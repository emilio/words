---
layout: post
title:  "Thoughts on code reviews"
date:   2026-07-18 15:46
---

Welp, long time no see. I just wanted to dump some thoughts I had on code
reviews. I don't expect them to be revolutionary or anything, but I've found it
useful to have a snapshot of what I thought about a topic in the past, and code
reviews are something that (for better or worse) I'm doing a lot of lately.

## Where I am right now

According to some stats by my colleague Paul Adenot, over the last year I've
reviewed a bit more than 5200 Firefox patches in our Phabricator instance,
doing a total of ~11k review "actions" (comment, accept, reject).

The code I review varies a lot in scope. Mostly:

 * Layout and CSS engine changes.
 * DOM Core.
 * Widget (cross-platform abstractions), particularly on the GTK component.
 * XPCOM and MFBT (the core data infrastructure and data structures shared by
   the rest of Gecko).
 * Firefox theming / front-end.

But there's a long tail of other stuff.

For context, the number of commits I've authored in the same period is ~1300. I'm
still one of the top individual committers, and I'm reviewing around 5x the
code I write.

Note that this also doesn't account for code reviews and commits I do outside
of the Firefox repository, like in standards work, or other projects I maintain
like [rust-bindgen](https://github.com/rust-lang/rust-bindgen) or
[cbindgen](https://github.com/mozilla/cbindgen).

I want to note that I'm also not alone in the "probably way too much review
load" camp. Olli and Dao are also doing a _ton_ of reviews in their respective
areas, for example.

## Thoughts on the sustainability of this all

This is not an ideal situation, especially when the amount of code that we need
to review keeps growing thanks to AI. The `#desktop-theme-reviewers` queue
just scares me.

Other team members are also picking up a fair amount of reviews (shout-out to
David Shin on my team), but reviews are still very far from being close to
evenly distributed, even when you just take into account very senior engineers.

Having a healthy bus factor of reviewers is great not only for the team's
speed, but also for distributing expertise across the team. **Code reviews are
a learning exercise, both for the author and the reviewer**.

I don't have bullet-proof ideas on how to make this better auto-magically. AI
can help find some of the more obvious mistakes, but it can't replace human
review and expertise. The right fix is really for everyone in the team to pitch
in some of the time and expertise and do reviews.

There are some things that can be tried to "grow reviewers" like pair
reviewing, or some sort of _shadow reviewer_ system where you learn from another
reviewer for a bit... I'm hoping that writing a bit about how I think about
code reviews helps other people to take on more reviews, even if they start
mostly asking questions.

## When and how I do code reviews

My general approach to this is basically **look at the review queue** while my
local build is ongoing, or when I'm waiting for try results.

The page I used to look at is [the active revisions Phabricator
page](https://phabricator.services.mozilla.com/differential/query/active/),
though nowadays I tend to use the [dashboard I
built](https://emilio.codeberg.page/reviews/), to be able to filter by review
group. Probably either works for you, unless your review queue is very large
(in which case hopefully my dashboard helps a bit).

I tend to do them in chunks, first explicit reviews and then by group. That is:

 * First I'll look at reviews that are assigned to me individually (the
   "Explicit" pill on my dashboard). These are reviews where I've either
   requested changes in the past, or where I got tagged by name with
   `r=emilio` directly.

 * Then I'll look at all the `#style` reviews, then `#layout`, then `#webidl`,
   then `#xpcom`, etc... This helps avoid context-switching too much (since the
   default Phabricator dashboard order is by last updated which is a mess for
   me).

 * I tend to prioritize blocking reviews over non-blocking, for obvious reasons
   (something that Phabricator doesn't make easy but my dashboard does).

That's pretty much it, really. You just need to slot some time to do it the
same way you find time to write code, triage bugs, etc. Other more organized
ways (reserving a few work hours a week or so) might work better for other
people?

## Things I generally look for

This is not a formal checklist per se, but things I usually look at in order to
approve / reject a change, or whether to ask more questions to the patch
author. They're not in any particular order, I think at this point my brain
does most of these in auto-pilot.

### What's the over-all complexity of the change?

There are reviews that are extremely trivial, typo fixes / trivial algorithm
fixes with a test. There are others which are either very subtle code changes,
or plain huge patches, which AI loves to generate...

It's perfectly acceptable to ask someone to split up a very complex patch (see
[recent example](https://phabricator.services.mozilla.com/D311736#10817386)).
It's better than leaving the patch hanging for an indefinite amount of time.

### What's the blast radius?

It's important to understand what the impact of the change being correct or
wrong is. That usually means understanding how the code being changed is
reached. Common things to look for are:

 * How many callers does this code have?
 * Is this exposed to the web or not?
 * Is it exposed to privileged JS?
 * Is it enabled by default or part of an experiment / in development feature?
 * Is the fix intended to be uplifted (e.g. is it a security issue or urgent bug fix)?

Depending on those, the amount of scrutiny and edge cases we should deal with
vs not might change.

### How deeply does the author understand the code they're changing?

If I know the patch author is very familiar with the code being changed, I
_may_ decide to approve the change based on other factors that usually would be
"request changes with questions".

The kinds of mistakes to look for from an expert in the code vs not are
different. Similarly, LLM patches tend to contain different sets of mistakes
than human patches.

### Do I understand how the patch fixes the issue?

If I don't, this is usually an insta-request-changes with questions (see
[recent example](https://phabricator.services.mozilla.com/D312479)). Unless
it's in an area where I genuinely have no context (e.g. if you send a video
decoder fix my way), in which case I'll find a better reviewer for the patch
(e.g. `#media-playback-reviewers`).

If I understand how it fixes it but it's not obvious from the code or the
commit message, it might be approved but with a request to extend the commit
message / comments before landing.

There are multiple layers to this. E.g., I may understand how the patch fixes
the issue, but I might not deeply understand all the code involved. That might
be fine (if the author does understand it, or there's similar enough code
around), but it might also be an opportunity to dig and learn about some new
part of the code, if I have the cycles to do so.

Notably, sometimes it's required to **check that the commit message is
correct**. LLMs are pretty good at writing bullshit.

If with a good commit message and putting reasonable effort in understanding
the code I still can't make the call about whether the patch is correct, it's
generally the time to either:

 - Ask for more clarifications about the correctness of it to the author.
 - Find a more appropriate reviewer that has more context than me on this area.
 - If that doesn't exist, do more digging: Apply the patch locally, debug the
   related code, look at the debugger myself.
 - If even that doesn't help, maybe we can meet and walk through the patch /
   their thought process together.

### Is the fix at the right level of abstraction?

The Firefox codebase is complex. It's easy to paper over a bug in e.g.
JavaScript when the real bug is in Gecko, for example. Or to add a special
case to one function when it's just papering over a bug in a subsystem it's
calling, or when we're dealing with a wrong state that we're not supposed to get
into to begin with.

See [bug 2007147](https://bugzil.la/2007147) for a canonical example of this
(Gecko bug papered in the front-end).

See [this kind of
comment](https://phabricator.services.mozilla.com/D302222?vs=on&id=1281850#inline-1633835)
for a canonical example of this in platform code (widget code papering over
some event handling bug in Gecko).

This is a very human mistake (fix the bug in code you're familiar with), but
LLMs are also very prone to do this kind of mistake.

Sometimes, papering over the bug somewhere else might be the right thing to do
given time / resource constraints. If the root cause fix is not a lot harder I
tend to request changes and fix it right instead. If we can't fix the root
cause as part of the change, I tend to request at least code comment pointing
to the root cause, plus to a follow-up bug to clean up when the root cause is
fixed.

### Could the change be simpler?

This is obviously a bit subjective, but I think **most code should be simple**.
If the patch _smells_ too complicated, it probably is. Some questions that
I tend to ask myself when looking at code:

 - Is there a better layer / place to write the fix? Somewhat related to the
   point above.
 - Are there redundant checks / is the code dealing with state that's
   impossible?
 - Is there a simpler way of doing what the patch is trying to do?
 - Do we have code generation machinery for some of the things the patch is
   doing (e.g. the style system has a lot of `#[derive]`s that can implement
   things for you, for the DOM we have WebIDL event codegen).
 - Are there refactorings in code this is being called from / this calls that
   could make the patch and surrounding code simpler?

Sometimes the right call is not to expand scope too much, but I tend to request
at least a bug tracking the code simplifications / root cause fixes, if they're
not feasible as part of the particular bug.

But most of the time, the right call is to just "fix it right", or do some
preliminary clean-ups / refactoring in a separate bug / patch.

Note that there's also the _opposite_ case. Sometimes a fix deals with a narrow
version of the problem / subset of the potential issues, and the root cause fix
is a bit more complicated.

### Does the fix match the specification?

For web exposed changes, it's important that the behavior is specified in the
relevant standard(s) (and properly tested in WPT). That's important both from
an Open Web / Mozilla mission perspective, but also from a selfish product
perspective: Firefox being a minority browser means that sites don't adapt to
our behavior. Chromium (and WebKit to some extent due to iOS) have a bit more
leeway in that regard.

The closer the code matches the spec the better, of course, so I try to find
ways to make either the code simpler / closer to the spec, or maybe even
change the spec to be simpler.

If the spec is ambiguous, or we're intentionally diverging from it, we should
make sure there's at least a spec issue tracking it (and that a comment
explains the divergence and points to it), or a follow-up bug to implement the
behavior.

### State management

Common / miscellaneous things to look at, and the specifics obviously depend on
the language / area you're reviewing code in, but in general I tend to confirm
that any state that gets introduced is managed properly. That includes memory,
of course.

 - Do the conditions the patch introduces check state that may change? Do we
   need invalidation for it? (common in layout / CSS)

 - Do event listeners get cleaned up? (common in JS)

 - Do member variables need cycle collection? (common in DOM patches)

 - Does async code handle references correctly? Does it introduce any cyclic
   references?

 - Does it introduce any cache that isn't cleared? Is that fine?

 - Can state be messed up by arbitrary script execution? (common in DOM and Layout)

 - Any Rust `unsafe` code?

### Performance

I try to look at whether the change introduces any performance cliff, or may
make very hot code slower. Or are there obvious low hanging fruit that would
make the code faster?

Again, depending on the author and their expertise on the relevant code it
might be either an approve or reject with a request for performance
measurements (might be as simple as "make sure this doesn't regress Speedometer
before landing", or something more tailored).

Similarly, it's very common in the front-end to introduce changes that look
innocuous but will cause subtle performance cliffs, see [bug
2054124](https://bugzilla.mozilla.org/show_bug.cgi?id=2054124#c7) for example.

### Tests

Obvious one, but the patch _should_ include automated tests when feasible (some
system integration changes realistically can't). Some folks like to include
tests in a separate patch in the stack, I tend to look at those at the same
time as the main change.

Looking at the tests is a great way to check what the intended behavior change
is. Looking for missing coverage (behavior changes in the patch that aren't
covered by the tests) is a good way of catching unintended mistakes or behavior
changes (or better testing opportunities).

The tests should also be as simple as possible, and be tested with the right
test framework (which for platform changes is almost always
[WPT](https://web-platform-tests.org)).


## The final review decision

Once I've looked at these, I have written zero to a bunch of comments in
Phabricator. The final approve / reject decision depends on the magnitude and
severity of the changes, and some of the factors below.

If a patch is in decent shape and I mostly have nits / relatively minor
improvements, I'll most likely approve it. The key question there is **do I
need to look at this again once the changes are made**?

The one exception is if I don't know whether the author has L3 access, in which
case I'll request changes just so that I remember to land the patch when they
update it.

## Random notes for reviewers afraid of screwing up

I wish I knew why review load isn't better spread out, but here are a few notes
based on my intuition.

### Reviewers can make mistakes

Just like when writing code, you can also miss something when reviewing. Do
your best, I see code review as a very important step towards ensuring the code
is maintainable, but we're all human.

In the Firefox case, we're lucky that we have pretty much state of the art
static analysis, fuzzing, testing, bisection tools, and a great community that
reports great bugs.

Don't be afraid of reviewing code.

### Don't be afraid to ask questions

I find code review a great learning / expertise-sharing opportunity. Sometimes
it's easy to say "I'm not sure this is correct, I'll let someone else deal with
it", but... if you've skimmed the patch and don't understand it, it might be a
great opportunity to learn instead / in addition to it?

Maybe the author could make the patch cleaner, or maybe we could improve the
docs. Ask questions. If the patch or docs could become better, that's a win. If
the patch author teaches you something, that's also a win.

### Don't be afraid to review code you're not an expert on

I personally like digging into new code, and some changes you can be reasonably
confident of their correctness based on most of the items mentioned above.

Digging into and understanding unknown code is a great way of improving as an
engineer and learning new things. Pair it with asking questions to the author.

Maybe it still needs eyes from someone else, that's fine. Feel free to comment
/ request changes / approve / resign as a reviewer and _then_ tag someone else
as a blocking reviewer if you think the patch would benefit from extra eyes.
