---
layout: post
title:  "Developing Firefox on Windows on MSYS2 with zsh and the Windows Terminal"
date:   2022-11-22 10:09 AM
---

I've been looking at how to get a more familiar set-up on Windows, something
more similar to what I have on Linux or macOS.

The default bash terminal that comes with mozilla-build is not great for me (I'm
used to zsh). Also, mozilla-build comes without a package manager, which means
that software I need for managing e.g., my dotfiles doesn't work.

It's documented that you can
[invoke mach outside
mozilla-build](https://firefox-source-docs.mozilla.org/mach/windows-usage-outside-mozillabuild.html),
and that page does have a bunch of interesting tips, but nothing too concrete.

So while I tried to get that working, I decide to write out what I did in order
to hopefully make it easier for someone else.

## Installing MSYS2 and some basic dependencies.

First we're going to need some basic software:

 * Install [MozillaBuild](https://wiki.mozilla.org/MozillaBuild).
 * Install [Git for Windows](https://gitforwindows.org/).
 * Install Python 3. I used the [Microsoft
   Store](https://apps.microsoft.com/store/detail/python-310/9PJPW5LDXLZ5) for
   it. Make sure you use Windows python rather than cygwin's, because otherwise
   the Firefox build will fail.
 * Install [MSYS2](https://www.msys2.org/).

## Installing our shell and other MSYS2 tweaks

On an `MSYS2` terminal I ran `pacman -S zsh` (or shell of your choice, or avoid
doing it if you're ok with bash).

Then I tweaked `/etc/nsswitch.conf`, and set `db_home: windows`. This allows the
windows home directory to be the shell's home directory, which is easier so that
things like ssh / git config don't need to live in two different places.

## Adding a Windows Terminal profile

In the [Windows
Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701),
we need to create a new profile. Give it the name you want, and the following
settings:

### Command line

That should be something along the lines of:

```
C:/msys64/msys2_shell.cmd -defterm -here -no-start -ucrt64 -shell zsh -use-full-path
```

Some notes:

 * `-use-full-path` is needed so that things like `git` or `python` are visible
   inside the msys2 terminal.

 * `-shell zsh` is obviously what triggers the new shell, and you can switch to
   whatever or omit it to remain with bash.

### Start directory

I made that `%USERPROFILE%` (so, the home directory). You can also set
`C:\mozilla-unified` or wherever you want to have the Firefox checkout.

### Icon

If you fancy, you can set the icon to something like `C:\msys64\msys2.ico` or
even something like `<mozilla-repo>\browser\branding\nightly\default256.png`.

## Customizing stuff

Now you can customize your terminal and environment much like you'd do on Unix.
For me, I imported my `~/.zshrc`, `~/.vimrc`, etc, and installed `nvim` (with
`winget`), `oh-my-zsh`, installed my powerline fonts, etc.

I found some hiccups that I'll document below:

### Python pip path

I use `git-revise`, `moz-phab`, `mozregression`, etc from pip, so I'd like
`pip`-installed commands to be on my `PATH`. On my Linux/macOS `.zshrc` I had:

```sh
export PATH="$PATH:$(python3 -m site --user-base)/bin"
```

But that had two issues:

 * The path on Windows is different (it's user-base/Python{major}{minor}/Scripts).

 * The `python3 -m site --user-base` command was printing a `\r\n`, which put an
   annoying carriage return in the `PATH`, causing weird stuff to happen
   with other programs.

In the end what I came up with is:

```sh
if command -v python3 > /dev/null; then
  if command -v cygpath > /dev/null; then
    export PATH="$PATH:$(cygpath $(python3 -m site --user-base | tr -d '\r'))/Python$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}", end="")')/Scripts"
  else
    export PATH="$PATH:$(python3 -m site --user-base)/bin"
  fi
fi
```

As much an abomination as it is, it works.

### Neovim

There was no msys2 package of neovim (my usual editor on other platforms), but
I could install it with `winget install Neovim.Neovim`.

That works, but turns out on windows `nvim` looks at a different path for its
configuration, so I had to create `~/AppData/Local/nvim/init.vim` with:

```
source ~/.config/nvim/init.vim
```

For it to pick up my usual config.

On top, running , my usual nvim setup has a number of plugins that didn't quite
work, and various other [issues](https://github.com/neovim/neovim/issues/21148)
related to stuff not expecting a bash-compatible shell on Windows.

After a bit of painful debugging, I ended up giving up and putting the following
in my `.vimrc` file:

```vim
if has('win32') || has('win64')
  set shell=$COMSPEC
endif
```

Which basically resets the shell to `cmd.exe`. Stuff just works with that.
I also had to create a `spell/` directory so that nvim wouldn't try to download
spell files to `C:\Program Files\Neovim\...` (which didn't work because of
permissions).

Another few tweaks to the `~/.zshrc` file were needed, since Git would refuse to
use `GIT_EDITOR=nvim` but `GIT_EDITOR=nvim.exe` worked.

These are the relevant bits of my zshrc now:

```
if ! command -v nvim >/dev/null; then
  export VISUAL=vim
else
  export VISUAL=nvim
  alias vim='nvim'
fi

if command -v cygpath >/dev/null; then
  # This helps with git editor etc.
  export VISUAL="$VISUAL.exe"
fi

export EDITOR="$VISUAL"
export GIT_EDITOR="$VISUAL"
```

Everything else just works. Autocomplete with `coc` and `coc-clangd`, etc works
perfectly, my usual build setup just works...

## Building Firefox

Yay, the fun stuff. The main thing to have into account is that you want this
bit in your `mozconfig`, so that `configure` picks the right tools / cygwin dlls
for the build:

```sh
export PATH="/c/mozilla-build/msys2/usr/bin:$PATH"
```

You shouldn't need anything else. Maybe we can fix the build system to do this
automatically, I filed [bug 1801826](https://bugzil.la/1801826) for this.

Another thing that threw me off for a bit was that on Linux, I have [a setup to
allow building with different
compilers](https://github.com/emilio/mozconfigs/blob/c0b516299f6e1658dacfae4375621693fdc491e5/mozconfigs/compile-environment#L18),
and that was overriding `AS`, which on windows can't be set to `clang-cl`.

Since I don't care about building with different compilers on windows I just
avoided setting `AS` at all.

With all this, I have a comfortable set-up to building and editing code on
Windows, similar to other platforms.
