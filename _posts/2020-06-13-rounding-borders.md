---
layout: post
title:  "Border rounding in CSS"
date:   2020-06-13 20:56:00
---

This week I landed [a change in
Gecko](https://bugzilla.mozilla.org/show_bug.cgi?id=477157) to make subpixel
borders work more similarly to other engines. I learned a bunch in the progress
_and_ after landing it, so I wanted to capture it somewhere.

Border widths are a bit special compared to other kinds of CSS lengths. All
browser engines agree on these principles:

 * **Borders should be crisp**. Anti-aliased borders kinda suck.
 * **Borders should be even**. If two borders are the same length in your CSS,
   they should be the same length in the rendered page.

Rendering borders that aren't crisp, or that are uneven, is not an option.

The rules I'm about to describe here also apply to `outline-width` and
`column-rule-width` at least in Gecko, btw.

## Rounding up

In order to achieve crisp borders, you need at least one device pixel in which
to paint the border. For example, for markup such as this:

```html
<!doctype html>
<div style="width: 0.01px; border: 0.01px solid"></div>
```

The `width` and `border-*-width` computed values will be different. **Borders
will get rounded up to one device pixel**.

All engines agree on doing this **at computed value time**, which means that the
layout algorithms will use the device pixel, and reserve enough space for the
border to be crisp.

## Rounding down

For a similar reason, if you write something like:

```html
<!doctype html>
<div style="width: 10.5px; border: 10.5px solid"></div>
```

The `width` and `border-*-width`s may not end up being exactly the same size.
They may get **rounded down to the nearest device pixel size**.

When you have something like a border which is `1.5` device pixels wide, you
need to anti-alias it against something, and that would mean that whether it
ends up being one or two pixels wide would usually depend on the position of the
screen where the border should get painted. This can cause uneven borders.

Now, **browsers here disagree on when** to do this:

 * Gecko, before my patch, rounds at computed value time. Which means that we'll
   do layout with the device pixel border size.

 * WebKit (and Blink) does layout with the subpixel border, and round the border
   down at paint-time.

There are pros and cons of both approaches.

**Firefox's approach** causes borders to sometimes be smaller during layout than
what the author expects. This can cause some unexpected layout differences,
which is what the original bug was about.

**WebKit's approach** doesn't have this problem, but it has other serious
problems: It causes slivers from the borders to the background of the children,
or to the same element's background if you use it in combination with
`background-clip: padding-box`.

For example, something like this (you may need to tweak the subpixel border to
see the issue on your screen, and / or zoom in and out) should ideally _never_
show any white between the background and the border, but in Chrome and safari
you can.

```html
<div style="height: 10px; border: 1.5px solid black; background-color: black; background-clip: padding-box"></div>
```

Rounding up instead of down for this would be problematic in both situations,
for different reasons. For Firefox, it'd mean that children using borders in
a precise way would overflow in some resolutions but not others. For WebKit it'd
mean that semi-transparent borders would overlap with children.

## There's no perfect solution

Unfortunately, both solutions aren't perfect, and they are incompatible. I don't
think that a perfect solution to this problem exists, just different trade-offs.

I've shifted my mind over the last few days, and (at least as I write this) **I
believe Firefox's approach is slightly superior** (and depending on the thoughts
of other people we may revert my Firefox patch).

The `background-clip: padding-box` use case not working is really sad, IMO.

I think we should get to an agreement and specify some of these in CSS. At least
the rounding-up at computed value time seems interoperable (so that seems
uncontroversial to specify to me), but we should aim to specify the whole thing,
including which properties are affected and so on.

I'm interested on what thoughts people that spend more time using CSS may
have... Have you got bitten by any of these issues as either user or developer?
Which of the two approaches causes more pain?

Feel free to reach out to me on [twitter](https://twitter.com/ecbos_) or
somewhere else for opinions :)

Thanks for making it until here.
