---
layout: post
title:  "XUL Layout is gone"
date:   2023-03-30 14:30 PM
---

So this week I landed
a [few](https://hg.mozilla.org/mozilla-central/rev/0e21add6bf2c)
[patches](https://hg.mozilla.org/mozilla-central/rev/c134b1c8a8ed) that
completely removed XUL layout from the Firefox codebase.

This means that (modulo a few exceptions documented below) all the Firefox UI
is using regular web technology to render (mostly CSS flexbox).

This was a rather big effort (first filed 9 years ago in [bug
1033225](https://bugzil.la/1033225)), and I wanted to document some of the
things that I learned during the process, some of the things and decisions that
made it possible, and some of the things that I would've maybe done
differently.

This was possible thanks to a lot of help from the front-end team and
volunteers: In particular, Gijs, Dão, Itiel, Mike Conley, Brian Grinstead and
Neil Deakin have helped a lot with reviews and / or early explorations. Neil
[blogged](https://enndeakin.wordpress.com/2015/07/13/comparing-flexible-box-layouts/)
about some of the first exploration in 2015.

On the layout team front Daniel Holbert and Mats got this started years ago,
and Tim Nguyen helped with some of the early refactorings and code removal too
a while ago.

I'm sure I'm forgetting someone, too...

## What is (was!) XUL layout?

[XUL](https://en.wikipedia.org/wiki/XUL) is a specific XML namespace (like
HTML or SVG), in which the Mozilla UI (and still a fair amount of the Firefox
UI) was written back in the day.

We still use the XUL namespace in various ways (generally to implement things
that aren't web exposed, like native menu popups).

Along with the custom XML namespace, there is a set of CSS `display` values
(`-moz-box`, `-moz-inline-box`, `-moz-grid`, `-moz-stack`, `-moz-popup`) that
implemented completely separate layout algorithms from the usual HTML layout.

XUL `-moz-box` layout was somewhat close (in fact, [a
precursor](https://www.w3.org/TR/2009/WD-css3-flexbox-20090723/)) to what
eventually became CSS flexbox.

## Why remove it?

The XUL box model had a bunch of issues, and removing it is a win on various fronts.

### Bad interactions with regular box model

XUL never supported "basic" CSS features that work everywhere else, like proper
absolute positioning.

It also didn't interact well with even relatively basic block / inline layout.
For my favourite example of a hack removed by this effort is [the
`descriptionheightworkaround`
hack](https://hg.mozilla.org/mozilla-central/rev/16fd9fff367f), which was made
so that `<description>` elements (which are just regular `display: block`
elements) wrapped correctly inside XUL panels.

### Proprietary, poorly documented technology

The Firefox desktop front-end, at the end of the day, is a regular website with
superpowers.

Before, if you're a front-end developer and you want to contribute to the
firefox UI, you'd needed to learn what `display: -moz-box` does and how
it behaves, which is not super well documented.

Now you can just use the [browser
toolbox](https://firefox-source-docs.mozilla.org/devtools-user/browser_toolbox/index.html)
and use regular CSS to change the UI or contribute to it.

### Not actively maintained

Nobody was realistically touching XUL layout code if they could avoid it. Part
of it was just a matter of priority (we'd rather make the web faster for
example).

After these changes, the layout team needs to maintain about 13k less lines of
code (probably more, since I haven't accounted for removals to other
directories):

```
$ g diff --stat 23d7b33ea6df2..HEAD layout/xul | tail -1
 132 files changed, 4981 insertions(+), 17465 deletions(-)
```

### Using web technology is best

If we render stuff with the same technologies that websites use, it means
performance improvements and bugs that affect the web affect the Firefox UI and
vice versa.

In fact, during this effort we found some bugs in flexbox that should help
performance of the web more generally, like [bug
1797272](https://bugzil.la/1797272).

## How? Emulation

In theory, the following mapping should get you a somewhat close rendering
between the XUL box model and CSS flexbox:

 * `display: -moz-box` -> `display: flex`
 * `-moz-box-flex: N` -> `flex-grow: N; flex-shrink: N`
 * `-moz-box-align` -> `align-items`
   * `stretch` -> `stretch`
   * `start` -> `flex-start`
   * `center` -> `center`
   * `baseline` -> `baseline`
   * `end` -> `flex-end`

 * `-moz-box-pack` -> `justify-content`
   * `start` -> `flex-start`
   * `center` -> `center`
   * `end` -> `flex-end`
   * `justify` -> `space-between`

 * `-moz-box-orient` + `-moz-box-direction` -> `flex-direction`
   * `vertical` + `normal` -> `column`
   * `vertical` + `reverse` -> `column-reverse`
   * `horizontal` + `normal` -> `row`
   * `horizontal` + `reverse` -> `row-reverse`

 * `-moz-box-ordinal-group: N` -> `order: N`

We, in fact, need to support such mapping already on "modern" flexbox to
implement `display: -webkit-box`.

We [long ago](https://bugzil.la/1398963) added a pref to do a one-off switch to
emulate `-moz-box` with flexbox (like we do for `-webkit-box`). In theory, just
flipping that flag should be enough to give you a similar (ideally identical)
layout.

However, there were enough differences with CSS flexbox that made switching one
to the other non-trivial. Here's a documentation of the differences that
I found (and I recall, might've missed some).

### Differences in the box tree

This one was one of the first surprises I found. When you write something like:

```
<div style="display: flex">
  <span>Some text</span>
</div>
```

The `<span>` is [blockified](https://www.w3.org/TR/css-display-3/#blockify).
(its computed `display` value would become `block`).

Our existing CSS flexbox emulation (which is what `display: -webkit-box` uses)
didn't do that at all.

And XUL flexbox did something even more different, which was wrapping stuff in
a block.

That caused some interesting issues when you used `-moz-box` emulation.
I decided to unify how we handled this in [bug
1789123](https://bugzil.la/1789123) to make XUL and emulated-moz-box match
modern flexbox, which fixed a lot of UI regressions with flexbox emulation
enabled, and suprisingly only caused [one UI
regression](https://bugzil.la/1790898).

### Special boxes that hard-coded XUL layout

This was by far the most annoying of all the issues, and what caused most of
the code to remain there for a while.

Even in the flexbox emulation world, we had a lot of special XUL behavior
implemented in `nsBoxFrame` subclasses. Inheriting from `nsBoxFrame` meant that
it forced us into the legacy layout effectively, and since XUL and CSS layout
don't play along very well together, this was a blocker for enabling it in
various parts of the UI that used these elements.

This involved rewriting:

 * The root box frame to reuse the same mechanism as HTML ([bug 1665476](https://bugzil.la/1665476)).
 * Resizers (Mats did this in [bug 1590376](https://bugzil.la/1590376)).
 * Various buttons ([bug 1790920](https://bugzil.la/1790920)).
 * Menus ([bug 1805414](https://bugzil.la/1805414), [bug 1812329](https://bugzil.la/1812329)).
 * `<stack>`, `<tabpanels>` and `<deck>` ([bug 1576946](https://bugzil.la/1576946), [bug 1689816](https://bugzil.la/1689816)). Btw,
   that made me add a CSS extension to hide something visually but not for
   accessibility, which CSS usually only has hacks for.
 * `nsDocElementBoxFrame` (the root box frame which used a slightly different layout algorithm) ([bug 1792741](https://bugzil.la/1792741)).
 * Popups ([bug 1799343](https://bugzil.la/1799343), [bug 1799580](https://bugzil.la/1799580), [bug 1809084](https://bugzil.la/1809084))
 * Scrollbars ([bug 1824236](https://bugzil.la/1824236)).
 * XUL images ([bug 1815229](https://bugzil.la/1815229)).
 * Trees ([bug 1820634](https://bugzil.la/1820634), [bug 1824957](https://bugzil.la/1824957)).
 * Splitters ([bug 1794630](https://bugzil.la/1794630), [bug 1824489](https://bugzil.la/1824489)).
 * Label / description, which includes accesskeys and middle-cropping ([bug 1590884](https://bugzil.la/1590884), [bug
   1799460](https://bugzil.la/1799460), [bug
   1824667](https://bugzil.la/1824667)).

I've probably forgotten some... Tim Nguyen and Mats had done some of these.

### Magic attributes

XUL had magic `width` / `height` / `minwidth` / `minheight` / `flex` attributes
which were read from layout and acted as `!important`, overriding any other CSS
rule.

Luckily we didn't have many conflicting CSS rules, so those could mostly be
replaced by `width` / `height` / etc CSS properties on the style attribute or
on CSS, but given flex="0" and flex="1" were really used a lot I kept those as
an UA stylesheet in [bug 1784265](https://bugzil.la/1784265).

### width/height are more frequently honored

With XUL, something like `width: 100px` wouldn't quite do what it says. If it
had content that was wider than that it'd expand over that size, if the
container was bigger it'd flex over it.

What it means in practice is that a bunch of explicit width/heights need
to become min-width/heights.

An example of this could be [bug 1795339](https://bugzil.la/1795339).

### Intrinsic sizing differences

Scrollable elements contribute more to the flex min size with modern flexbox.
This is a rather annoying behavior with modern flexbox, IMO.

If you have an element which is flexible, but has scrollable overflow
(overflow: auto/hidden/scroll), it might still grow the surrounding flex
container based on the scrolled contents, rather than scroll.

For that I had to sprinkle a lot of min-{width,height}: 0 on the flex item(s),
or alternatively contain: {size,inline-size}. contain is a simpler fix (you
don't need to specify min-{width,height} on all flex items), but is a bit more
aggressive.

Examples of this could be [bug 1794499](https://bugzil.la/1794499) or
[bug 1793505](https://bugzil.la/1793505). [Bug
1795286](https://bugzil.la/1795286) is an example of the `contain` vs. `min-*`
behavior making a difference.

On XUL, automatic minimum sizes of flex items are roughly calculated by
recursively adding all margin/border/paddings and min-{width,height} of
descendants, while on flexbox, the automatic content sizes actually lay out the
element (ignoring percentages, etc).

In practice the new behavior should be more intuitive (except for scrollers as
mentioned above), but sometimes it made stuff grow where it didn't before.

## Timeline and approach

In [bug 1398963](https://bugzil.la/1398963), there's a lot of discussion which
eventually culminated with a pref (`layout.css.emulate-moz-box-with-flex`)
landing to allow seeing the difference.

As I started looking at some of the issues above, it was clear to me that
a one-off switch like that was not going to fly: There's just too much UI that
needs small tweaks or fixes for it to land all at once.

In order to make the migration possible, in [bug
1783934](https://bugzil.la/1783934) I added a `-moz-box-layout` css property to
allow opting into the emulation. That allowed us to have some pages opt in into
the new behavior, without having to fix all others at the same time, and
without having to maintain both the old and new layouts.

I think that was a key part of being able to succeed doing this. Some of the
bugs listed below caused a large amount of regressions. Having an easy way to
opt out of the new behavior, and being able to address regressions on
a per-case basis made it feasible.

That also unblocked making the "switch it all" pref dynamic, which made it easy
to spot visual regressions on the browser chrome, which I did in  [bug
1784349](https://bugzil.la/1784349).

The first page using flexbox emulation by default was the Settings page ([bug
1790307](https://bugzil.la/1790307)).

I enabled it afterwards on the main browser area (the content area, not the
tabs, urlbar etc), which was already using a mix of CSS flex and grid in other
places ([bug 1789168](https://bugzil.la/1789168)).

DevTools was also a relatively easy target, because other than splitters etc
they didn't use much XUL ([bug 1792473](https://bugzil.la/1792473)).

One [existing bug](https://bugzil.la/1779695) made me toggle it on all other
in-content pages (so most dialogs and about pages).

About a month later I turned it on the main Firefox UI ([bug
1792473](https://bugzil.la/1792473)).

After this, there was a long tail of windows (like the bookmarks organizer, the
page information window, the profile manager, etc) which were still using XUL
layout. I enabled it everywhere on [bug 1815255](https://bugzil.la/1815255),
soon after the merge, so that we had a whole cycle for regression fixes.

A crazy amount of regression-fixing after, **I was done!** I could finish
removing the remnants of XUL layout (scrollbars, etc), and call it a day...

### The final switch

But... It seems that now we had flexbox emulation on everywhere, switching to
proper modern flexbox, and removing `display: -moz-box` completely would be
just a matter of search and replace, right?

It never is so easy... In [bug 1820534](https://bugzil.la/1820534) I moved the
front-end to modern flexbox by basically moving `display: -moz-box` to `flex`,
and doing basically the inverse mapping.

That _mostly_ worked, but caused a bunch of regressions due to other behavior
changes (mostly around min intrinsic sizes like [bug
1822131](https://bugzil.la/1822131), and interactions with code that
were setting xul properties inside grid, which didn't have an effect but now we
use the align/justify-* properties it does).

I landed two other "big" changes to our flexbox setup as a result of those, so
that we [shrunk by default](https://bugzil.la/1822131) and so that flex="1"
[had a smaller flex basis](https://bugzil.la/1822578) too.

The end result is less differences between XUL and HTML, and that the front-end
is using un-prefixed flexbox, so I'm quite pleased about that!

## I'm a Firefox contributor, when should I use XUL vs. HTML?

I plan to update the in-tree docs on this. The TLDR is that XUL has some
specialness, mostly in the DOM, and mostly around popups and menus.

So, you still need `<xul:panel>` / `<xul:menupopup>` / etc to add native OS
panels and menus. Maybe in the future we can replace them with the
[popover](https://html.spec.whatwg.org/#popover) API.

Other than that, nowadays most XUL is just HTML but defaulting to `box-sizing:
border-box` and `display: flex`.
