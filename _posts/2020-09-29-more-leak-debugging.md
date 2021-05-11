---
layout: post
title:  "More Gecko leak debugging"
date:   2020-09-29 01:49:00
---

So my [previous post about leak
debugging](https://crisal.io/words/2019/11/13/shutdown-leak-hunting.html) has
been useful to me and to some other people.

Today I just [got backed out](https://bugzilla.mozilla.org/show_bug.cgi?id=1667510#c13)
for another kind of leak in a relatively innocent patch (again). And so since
I don't know how to possibly explain this leak, and this time it is an actual
leak, I thought it'll be useful to document the steps I take to fix it.

# Reproducing and reducing the failure

From the logs linked in the backout, we can see that the failing task is the
non-e10s mochitest run, and some of the potentially related tests include:

 * `layout/base/tests/chrome/test_printpreview_bug396024.xhtml`
 * `layout/base/tests/chrome/test_printpreview_bug482976.xhtml`
 * `layout/base/tests/chrome/test_printpreview.xhtml`

On closer inspection, the only one that can be related to my patch is
`test_printpreview.xhtml`, because it's the only one which tries to print
various UA-widget-like thingies like `<audio controls>`, `<input>`, the XML
pretty-printer, etc...

Indeed, just running `./mach mochitest --disable-e10s
layout/base/tests/chrome/test_printpreview.xhtml` reproduces _some_ of the time
(I tried about 4 times, and it reproduced once).

This test is pretty big and slow for a debug build, so I'll try to isolate it to
the `<audio>` or prettyprinter...

After some experimentation, this patch (which skips most of the tests) still
reproduces the issue from time to time, yay!

```diff
diff --git a/layout/base/tests/chrome/printpreview_helper.xhtml b/layout/base/tests/chrome/printpreview_helper.xhtml
index ff213b733fb9..7b89441ce17a 100644
--- a/layout/base/tests/chrome/printpreview_helper.xhtml
+++ b/layout/base/tests/chrome/printpreview_helper.xhtml
@@ -189,7 +189,7 @@ function runTest2() {
   isnot(frameElts[0].contentWindow.counter, 0, "Timers should have run!");
   counter = frameElts[0].contentWindow.counter;
   frameElts[0].contentWindow.counterTimeout = "";
-  setTimeout(runTest3, 0);
+  setTimeout(runTest21, 0);
 }
 
 var elementIndex = 0;
@@ -592,7 +592,7 @@ async function runTest20() {
 
 async function runTest21() {
   await compareFiles("data:text/html,<audio controls>", "data:text/html,<audio controls >"); // Shouldn't crash.
-  requestAnimationFrame(() => setTimeout(runTest22));
+  finish();
 }
 
 async function runTest22() {
```

# Trying (and failing) to fix the bug by code inspection.

So the next I thought is "this is a simple patch Emilio, I'm sure there's not so
much that can go wrong that you changed".

My patch effectively skips dispatching some events that set up [UA
widgets](https://firefox-source-docs.mozilla.org/toolkit/content/toolkit_widgets/ua_widget.html)
when printing (because for printing we already do a clone of the shadow root
with all the content and we don't really need anything else).

So the first thought is that somehow I'm skipping the teardown for an element
but not the setup, and that leaves some state behind.

I instrument the code with a bunch of printfs, reproduce the bug, but the calls
are all matched properly. That's not great. However I see that sometimes we bail
out from actually cleaning up
[here](https://searchfox.org/mozilla-central/rev/f27594d62e7f1d57626889255ce6a3071d67209f/dom/base/Element.cpp#1217-1223).

I thought I had it! But poking at a debugger I realize these are normal
[`<video>`](https://searchfox.org/mozilla-central/rev/f27594d62e7f1d57626889255ce6a3071d67209f/browser/base/content/popup-notifications.inc#31)
elements from the Firefox front-end, and that the bail out happens during cycle
collection. Some more reading up on [the bug that
introduced that code](https://bugzilla.mozilla.org/show_bug.cgi?id=1514098) made
me think that this is a normal situation, so oh well.

Taking a closer look, it seems the leaked atoms seem to indicate that we leaked
a whole Chrome window...

```
WARNING: YOU ARE LEAKING THE WORLD (at least one JSRuntime and everything alive inside it, that is) AT JS_ShutDown TIME.  FIX THIS!
[60181, Main Thread] ###!!! ASSERTION: 26 dynamic atom(s) with non-zero refcount: downloads-item-font-size-factor,protections-popup-trackersView,private-browsing-indicator,PanelUI-bookmarks,translate-notification-icon,manBookmarkKb,downloadsCmd_clearList,context-openlinkprivate,find-button,key_responsiveDesignMode,pageStyleMenu,pagemenu,extension-new-tab,downloadHoveringButton,desktop,key_inspector,Unmute,chromeclass-toolbar,test_todo,context-frameOsPid,...: 'nonZeroRefcountAtomsCount == 0',

...
(lots more like that)
...
```

Those definitely look like parts of the browser UI to me. Definitely not part of
the test.

I start so suspect what's going on... This test calls into
[`window.printPreview()`](https://searchfox.org/mozilla-central/rev/f27594d62e7f1d57626889255ce6a3071d67209f/dom/chrome-webidl/FrameLoader.webidl#133)
which, when not passed a docshell to clone the printed document into, creates
a whole window. I suspect we're loading the whole browser UI in there, and then
replacing it by the whole preview document, or something...

But that's not something that my patch changes for starters, and the test takes
care of manually closing those windows, so why my patch breaks this somehow is
still a mystery. I guess it's CC log time.

# CC log time

The setup here is going to be similar to the one in my previous post. Just that
this time is a real leak, so hopefully we can debug it with
`MOZ_CC_LOG_SHUTDOWN=1` instead of doing all the logs.

So my command looks something like this:

```
mkdir -p /tmp/leaklogs; rm -f /tmp/leaklogs/*.log; MOZ_CC_LOG_DIRECTORY=/tmp/leaklogs MOZ_CC_LOG_THREAD=main MOZ_CC_LOG_SHUTDOWN=1 ./mach mochitest --debugger=rr layout/base/tests/chrome/test_printpreview.xhtml
```

The good part, it reproduced first try somehow! So same deal, let's put
everything into a temp directory and rr our way out of here:

```
$ mkdir ~/tmp/leak
$ rr pack # This makes a mostly-self-contained trace.
$ mv <rr-trace-directory> ~/tmp/leak/rr-trace
$ mv /tmp/leaklogs ~/tmp/leak/leaklogs
$ rr replay -a -M ~/tmp/leak/rr-trace >~/tmp/leak/log 2>&1
```

Time to analyze our logs. Last time we knew what kind of object was actually
leaking, but this time we don't. However looking at the [MDN
docs](https://developer.mozilla.org/en-US/docs/Mozilla/Performance/GC_and_CC_logs),
it seems `nsGlobalWindowInner` should be a safe bet to try to figure out this.

Indeed, running:

```
$ python2 ~/src/moz/heapgraph/find_roots.py leaklogs/cc-edges.76021-1.log nsGlobalWindow
```

We get a bunch of output looking like this:

```
0x7fe7af511000 [FragmentOrElement (xhtml) audio data:text/html,<audio controls >]
    --[mPlayed]--> 0x7fe7af427670 [TimeRanges]
    --[mParent]--> 0x7fe7d5219000 [Document data (xhtml) data:text/html,<audio controls >]
    --[Preserved wrapper]--> 0x274b00ea8080 [JS Object (HTMLDocument)]
    --[group_global]--> 0x274b00e97060 [JS Object (Window)]
    --[getter]--> 0x274b00e9e080 [JS Object (Proxy)]
    --[proxy target]--> 0x1561ffabcce0 [JS Object (Function - get)]
    --[fun_environment]--> 0x1357fa8a7380 [JS Object (LexicalEnvironment)]
    --[window]--> 0x246f5ae47700 [JS Object (Proxy)]
    --[proxy_reserved]--> 0xe187286f4f0 [JS Object (XrayHolder)]
    --[close]--> 0x10e559d823d0 [JS Object (Function - close)]
    --[group_global]--> 0x18c91f3f4600 [JS Object (Window)]
    --[MozHTMLElement]--> 0x1202685bc830 [JS Object (Function - MozElementBase)]
    --[script]--> 0x3c8aa0733880 [JS Script]
    --[sourceObject]--> 0x246f5ae78700 [JS Object (ScriptSource)]
    --[group_global]--> 0x31cebf87b240 [JS Object (Window)]
    --[gBrowser]--> 0x31891b2bca00 [JS Object (Object)]
    --[_selectedBrowser]--> 0x10a84395b130 [JS Object (XULFrameElement)]
    --[tabDialogBox]--> 0xe187280f180 [JS Object (Object)]
    --[_dialogManager]--> 0x1c8ee4f5aac0 [JS Object (Object)]
    --[_preloadDialog]--> 0x1c8ee4fa3b00 [JS Object (Object)]
    --[_frameCreated]--> 0x1c8ee4fd0ac0 [JS Object (Promise)]
    --[**UNKNOWN SLOT 1**]--> 0x12026856e9a0 [JS Object (Event)]
    --[group_global]--> 0x31cebf87b920 [JS Object (Window)]
    --[UnwrapDOMObject(obj)]--> 0x7fe7d534ec00 [nsGlobalWindowInner # 32 inner about:blank]

    Root 0x7fe7af511000 is a ref counted object with 1 unknown edge(s).
    known edges:
       0x7fe7af427700 [MediaTrackList ] --[mMediaElement]--> 0x7fe7af511000
       0x7fe7af533dc0 [FragmentOrElement (xhtml) body data:text/html,<audio controls >] --[mFirstChild]--> 0x7fe7af511000
       0x7fe7ea33fac0 [MediaTrackList ] --[mMediaElement]--> 0x7fe7af511000
     0x7fe7af5242e0 [FragmentOrElement ([none]) #document-fragment data:text/html,<audio controls >] --[mHost]--> 0x7fe7af511000
```

So it seems that's the object we're leaking! It seems it's our `<audio controls >`
element from the test. Given the amount of JS stuff going on I'm assuming it is
the non-static version of it... But we'll see. There's a whole lot of stuff
going on there, and it's not clear where that unknown edge comes from.

That `** UNKNOWN SLOT 1**` bit looks a bit suspicious...

So lacking a better lead, I'm going to seek to the leak, and try to get
a reference to the `<audio>` element and see what's going on there...

Soon we find out that this is actually the static element...

```
(rr) p (mozilla::dom::HTMLAudioElement*)0x7fe7af511000
p $1 = (mozilla::dom::HTMLAudioElement *) 0x7fe7af511000
(rr) p $1->mNodeInfo->mDocument->mIsStaticDocument
$2 = true
```

That's not great news, there's a lot of JS going on in that page, for what's
supposed to essentially be a static document... I decide to start tracking down
what changes the refcount to see if I see the bogus edge:

```
(rr) watch -l $1->mRefCnt.mRefCntAndFlags
```

