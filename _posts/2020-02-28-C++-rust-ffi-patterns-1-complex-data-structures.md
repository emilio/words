---
layout: post
title:  "FFI patterns #1 - Complex Rust data structures exposed seamlessly to C++"
date:   2020-02-28 00:20:00
---

I've been meaning to post about this for a while. I plan to start a series on
different patterns for Rust / C++ FFI that are being used in Gecko.

I don't know how many posts would this take, and given I'm a not-very-consistent
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

 * Get [`cbindgen`](https://github.com/eqrion/cbindgen) to generate a bunch of
   idiomatic C++ code based on our gazillion Rust types.

 * Have equivalent C++ implementations of your core Rust data-structures, with
   destructors / proper semantics, and so on.

 * Profit?

We'll go about all the details of how to make that happen, as well as a proper
step-by-step example below.

## The caveats

The plus side is of course that you win idiomatic C++ code, with all the gnarly
boring stuff generated for you. You can poke at Rust structs directly, get
pointers to it, copy it, all without having to define an FFI function for each
operation you want to perform. Sounds amazing!

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
   usually not a big deal (the only thing that usually need manual drop
   implementations is data-structures or such). Here's
   [an](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/ports/geckolib/cbindgen.toml#514)
   [example](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/ServoStyleConstsInlines.h#135)
   which I'll talk about later.

These haven't been a problem in practice for us. It's a bit more of a complex
setup than just declaring and using FFI functions, but it pays off by not having
to do manual memory management in C++.

## Real-world example

Here's how some the final consumers look like in Firefox:

 * [Processing of CSS
   transforms](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/nsStyleTransformMatrix.cpp#390-570)
 * [Resolution](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/generic/nsTextFrame.cpp#1798)
   of
   [`LengthPercentage`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/ServoStyleConstsInlines.h#698)
   values (including
   [calc](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/nsStyleStruct.cpp#3448),
   etc).
 * [Strings](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/layout/style/ServoStyleConstsInlines.h#336).

Here's how some of those generated types look like (I can't perma-link to
generated files on searchfox):

### Rust code

(Original is
[here](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style/values/generics/effects.rs#53),
I've stripped out the custom derive mumbo-jumbo, which is not the point of this
exercise).

```rust
#[derive(Clone, Debug, PartialEq)]
#[repr(C, u8)]
pub enum GenericFilter<Angle, NonNegativeFactor, ZeroToOneFactor, Length, Shadow, U> {
    Blur(Length),
    Brightness(NonNegativeFactor),
    Contrast(NonNegativeFactor),
    Grayscale(ZeroToOneFactor),
    HueRotate(Angle),
    Invert(ZeroToOneFactor),
    Opacity(ZeroToOneFactor),
    Saturate(NonNegativeFactor),
    Sepia(ZeroToOneFactor),
    DropShadow(Shadow),
    Url(U),
}
```

### Auto-generated C++ code

Warning, it's verbose, if you expand the `<details>` below, prepare your
mousewheel / finger / trackpad :)

<details>

```cpp
template<typename Angle, typename NonNegativeFactor, typename ZeroToOneFactor, typename Length, typename Shadow, typename U>
struct StyleGenericFilter {
  enum class Tag : uint8_t {
    /// `blur(<length>)`
    Blur,
    /// `brightness(<factor>)`
    Brightness,
    /// `contrast(<factor>)`
    Contrast,
    /// `grayscale(<factor>)`
    Grayscale,
    /// `hue-rotate(<angle>)`
    HueRotate,
    /// `invert(<factor>)`
    Invert,
    /// `opacity(<factor>)`
    Opacity,
    /// `saturate(<factor>)`
    Saturate,
    /// `sepia(<factor>)`
    Sepia,
    /// `drop-shadow(...)`
    DropShadow,
    /// `<url>`
    Url,
  };

  struct StyleBlur_Body {
    Length _0;

    bool operator==(const StyleBlur_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleBlur_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleBrightness_Body {
    NonNegativeFactor _0;

    bool operator==(const StyleBrightness_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleBrightness_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleContrast_Body {
    NonNegativeFactor _0;

    bool operator==(const StyleContrast_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleContrast_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleGrayscale_Body {
    ZeroToOneFactor _0;

    bool operator==(const StyleGrayscale_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleGrayscale_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleHueRotate_Body {
    Angle _0;

    bool operator==(const StyleHueRotate_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleHueRotate_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleInvert_Body {
    ZeroToOneFactor _0;

    bool operator==(const StyleInvert_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleInvert_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleOpacity_Body {
    ZeroToOneFactor _0;

    bool operator==(const StyleOpacity_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleOpacity_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleSaturate_Body {
    NonNegativeFactor _0;

    bool operator==(const StyleSaturate_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleSaturate_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleSepia_Body {
    ZeroToOneFactor _0;

    bool operator==(const StyleSepia_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleSepia_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleDropShadow_Body {
    Shadow _0;

    bool operator==(const StyleDropShadow_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleDropShadow_Body& other) const {
      return _0 != other._0;
    }
  };

  struct StyleUrl_Body {
    U _0;

    bool operator==(const StyleUrl_Body& other) const {
      return _0 == other._0;
    }
    bool operator!=(const StyleUrl_Body& other) const {
      return _0 != other._0;
    }
  };

  Tag tag;
  union {
    StyleBlur_Body blur;
    StyleBrightness_Body brightness;
    StyleContrast_Body contrast;
    StyleGrayscale_Body grayscale;
    StyleHueRotate_Body hue_rotate;
    StyleInvert_Body invert;
    StyleOpacity_Body opacity;
    StyleSaturate_Body saturate;
    StyleSepia_Body sepia;
    StyleDropShadow_Body drop_shadow;
    StyleUrl_Body url;
  };

  static StyleGenericFilter Blur(const Length &a0) {
    StyleGenericFilter result;
    ::new (&result.blur._0) (Length)(a0);
    result.tag = Tag::Blur;
    return result;
  }

  bool IsBlur() const {
    return tag == Tag::Blur;
  }

  const Length& AsBlur() const {
    MOZ_ASSERT(IsBlur());
    return blur._0;
  }

  static StyleGenericFilter Brightness(const NonNegativeFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.brightness._0) (NonNegativeFactor)(a0);
    result.tag = Tag::Brightness;
    return result;
  }

  bool IsBrightness() const {
    return tag == Tag::Brightness;
  }

  const NonNegativeFactor& AsBrightness() const {
    MOZ_ASSERT(IsBrightness());
    return brightness._0;
  }

  static StyleGenericFilter Contrast(const NonNegativeFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.contrast._0) (NonNegativeFactor)(a0);
    result.tag = Tag::Contrast;
    return result;
  }

  bool IsContrast() const {
    return tag == Tag::Contrast;
  }

  const NonNegativeFactor& AsContrast() const {
    MOZ_ASSERT(IsContrast());
    return contrast._0;
  }

  static StyleGenericFilter Grayscale(const ZeroToOneFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.grayscale._0) (ZeroToOneFactor)(a0);
    result.tag = Tag::Grayscale;
    return result;
  }

  bool IsGrayscale() const {
    return tag == Tag::Grayscale;
  }

  const ZeroToOneFactor& AsGrayscale() const {
    MOZ_ASSERT(IsGrayscale());
    return grayscale._0;
  }

  static StyleGenericFilter HueRotate(const Angle &a0) {
    StyleGenericFilter result;
    ::new (&result.hue_rotate._0) (Angle)(a0);
    result.tag = Tag::HueRotate;
    return result;
  }

  bool IsHueRotate() const {
    return tag == Tag::HueRotate;
  }

  const Angle& AsHueRotate() const {
    MOZ_ASSERT(IsHueRotate());
    return hue_rotate._0;
  }

  static StyleGenericFilter Invert(const ZeroToOneFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.invert._0) (ZeroToOneFactor)(a0);
    result.tag = Tag::Invert;
    return result;
  }

  bool IsInvert() const {
    return tag == Tag::Invert;
  }

  const ZeroToOneFactor& AsInvert() const {
    MOZ_ASSERT(IsInvert());
    return invert._0;
  }

  static StyleGenericFilter Opacity(const ZeroToOneFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.opacity._0) (ZeroToOneFactor)(a0);
    result.tag = Tag::Opacity;
    return result;
  }

  bool IsOpacity() const {
    return tag == Tag::Opacity;
  }

  const ZeroToOneFactor& AsOpacity() const {
    MOZ_ASSERT(IsOpacity());
    return opacity._0;
  }

  static StyleGenericFilter Saturate(const NonNegativeFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.saturate._0) (NonNegativeFactor)(a0);
    result.tag = Tag::Saturate;
    return result;
  }

  bool IsSaturate() const {
    return tag == Tag::Saturate;
  }

  const NonNegativeFactor& AsSaturate() const {
    MOZ_ASSERT(IsSaturate());
    return saturate._0;
  }

  static StyleGenericFilter Sepia(const ZeroToOneFactor &a0) {
    StyleGenericFilter result;
    ::new (&result.sepia._0) (ZeroToOneFactor)(a0);
    result.tag = Tag::Sepia;
    return result;
  }

  bool IsSepia() const {
    return tag == Tag::Sepia;
  }

  const ZeroToOneFactor& AsSepia() const {
    MOZ_ASSERT(IsSepia());
    return sepia._0;
  }

  static StyleGenericFilter DropShadow(const Shadow &a0) {
    StyleGenericFilter result;
    ::new (&result.drop_shadow._0) (Shadow)(a0);
    result.tag = Tag::DropShadow;
    return result;
  }

  bool IsDropShadow() const {
    return tag == Tag::DropShadow;
  }

  const Shadow& AsDropShadow() const {
    MOZ_ASSERT(IsDropShadow());
    return drop_shadow._0;
  }

  static StyleGenericFilter Url(const U &a0) {
    StyleGenericFilter result;
    ::new (&result.url._0) (U)(a0);
    result.tag = Tag::Url;
    return result;
  }

  bool IsUrl() const {
    return tag == Tag::Url;
  }

  const U& AsUrl() const {
    MOZ_ASSERT(IsUrl());
    return url._0;
  }

  bool operator==(const StyleGenericFilter& other) const {
    if (tag != other.tag) {
      return false;
    }
    switch (tag) {
      case Tag::Blur: return blur == other.blur;
      case Tag::Brightness: return brightness == other.brightness;
      case Tag::Contrast: return contrast == other.contrast;
      case Tag::Grayscale: return grayscale == other.grayscale;
      case Tag::HueRotate: return hue_rotate == other.hue_rotate;
      case Tag::Invert: return invert == other.invert;
      case Tag::Opacity: return opacity == other.opacity;
      case Tag::Saturate: return saturate == other.saturate;
      case Tag::Sepia: return sepia == other.sepia;
      case Tag::DropShadow: return drop_shadow == other.drop_shadow;
      case Tag::Url: return url == other.url;
      default: return true;
    }
  }

  bool operator!=(const StyleGenericFilter& other) const {
    return !(*this == other);
  }

  private:
  StyleGenericFilter() {

  }
  public:


  ~StyleGenericFilter() {
    switch (tag) {
      case Tag::Blur: blur.~StyleBlur_Body(); break;
      case Tag::Brightness: brightness.~StyleBrightness_Body(); break;
      case Tag::Contrast: contrast.~StyleContrast_Body(); break;
      case Tag::Grayscale: grayscale.~StyleGrayscale_Body(); break;
      case Tag::HueRotate: hue_rotate.~StyleHueRotate_Body(); break;
      case Tag::Invert: invert.~StyleInvert_Body(); break;
      case Tag::Opacity: opacity.~StyleOpacity_Body(); break;
      case Tag::Saturate: saturate.~StyleSaturate_Body(); break;
      case Tag::Sepia: sepia.~StyleSepia_Body(); break;
      case Tag::DropShadow: drop_shadow.~StyleDropShadow_Body(); break;
      case Tag::Url: url.~StyleUrl_Body(); break;
      default: break;
    }
  }

  StyleGenericFilter(const StyleGenericFilter& other)
   : tag(other.tag) {
    switch (tag) {
      case Tag::Blur: ::new (&blur) (StyleBlur_Body)(other.blur); break;
      case Tag::Brightness: ::new (&brightness) (StyleBrightness_Body)(other.brightness); break;
      case Tag::Contrast: ::new (&contrast) (StyleContrast_Body)(other.contrast); break;
      case Tag::Grayscale: ::new (&grayscale) (StyleGrayscale_Body)(other.grayscale); break;
      case Tag::HueRotate: ::new (&hue_rotate) (StyleHueRotate_Body)(other.hue_rotate); break;
      case Tag::Invert: ::new (&invert) (StyleInvert_Body)(other.invert); break;
      case Tag::Opacity: ::new (&opacity) (StyleOpacity_Body)(other.opacity); break;
      case Tag::Saturate: ::new (&saturate) (StyleSaturate_Body)(other.saturate); break;
      case Tag::Sepia: ::new (&sepia) (StyleSepia_Body)(other.sepia); break;
      case Tag::DropShadow: ::new (&drop_shadow) (StyleDropShadow_Body)(other.drop_shadow); break;
      case Tag::Url: ::new (&url) (StyleUrl_Body)(other.url); break;
      default: break;
    }
  }
  StyleGenericFilter& operator=(const StyleGenericFilter& other) {
    if (this != &other) {
      this->~StyleGenericFilter();
      new (this) StyleGenericFilter(other);
    }
    return *this;
  }
};
```

</details>

*You wouldn't really want to write that by hand would you? :)*

## Demo

I've put a simple
[demo](https://github.com/emilio/rust-cpp-ffi-examples/tree/master/complex-rust-to-cpp)
on a GitHub repo of a minimal setup for this.

In practice there's a few differences from the Firefox setup. On Firefox:

 * The C++ code is not built from `build.rs` (as you may imagine).
 * `cbindgen` is ran as a CLI tool, because of that. We need the headers
   exported independently of the rust build.
 * We have bindings in _both_ directions, actually, so we also use
   [`rust-bindgen`](https://github.com/rust-lang/rust-bindgen) to be able to
   poke at C++ structs and classes, for a variety of reasons.

But those shouldn't really matter for this example. Modulo those caveats, it
should hopefully be a good overview of how the setup works. Here's the different
parts of the demo, explained step by step.

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
the following Rust program:

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

Now the layout of `Box<[TreeNode]>` and `Box<TreeNode>` should be
[well-defined](https://github.com/rust-lang/unsafe-code-guidelines/blob/master/reference/src/layout/pointers.md),
can cbindgen do the right thing for us?

The answer is "not quite". `cbindgen` doesn't understand `Box<[T]>` deeply
enough, and assumes the type is not FFI-safe. I just [filed an
issue](https://github.com/eqrion/cbindgen/issues/480) on maybe getting some
smarts for this, but cbindgen would need to generate a generic struct on its own
which is not great...

So for now we're going to do this manually.

#### `OwnedSlice`

[`OwnedSlice<T>`](https://github.com/emilio/rust-cpp-ffi-examples/blob/master/complex-rust-to-cpp/src/owned_slice.rs)
is going to be our **ffi-friendly replacement for `Box<[T]>`**. It's a very
straight-forward type, taken [almost
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
# Generates destructors
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
should be pretty straight-forward so I won't read through it.

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
is also relatively straight-forward, and it basically keeps the same invariants
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

 * [`Arc`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/servo_arc/lib.rs#78):
   We already had our own `Arc` copy for various reasons (to avoid weak
   reference count overhead, for other ffi shenanigans, and to add
   reference-count logging to detect leaks). Switching it to this model was
   trivial. There's a [crates.io version](https://crates.io/crates/triomphe) of
   this which Manish maintains.

 * [`ArcSlice`](https://searchfox.org/mozilla-central/rev/b2ccce862ef38d0d150fcac2b597f7f20091a0c7/servo/components/style_traits/arc_slice.rs#30),
   an `Arc<[T]>`, but stored as a thin pointer, built on top of that.
   It should also be buildable on top of triomphe, though I don't think
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
C++) is definitely worth a couple duplicated boring lines.

Congratulations if you made it all the way here. I hope I didn't write too many
typos in the process, my English always sucks... Feel free to send comments or
corrections to [my email](mailto:emilio@crisal.io),
[Twitter](https://twitter.com/ecbos_), or to
[GitHub](https://github.com/emilio/words) directly, your call.
