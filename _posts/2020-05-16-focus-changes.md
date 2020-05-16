---
layout: post
title:  "Focus changes landing in Firefox 78"
date:   2020-05-16 22:26:00
---

I've been spending a bunch of time side-tracked working on focus-related things
these last couple weeks, and there have been a few significant changes that
I hope will make both web developers and users happier.

There are various goals that I tried to accomplish, I will try to explain the
reasoning for them, and then drop an executive summary of the changes below.

First, there will be **no change for natively-styled controls**. These are the
default and work reasonably well, with all the caveats that native theming
brings. So to the extent possible they should remain looking native / we
shouldn't regress their rendering.

<aside class="note">
Note that there's a project to [use a consistent theme across
platforms](https://bugzilla.mozilla.org/show_bug.cgi?id=1535761) in Firefox,
mostly for sandboxing reasons. You can try that, and maybe file bugs, with
`widget.disable-native-theme-for-content=true` in `about:config`, but that is
kind of tangential to this effort and the fixes described below apply to that
theme as well as the native themes. Also, it's going to change substantially in
the coming months if I'm not wrong.
</aside>

With that out of the way...

## Preventing missing focus indicators by default

This was my main goal (that is, fixing [bug
1311444](https://bugzil.la/1311444)).

Different platforms have different conventions on when to show outlines (more on
this below). One thing is clear though: **When navigating using the keyboard,
missing focus indicators are a bug**.

When these are hidden by default by the browser, it should be fixed, and that's
what I did. This was a bit harder than it seems (as usual) because we had to
enable `outline-style: auto` everywhere first.

The TLDR is that **form controls have `outline-style: auto` by default** in the
UA style sheet when `:-moz-focusring` applies. This matches both Blink and
WebKit, as far as I can tell.

This is useful because using the `auto` value allows us to have magic behavior
for themed controls that draw their own focus indicators (so as to not draw both
a "web" outline and the theme's outline), while allowing authors to override it,
and while displaying the outlines in non-themed form controls.

## Improving stylability

My other main goal was to **improve stylability and interoperability with other
browsers**. This one is the one that I hope will bring more joy to web
developers :)

Firefox has some, er, _interesting_ behavior with respect to focus indicators,
mostly due to the unstyled buttons wanting to look like the native Windows
buttons.

These span from the stylable but ugly inner border on buttons
([`::-moz-focus-inner`](https://developer.mozilla.org/en-US/docs/Web/CSS/::-moz-focus-inner)),
from the totally [unstylable and un-removable inner focus ring for `<select>`
elements](https://bugzilla.mozilla.org/show_bug.cgi?id=1580935), for which
people use [terrible hacks to
hide](https://stackoverflow.com/questions/19451183/cannot-remove-outline-dotted-border-from-firefox-select-drop-down).

These indicators were also annoying for users too, specially on Android, where
WebKit-based browsers dominate, and web developers don't usually bother removing
them if they don't want them. The mobile team and users had filed
[multiple](https://bugzilla.mozilla.org/show_bug.cgi?id=1583381)
[bugs](https://bugzilla.mozilla.org/show_bug.cgi?id=1618076) about this.

I believe that we should give web developers a way to style their controls as
they please, and that we shouldn't make web developers go out of their way to
get a nice experience on Firefox.

The biggest change here is that **un-themed form controls no longer show "inner"
focus indicators** (like `::-moz-focus-inner`). That is, setting
`-moz-appearance: none` (or background, or borders), on your `<select>`
/ `<button>` becomes enough to remove these. This is again something that we
could only do after fixing the missing default focus indicators. Now the inner
indicator is effectively superseded by the `outline`.

Another related patch that [I plan to
land](https://phabricator.services.mozilla.com/D74734) is to **make the
`::-moz-focus-outer` pseudo-element a no-op**, using `outline` instead. This
pseudo-element (which only applies to `<input type=range>`) was a hack to show
outlines on non-natively styled `<input type=range>` by default. The previous
work also effectively supersedes it, and allows authors and the implementation
to just use `outline` for it, as one would expect.

## Bonus (hopefully): Linux outline changes

This change has [still not
landed](https://bugzilla.mozilla.org/show_bug.cgi?id=1638127), but I hope the
Linux maintainers agree with it, as the behavior matches (to the best of my
knowledge) that of GTK.

Firefox's focus model has two switches, historically, based on platform
conventions:

 * **Whether focus rings are shown on all focused elements unconditionally**.
   This is true for Linux, dependent on a system setting on Windows (but default
   false), and false everywhere else. Additionally, once you move the focus
   using the keyboard on any platform, it becomes true for that window.

 * **Whether, if the above switch is false, focus indicators are shown for each
   element, unless it's focused via mouse / pointer, and the element is a link,
   a `<video>` or an `<audio>` element**. Yeah, that's the condition, really.
   This is true for all platforms except Windows.

That means that **on Linux you get all the outlines, all the time**, regardless
of system settings or whether you've used the keyboard to navigate the page.
This is very annoying, as you get outlines even when clicking links on Google.

My proposal is to **align with GTK's behavior** (which also happens to be
Windows' behavior by default). That is, **outlines will only show once you've
navigated by keyboard**. You will still be able to go back to the current
behavior by toggling the `browser.display.show_focus_rings` preference back to
`true` in `about:config`.

<aside class="note">
Note that on MacOS this is not so much of an issue, because mouse doesn't focus
form controls by default, following the platform's convention, so in practice
when you click on buttons and such you don't get outlines.

Some research on whether we can unify the outline behavior across desktop OSes
would be useful. If you are a Firefox MacOS user and think we show too many
outlines when interacting with the page, please reach out!

I might try to change some of these switches in the future, probably as part of
implementing the
[`:focus-visible`](https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible)
pseudo-class or such. The current behavior doesn't seem all that helpful to me.
For example, it seems to me like programmatic focus should show focus
outlines, at least some of the time...

But in any case, all this requires more work: UX and the accessibility team to
be on the loop, lots of feedback from both users and developers, spec
discussions, etc...

Still, all feedback that you may have on this kind of stuff is welcome, see
below! :)
</aside>

### Questions? Issues? Follow-up suggestions?

Please test this stuff out on [Nightly](https://nightly.mozilla.org), and if you
disagree with some of the changes / think they're harmful for either users or
developers, or such things, please reach out! Either
[Bugzilla](https://bugzil.la), [email](mailto:emilio@crisal.io) or
[Twitter](https://twitter.com/ecbos_) works :)
