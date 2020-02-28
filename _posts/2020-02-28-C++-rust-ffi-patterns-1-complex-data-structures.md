---
layout: post
title:  "FFI patterns #1 - Complex Rust data structures exposed seamlessly to C++"
date:   2020-02-28 00:20:00
---

I've been meaning to post about this for a while. I plan to start a series on
different patterns for Rust / C++ FFI that are being used in Gecko.

I don't know how many posts this would take, and given I'm a not-very-consistent
writer, I think I'm going to start with the most complex one to get it done.

This is the pattern that Firefox's style system uses.

## The use-case

The use-case for this is one or more of the following:

 * You have pretty complex Rust data structures that you need to expose to C++.

 * You can't afford extra indirection / FFI calls / conversions / copies, or
   there's too much API surface for it to be reasonable to add an extern
   function for each getter / setter / etc.

 * You want C++ code to be idiomatic, and not need wrappers around the Rust
   objects. That is, you want destructors, copy-constructors, copy-assignment,
   etc to **just work**, free your resources, etc.

In our case, the style system **needs to expose a bunch of complex, recursive,
generic data-structures** like [calc
nodes](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style/values/generics/calc.rs#54),
inside a manual-tagged-pointer for
[LengthPercentage](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style/values/computed/length_percentage.rs#105).
Or some other crazy tagged union types like
[transforms](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style/values/generics/transform.rs#160),
or text-shadows, which involve reference-counted lists, etc.

There are also **hundreds of CSS properties**, with **thousands of consumers**
across the whole Gecko layout engine, and thus:

 * We **cannot rely on manual memory management**, because some consumers will
   always get it wrong.

 * We **cannot afford to add an extra indirection to each CSS value**. Layout
   and painting are already memory-bound, we don't want to make that worse.

So this pattern seems like a good fit for us.

## The plan

The plan to accomplish it is not too complex on the surface:

 1. Get [`cbindgen`](https://github.com/eqrion/cbindgen) to generate a bunch of
    idiomatic C++ code based on our gazillion Rust types.

 2. Have equivalent C++ implementations of your core Rust data-structures, with
    destructors / proper semantics, and so on.

 3. Profit?

We'll go about all the details of how to make that happen, as well as a proper
step-by-step example below.

## The caveats

The plus side is of course that you win idiomatic C++ code, with all the gnarly
boring stuff generated for you. You can poke at Rust structs directly, get
pointers to them, copy them, all without having to define an FFI function for
each operation you want to perform. Sounds amazing!

However, nothing is free, and if you go for this approach you need to consider
the following caveats:

 * **Passing structs by value on the FFI boundary between Rust and C++ becomes
   unsafe**: You need to use references / pointers. The reason for this is that
   having destructors and such changes the C++ ABI. Having manual `Drop`
   / `Clone` implementations however doesn't change the ABI in the same way in
   Rust (and I think that's good, I don't think Rust should be in the business
   of being ABI-compatible with C++). In Firefox we have a [clang-based static
   analysis](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/build/clang-plugin/NonTrivialTypeInFfiChecker.cpp)
   to prevent people from shooting themselves in the foot.

 * You need to **duplicate manual `Drop` implementations** in C++. This is
   usually not a big deal (the only things that usually need manual drop
   implementations are data-structures or such). Here's
   [an](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/ports/geckolib/cbindgen.toml#514)
   [example](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/ServoStyleConstsInlines.h#135)
   which I'll talk about later.

These haven't been a problem in practice for us. It's a bit more complex setup
than just declaring and using FFI functions, but it pays off by not having to do
manual memory management in C++.

## Demo

I've put a simple
[demo](https://github.com/emilio/rust-cpp-ffi-examples/tree/master/complex-rust-to-cpp)
on a GitHub repo of a somewhat-minimal setup for this.

In practice there's a few differences from the Firefox setup. On Firefox:

 * The C++ code is not built from `build.rs` (as you may imagine).
 * `cbindgen` is run as a CLI tool, because of that. We need the headers
   exported independently of the rust build.
 * We have bindings in _both_ directions, actually, so we also use
   [`rust-bindgen`](https://github.com/rust-lang/rust-bindgen) to be able to
   poke at C++ structs and classes, for a variety of reasons.

But those shouldn't really matter for this example. Modulo those, it should
hopefully be a good overview of how the setup works. Here's the different parts
of the demo, explained step by step.

### The program we want to build

The program we want is simple enough... We want to expose a tree to C++, and
want to run some calculations on that tree in C++.

If we weren't interfacing with C++, our tree would look like this:

```rust
#[derive(Clone, Debug)]
pub enum TreeNode {
    /// This node just has a value.
    Leaf(f32),
    /// This node sums all the children.
    Sum(Box<[TreeNode]>),
    /// This node returns 1 if the two things are the same, and zero otherwise.
    Cmp(Box<TreeNode>, Box<TreeNode>),
}
```

What we effectively want to do is something like:

```rust
let tree = create_some_complex_tree();
let value = unsafe { let_cpp_compute_the_value(&tree); };
assert_eq!(value, expected_value);
```

Or something like that.

### Exposing the type to C++

Let's see what `cbindgen` thinks about our `TreeNode` type. When running it on
the following Rust file:

```rust
#[derive(Clone, Debug)]
pub enum TreeNode {
    /// This node just has a value.
    Leaf(f32),
    /// This node sums all the children.
    Sum(Box<[TreeNode]>),
    /// This node returns 1 if the two things are the same, and zero otherwise.
    Cmp(Box<TreeNode>, Box<TreeNode>),
}

#[no_mangle]
pub extern "C" fn root(node: &TreeNode) {}
```

We get back only this:

```cpp
#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <new>

struct TreeNode;

extern "C" {

void root(const TreeNode *node);

} // extern "C"
```

Well... That's not great, but not quite unexpected.

**Our type needs a memory layout that C++ can understand**. The default Rust
struct layout is intentionally unspecified. Rust does a lot of smart stuff like
reordering fields, packing enums, etc.

In order to dumb down rustc so that it can interoperate with C++ **we need to
tag the enum with the `#[repr]` attribute**. I've gone with `#[repr(C, u8)]`,
but we have other choices here, see [this
rfc](https://github.com/rust-lang/rfcs/blob/master/text/2195-really-tagged-unions.md)
and the [nomicon](https://doc.rust-lang.org/nomicon/other-reprs.html) for the
details.

With that out of the way, the layout of `Box<[TreeNode]>` and `Box<TreeNode>`
should be
[well-defined](https://github.com/rust-lang/unsafe-code-guidelines/blob/master/reference/src/layout/pointers.md),
so can cbindgen do the right thing for us?

The answer is "not quite". `cbindgen` doesn't understand `Box<[T]>` deeply
enough, and assumes the type is not FFI-safe. I just [filed an
issue](https://github.com/eqrion/cbindgen/issues/480) on maybe getting some
smarts for this, but cbindgen would need to generate a generic struct on its own
which is not great...

So for now we're going to do this manually.

#### `OwnedSlice`

[`OwnedSlice<T>`](https://github.com/emilio/rust-cpp-ffi-examples/blob/master/complex-rust-to-cpp/src/owned_slice.rs)
is going to be our **ffi-friendly replacement for `Box<[T]>`**. It's a very
straightforward type, taken [almost
verbatim](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style_traits/owned_slice.rs)
from Firefox.

It has the **same layout as `Box<[T]>`**, and we can use it on our `TreeNode`.
It looks like:

```rust
/// cbindgen:derive-eq=false
/// cbindgen:derive-neq=false
#[repr(C)]
pub struct OwnedSlice<T: Sized> {
    ptr: NonNull<T>,
    len: usize,
    _phantom: PhantomData<T>,
}
```

Note those two `cbindgen:` annotations. We'll get to those later.

The final `TreeNode` type looks like:

```rust
#[derive(Clone, Debug)]
#[repr(C, u8)]
pub enum TreeNode {
    /// This node just has a value.
    Leaf(f32),
    /// This node sums all the children.
    Sum(OwnedSlice<TreeNode>),
    /// This node returns 1 if the two things are the same, and zero otherwise.
    Cmp(Box<TreeNode>, Box<TreeNode>),
}
```

And cbindgen generates the following for it (without any flags, we'll see about
that in a min):

```cpp
template<typename T>
struct Box;

struct TreeNode {
  enum class Tag : uint8_t {
    /// This node just has a value.
    Leaf,
    /// This node sums all the children.
    Sum,
    /// This node returns 1 if the two things are the same, and zero otherwise.
    Cmp,
  };

  struct Leaf_Body {
    float _0;
  };

  struct Sum_Body {
    OwnedSlice<TreeNode> _0;
  };

  struct Cmp_Body {
    Box<TreeNode> _0;
    Box<TreeNode> _1;
  };

  Tag tag;
  union {
    Leaf_Body leaf;
    Sum_Body sum;
    Cmp_Body cmp;
  };
};
```

It also generates bindings for `OwnedSlice`, which I've omitted for brevity.

### `cbindgen.toml`

We have the base type working, and it looks nice. But **poking at it and using it
from C++ is still very error-prone**.

`cbindgen` has a bunch of flags to make interacting with tagged enums and
structs from C++ better. You can look at the [docs in the `cbindgen`
repo](https://github.com/eqrion/cbindgen/blob/master/docs.md), but here are the
ones we're going to use:

```toml
[struct]
# generates operator==
derive_eq = true
# generates operator!=
derive_neq = true

[enum]
# Generates IsFoo() methods.
derive_helper_methods = true
# Generates `const T& AsFoo() const` methods.
derive_const_casts = true
# Adds an `assert(IsFoo())` on each `AsFoo()` method.
cast_assert_name = "assert"
# Generates destructors.
derive_tagged_enum_destructor = true
# Generates copy-constructors.
derive_tagged_enum_copy_constructor = true
# Generates copy-assignment operators.
derive_tagged_enum_copy_assignment = true
# Generates a private default-constructor for enums that doesn't initialize
# anything. Either you do this or you provide your own default constructor.
private_default_tagged_enum_constructor = true
```

This generates a bunch more code for `TreeNode`, as advertised. Our code still
doesn't compile though, given there's only a forward-declaration for `Box`:

```cpp
template <typename T>
struct Box;
```

### Defining `Box`.

We're going to define a simple smart pointer type for `Box` that has the same
semantics and layout as Rust (assuming sized types), and include it in
a `forwards.h` file from cbindgen.toml.

[The
implementation](https://github.com/emilio/rust-cpp-ffi-examples/blob/master/complex-rust-to-cpp/cpp/my_ffi_forwards.h)
should be pretty straightforward so I won't read through it.

This makes our bindings compile, but still `OwnedSlice` has issues.

### Making `OwnedSlice` do the right thing from C++

Remember those `cbindgen:` lines in `OwnedSlice`? Here's where they come into
play. The default `operator==` for `OwnedSlice` would have compared the pointer
and length values, and that's it. It wouldn't have the same semantics as our
rust type, which would compare the values individually.

Also, `OwnedSlice` doesn't manage its contents properly yet. We can fix that
easily, though.

`cbindgen` has an `[export.body]` section that allows you to define stuff like
methods, constructors, operators, etc. in the body of an item.

In this case, we just want a few basic things:

```toml
[export.body]
"OwnedSlice" = """
  inline void Clear();
  inline void CopyFrom(const OwnedSlice&);

  // cpp shenanigans.
  inline OwnedSlice();
  inline ~OwnedSlice();
  inline OwnedSlice(const OwnedSlice&);
  inline OwnedSlice& operator=(const OwnedSlice&);

  std::span<T> AsSpan() {
    return { ptr, len };
  }

  inline std::span<const T> AsSpan() const {
    return { ptr, len };
  }

  bool IsEmpty() {
    return AsSpan().empty();
  }

  inline bool operator==(const OwnedSlice&) const;
  inline bool operator!=(const OwnedSlice&) const;
"""
```

We'll be using C++20's `std::span` to allow ranged loops and such instead of
implementing iterators ourselves (I'm lazy, turns out).

We've added a few inline methods to help with memory management that we now need
to implement.

We'll include the file with the implementation of these methods at the end of
the `cbindgen`-generated file:

```toml
trailer = """
#include "my_ffi_inlines.h"
"""
```

[That
file](https://github.com/emilio/rust-cpp-ffi-examples/blob/master/complex-rust-to-cpp/cpp/my_ffi_inlines.h)
is also relatively straightforward, and it basically keeps the same invariants
as the Rust counterpart does.

### The actual C++ code.

With these two building-blocks in place (`Box` and `OwnedSlice`), we can use our
`TreeNode` from C++ the same way as any other idiomatic C++ struct.

C++ consumers of the `TreeNode` type can use it **transparently**, just like
Rust consumers, without leaking resources or leaving dangling pointers around
accidentally. Using it looks like reasonably modern C++.

The actual C++ code for our computation is
[here](https://github.com/emilio/rust-cpp-ffi-examples/blob/master/complex-rust-to-cpp/cpp/doit.cpp).

If we wanted to add some idiomatic methods to `TreeNode`, we could do that using
`[export.body]`, just like we've done with `OwnedSlice::AsSpan`.

This is as much as I can write today, you can see all the gory details in the
[demo
repo](https://github.com/emilio/rust-cpp-ffi-examples/tree/master/complex-rust-to-cpp).
Hopefully I haven't glanced over too much stuff.

## Conclusion

Of course this pattern is probably not worth it for just a single type, as it
requires a bit of setup. But when you have a massive API surface (like we do in
the Firefox style engine) the effort does pay off.

My favourite commit to link to is [this
one](https://hg.mozilla.org/mozilla-central/rev/02c806cb81d9) in which
I switched Firefox to use `cbindgen` for the transform property. It:

 * Modernized the existing (old) C++ code.
 * Improved performance.
 * Removed a lot of boring / repetitive / error-prone glue code.

Over time, we've needed a couple more data structures. We have C++-compatible
versions of:

 * [`OwnedStr`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style_traits/owned_str.rs#17):
   an owned utf-8 string (basically, `Box<str>`). It's built on top of
   `OwnedSlice` so it doesn't even need manual destructors and such, just some
   convenience methods to get the string as a Gecko substring.

 * [`Arc`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/servo_arc/lib.rs#78):
   We already had our own `Arc` copy for various reasons (to avoid weak
   reference count overhead, for other ffi shenanigans, and to add
   reference-count logging to detect leaks). Switching it to this model was
   trivial. There's a [crates.io version](https://crates.io/crates/triomphe) of
   this called Triomphe which Manish maintains.

 * [`ArcSlice`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style_traits/arc_slice.rs#30):
   an `Arc<[T]>`, but stored as a thin pointer, built on top of that.
   It should also be buildable on top of Triomphe, though I don't think
   Firefox's version is general-purpose enough to put on crates.io. Maybe,
   though?

We have destructors for a couple other structs for which we implement size
optimizations manually like `LengthPercentage`, but that's about it.

---

I tried to explain the trade-offs of this approach to do FFI with C++ above,
hopefully if you read until here now you have a better sense of them too, and if
it fits your use-case you have the tools to do the right thing.

I personally don't love to have duplicate code for our data-structures in both
Rust and C++. But for us it works out alright: the benefits we get (nice
idiomatic C++ code, having all our style system structs defined in Rust, which
can use a bunch of proc macros, and having them interoperate seamlessly with
C++) are definitely worth a couple duplicated boring lines.

Congratulations if you made it all the way here. I hope I didn't write too many
typos in the process, my English always sucks... Thanks to
[Daniel](https://twitter.com/CodingExon) for spotting a bunch already :)

Feel free to send comments or corrections to [my
email](mailto:emilio@crisal.io),
[Twitter](https://twitter.com/ecbos_), or to
[GitHub](https://github.com/emilio/words) directly, your call.
