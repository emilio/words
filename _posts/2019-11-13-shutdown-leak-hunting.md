---
layout: post
title:  Hunting an intermittent leak until shutdown.
date:   2019-11-13 14:38:00
---

This week I had to debug an [intermittent
leak-until-shutdown](https://bugzilla.mozilla.org/show_bug.cgi?id=1595573) which
seemed to be caused by a fairly innocent [test
change](https://hg.mozilla.org/integration/autoland/rev/e19c5df398de#l22.10).

As it turns out, the issue was not my fault (yay), but it was quite a pain to
debug, even though [the fix](https://phabricator.services.mozilla.com/D52833)
was trivial.

So I wrote this in the hopes of not forgetting how I did it, and in case that
other people could find it useful.

# Reproducing it

The first step to fix this is to reproduce it. As it turns out it wasn't trivial
to reproduce while running the test on its own.

```
$ ./mach mochitest toolkit/components/places/tests/browser/browser_bug461710.js
# No leak
```

So the next thing I tried was running it under [rr's chaos
mode](https://robert.ocallahan.org/2016/02/introducing-rr-chaos-mode.html):

```
$ ./mach mochitest --debugger=rr --debugger-args="record --chaos" toolkit/components/places/tests/browser/browser_bug461710.js
```

But that still sowed no signs of leaks.

Thankfully Marco
[commented on the bug](https://bugzilla.mozilla.org/show_bug.cgi?id=1595573#c3),
mentioning that running the whole directory used to help.

And indeed with something like this I managed to reproduce the failure pretty
consistently!

```
$ ./mach mochitest --debugger=rr --debugger-args="record --chaos" toolkit/components/places/tests/browser
```

Using the test output you can see the ID's of the windows and such that are
leaking, such as:

```
10:52.16 ERROR TEST-UNEXPECTED-FAIL | toolkit/components/places/tests/browser/browser_bug461710.js | leaked 2 window(s) until shutdown [url = about:blank]
10:52.16 ERROR TEST-UNEXPECTED-FAIL | toolkit/components/places/tests/browser/browser_bug461710.js | leaked 2 window(s) until shutdown [url = chrome://browser/content/browser.xhtml]
10:52.16 INFO TEST-INFO | toolkit/components/places/tests/browser/browser_bug461710.js | windows(s) leaked: [pid = 153511] [serial = 19], [pid = 153511] [serial = 15], [pid = 153511] [serial = 18], [pid = 153511] [serial = 14]
```

So `[pid = 153511] [serial = 19]`, `[pid = 153511] [serial = 15]`, `[pid = 153511]
[serial = 18]`, and `[pid = 153511] [serial = 14]` are the windows we're
interested in.

Looking at the output, we can see the window addresses, for example:

```
--DOMWINDOW == 2 (0x2e2228e5000) [pid = 153511] [serial = 19] [outer = (nil)] [url = about:blank]
```

This is the window we're going to focus on.

So with rr I can poke at the window object and so on, but I can't figure out
easily what's keeping it alive.

## CC and GC logs

So to debug this, we're going to need some more help from the CC and GC logs.

We have [some
documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Performance/GC_and_CC_logs)
to take those logs and such.

Usually the shutdown logs is all you want (`MOZ_CC_LOG_SHUTDOWN=1`). That's
useful to know why something is still alive _after_ shutdown.

But, in this case, the window is not _actually_ completely leaked, it's just
leaked until shutdown, which means that there's something keeping it alive, but
we manage to free it in the end when shutting down the browser, and thus the
shutdown logs just tell us what objects did we cycle-collect, but not why those
objects were kept alive for so long.

So I ran this a couple times until it reproduced:

```
mkdir -p /tmp/leaklogs; rm -f /tmp/leaklogs/*.log; MOZ_CC_LOG_THREAD=main MOZ_CC_LOG_DIRECTORY=/tmp/leaklogs MOZ_CC_LOG_ALL=1 ./mach mochitest --debugger=rr --debugger-args="record --chaos" toolkit/components/places/tests/browser --timeout 100000
```

Note that I had to increase the `--timeout` since CC logs are quite slow, and
more so under rr seems like.

As soon as I reproduced, I did the following:

```
$ mkdir ~/tmp/leak
$ rr pack # This makes a mostly-self-contained trace.
$ mv <rr-trace-directory> ~/tmp/leak/rr-trace
$ mv /tmp/leaklogs ~/tmp/leak/leaklogs
$ rr replay -a -M ~/tmp/leak/rr-trace >~/tmp/leak/log 2>&1
```

And I manually copied the leaked window identifiers in `~/tmp/leak/leaked-windows.log`.

So now we have a directory in `~/tmp/leak` with all the things we actually need
to debug this, let's move to that directory.

So we have a window address (`0x2e2228e5000`), and we can easily go to the
points where it's created and destroying thanks to rr. So if I want to go to
this part of the runtime (looking at the `log` file, which contains all the rr
marks):

```
[rr 153511 4073694]--DOMWINDOW == 2 (0x2e2228e5000) [pid = 153511] [serial = 19] [outer = (nil)] [url = about:blank]
```

I can just `rr replay rr-trace -p 153511 -g 4073694` to go to that point of the
program using rr.

Anyway. We have an address, let's look at where it was used by grepping on the
`leaklogs` directory:

```
$ rg 0x2e2228e5000 leaklogs | cut -d : -f 1 | uniq
leaklogs/cc-edges.153511-32.log
```

Seems we only log the window on the last CC (where it's actually freed), that's
suspicious. So we need to figure out what caused it to stay alive for so long.

To analyze the logs, I used [Andrew's `heapgraph`
repo](https://github.com/amccreight/heapgraph), which has the super-useful
`find_roots.py` script.

So if I run:

```
$ python2 ~/src/moz/heapgraph/find_roots.py leaklogs/cc-edges.153511-32.log 0x2e2228e5000
```

I get an output like:

```
Parsing leaklogs/cc-edges.153511-32.log. Done loading graph.
Didn't find a path.

    known edges:

       0x2e2227e9280 [CallbackObject] --[mIncumbentGlobal]--> 0x2e2228e5000
       ...
       0x707acbb0 [Promise] --[mGlobal]--> 0x2e2228e5000
       ...
       0x2e2228e5000 [nsGlobalWindowInner # 49 inner chrome://browser/content/browser.xhtml] --[mTopInnerWindow]--> 0x2e2228e5000
       ...
       [tons more]
```

So this was annoying, because `Didn't find a path.` means that the window
actually gets freed, but also the different bits there seem somewhat normal.

I spent quite some time chasing the things that kept references to the window
only to find various global objects that should get properly cleaned up.

The cyclic reference to itself also seemed suspicious, but nothing that the CC
shouldn't handle and it ended up not being the root cause of the leak.

So the next thing is to try to figure out why it was alive in the _previous_ GC.

For that, I had to figure out the address of the JS wrapper (the object that's
exposed to JS) using rr, as that's what appears on the GC logs, as opposed to
the CC logs that contain the native address.

The fact that the native window address didn't appear on the GC logs got me
pretty confused for quite a lot, and I thought I didn't have a lead anymore.

So let's jump on rr, and figure out the wrapper of the window (`4014963` is
a random point in time between the relevant `++DOMWINDOW` and `--DOMWINDOW`
lines where I know the window is alive).

```
$ rr replay rr-trace -p 153511 -g 4014963
...
(rr) print ((nsGlobalWindowInner*)0x2e2228e5000)->mWrapper
(JSObject*) 0x189b08eec9c0
```

So that's something, and that address does appear on all the GC logs, that's
awesome!

The last cc (where it gets freed) was number 32 (`cc-edges.153511-32.log`). The
previous one is 31, then.

Let's look at the gc logs for the GC #31 and see what's up:

```
$ python2 ~/src/moz/heapgraph/find_roots.py leaklogs/gc-edges.153511-31.log 0x189b08eec9c0 -obr
Parsing leaklogs/gc-edges.153511-31.log. Done loading graph.

via persistent-Object :
0x1582c8cf0550 [NonSyntacticVariablesObject <no private>]
    --[gPromises]--> 0x202153af68c0 [Map 0x4ca6275b0330]
    --[value]--> 0x3377c0074ee0 [Object <no private>]
    --[promise]--> 0x10620b429880 [Object <no private>]
    --[{private:internals:1}]--> 0x3377c004afc0 [Object <no private>]
    --[handlers]--> 0x25d5e2d92400 [Array <no private>]
    --[objectElements[0]]--> 0x1985b80bdac0 [Object <no private>]
    --[onReject]--> 0x10620b491ec0 [Function ]
    --[nativeReserved[0]]--> 0x1985b80bdfc0 [Promise <no private>]
    --[**UNKNOWN SLOT 1**]--> 0x25d5e2d32820 [PromiseReactionRecord <no private>]
    --[**UNKNOWN SLOT 7**]--> 0x10620b42ea00 [AsyncFunctionGenerator <no private>]
    --[**UNKNOWN SLOT 0**]--> 0x3edc014dd300 [Function]
    --[fun_environment]--> 0x25d5e2d0b180 [Call <no private>]
    --[enclosing_environment]--> 0x204e31204a40 [LexicalEnvironment <no private>]
    --[enclosing_environment]--> 0x111675425d40 [LexicalEnvironment <no private>]
    --[enclosing_environment]--> 0x2431cba9d220 [LexicalEnvironment <no private>]
    --[privateWindow]--> 0x189b08eec9c0 [Proxy <no private>]
```

So, that's interesting. `privateWindow` is the window we're leaking, and there
seem to be a bunch of references to it.

The one that caught my eye was `gPromises`, which seemed to be the top of the
chain.

That seems to be [a global JS
`Map`](https://searchfox.org/mozilla-central/rev/6566d92dd46417a2f57e75c515135ebe84c9cef5/testing/mochitest/BrowserTestUtils/ContentTask.jsm#24)
used to keep task ids to their relevant promise.

So it seems we've left a promise in that map that hasn't yet resolved or
rejected, and that is keeping everything alive. How could that happen?

The test was doing something conceptually simple:

```js
await TestUtils.waitForCondition(async function() {
  let color = await ContentTask.spawn(browserWindow, async function() {
    /* Do stuff... */
  });
  return color == something;
});

await closeWindow(browserWindow);
```

So we do use `ContentTask.spawn`, but it seems the tasks should always complete
for the test to finish... right?

And that's where something clicked, and I went to see the `waitForCondition`
implementation:

```js
/**
 * Will poll a condition function until it returns true.
 *
 * @param condition
 *        A condition function that must return true or false. If the
 *        condition ever throws, this is also treated as a false. The
 *        function can be a generator.
 * @param interval
 *        The time interval to poll the condition function. Defaults
 *        to 100ms.
 * @param attempts
 *        The number of times to poll before giving up and rejecting
 *        if the condition has not yet returned true. Defaults to 50
 *        (~5 seconds for 100ms intervals)
 * @return Promise
 *        Resolves with the return value of the condition function.
 *        Rejects if timeout is exceeded or condition ever throws.
 */
waitForCondition(condition, msg, interval = 100, maxTries = 50) {
  return new Promise((resolve, reject) => {
    let tries = 0;
    let intervalID = setInterval(async function() {
      if (tries >= maxTries) {
        clearInterval(intervalID);
        msg += ` - timed out after ${maxTries} tries.`;
        reject(msg);
        return;
      }

      let conditionPassed = false;
      try {
        conditionPassed = await condition();
      } catch (e) {
        msg += ` - threw exception: ${e}`;
        clearInterval(intervalID);
        reject(msg);
        return;
      }

      if (conditionPassed) {
        clearInterval(intervalID);
        resolve(conditionPassed);
      }
      tries++;
    }, interval);
  });
},
```

Hmm that `setInterval` there seems **highly** suspect.

In particular, because the inner function is async, we may be waiting an
arbitrary amount of time in `await condition()`, enough for the interval
function to run **again**.

So we could get to a state where we have two (or more) of these functions
running, and each of these post a `ContentTask`. As soon as the first of them
passes, then we resolve the promise, which could get to the `closeWindow()` call
which closed the browser, and made the pending `ContentTask`s never resolve ever
again, and thus leaving the `gPromises` map with entries for unresolved
promises, leaking the window.

Once I understood this, fixing it wasn't that bad (hopefully, assuming my
reviewer likes the patch :)).

Till next time. Oh, and thanks to Andrew Mccreight and Olli Pettay for all their
help figuring out the rough edges here :)
