---
layout: post
title:  More Reference Browser debugging fun.
date:   2019-08-08 19:01:00
---

So I finally got back to
[bug 1551659](https://bugzilla.mozilla.org/show_bug.cgi?id=1551659), now that
the build issues I was seeing on [the last
post](https://crisal.io/words/2019/07/30/geckoview-debugging-fun.html) were
fixed.

## Convincing Reference-Browser to use my local GeckoView build

So the build is still the same, and we exported it the same way to a local maven
repository as the last post.

So we just got to convince reference-browser to use our build, right? Should be
easy.

Last post I ended up with a patch like this (with a different timestamp due to
it being a different day):

```diff
diff --git a/app/build.gradle b/app/build.gradle
index 0369ec7..2fc0d77 100644
--- a/app/build.gradle
+++ b/app/build.gradle
@@ -177,6 +177,8 @@ if (project.hasProperty("telemetry") && project.property("telemetry") == "true")
 }
 
 dependencies {
+    implementation "org.mozilla.geckoview:geckoview-nightly:70.0.20190808155548"
+
     implementation Deps.mozilla_concept_engine
     implementation Deps.mozilla_concept_tabstray
     implementation Deps.mozilla_concept_toolbar
diff --git a/build.gradle b/build.gradle
index af40504..0da305a 100644
--- a/build.gradle
+++ b/build.gradle
@@ -18,6 +18,7 @@ plugins {
 
 allprojects {
     repositories {
+        mavenLocal()
         google()
 
         maven {
```

That unfortunately **did not work as-is**. Gradle started complaining that there
was not such `geckoview-nightly` version. This is because, if you remember
correctly, our directory under `~/.m2` was called `geckoview-default`.

Changing `geckoview-nightly` by `geckoview-default` got further along, but
Gradle started complaining about a lot of duplicated classes. Welp!

That's not totally unexpected, since now I was not removing the regular
`geckoview-nightly` dependency...

The way I got around it is a pretty big hack, which I hope gets fixed soon.
Basically, I had to:

```
$ cd ~/.m2/repository/org/mozilla/geckoview
$ cp -r geckoview-default geckoview-nightly
```

And replace all the occurrences of `geckoview-default` for `geckoview-nightly`,
including renaming files.

At the time of this writing, the only in-file replacements I had to do were in
`maven-metadata-local.xml` and
`70.0.20190808155548/geckoview-default-70.0.20190808155548.pom`. The rest were
renamings so that the final tree looked like:

```
/home/emilio/.m2/repository/org/mozilla/geckoview
├── geckoview-default
│   ├── 70.0.20190808155548
│   │   ├── geckoview-default-70.0.20190808155548.aar
│   │   ├── geckoview-default-70.0.20190808155548-javadoc.jar
│   │   ├── geckoview-default-70.0.20190808155548.pom
│   │   └── geckoview-default-70.0.20190808155548-sources.jar
│   └── maven-metadata-local.xml
└── geckoview-nightly
    ├── 70.0.20190808155548
    │   ├── geckoview-nightly-70.0.20190808155548.aar
    │   ├── geckoview-nightly-70.0.20190808155548-javadoc.jar
    │   ├── geckoview-nightly-70.0.20190808155548.pom
    │   └── geckoview-nightly-70.0.20190808155548-sources.jar
    └── maven-metadata-local.xml
```

That _almost_ worked! I got `./gradlew assembleDebug` and `./gradlew
installDebug` to work, but the application didn't launch.

Paying a bit of attention to `adb logcat`, I can see that it was trying to find
an `x86_64` version of `libmozglue.so` and co. But my GeckoView build was an
`x86` build (`ac_add_options --target=i686-linux-android`), so of course it
wasn't there.

Reference-Browser does support both, but I found no easy way of telling it "just
build x86, ffs". So at this point I had two options:

 * I could go back, change my mozconfig so that I build a 64-bit Android build
   (`ac_add_options --target=x86_64-linux-android`), wait for the full build,
   and then re-do my options.

 * I could try to convince gradle to build the x86 version of reference-browser.

Of course I chose the second. Next time I may do an x86_64 version to begin
with, maybe.

Anyhow, the way to do that was straight forward, after grepping a bit around the
build files:

```diff
diff --git a/app/build.gradle b/app/build.gradle
index 2fc0d77..49b791b 100644
--- a/app/build.gradle
+++ b/app/build.gradle
@@ -77,7 +77,7 @@ android {
 
             reset()
 
-            include "x86", "armeabi-v7a", "arm64-v8a", "x86_64"
+            include "x86" // , "armeabi-v7a", "arm64-v8a", "x86_64"
         }
     }
 }
```

And after that, `./gradlew assembleDebug` and `./gradlew installDebug`, and it
worked!

So this is the complete patch that I needed in the `reference-browser` repo:

```diff
diff --git a/app/build.gradle b/app/build.gradle
index 0369ec7..49b791b 100644
--- a/app/build.gradle
+++ b/app/build.gradle
@@ -77,7 +77,7 @@ android {
 
             reset()
 
-            include "x86", "armeabi-v7a", "arm64-v8a", "x86_64"
+            include "x86" // , "armeabi-v7a", "arm64-v8a", "x86_64"
         }
     }
 }
@@ -177,6 +177,8 @@ if (project.hasProperty("telemetry") && project.property("telemetry") == "true")
 }
 
 dependencies {
+    implementation "org.mozilla.geckoview:geckoview-nightly:70.0.20190808155548"
+
     implementation Deps.mozilla_concept_engine
     implementation Deps.mozilla_concept_tabstray
     implementation Deps.mozilla_concept_toolbar
diff --git a/build.gradle b/build.gradle
index af40504..0da305a 100644
--- a/build.gradle
+++ b/build.gradle
@@ -18,6 +18,7 @@ plugins {
 
 allprojects {
     repositories {
+        mavenLocal()
         google()
 
         maven {
```

## Getting into a debugger

With such a painful compile-debug-test cycle, I figured printf-debugging was not
going to be a very effective way of diagnosing it. So next task is getting my
hands into a debugger.

I think Android Studio has a nice interface to get an `lldb` instance attached
to the process you care about, but I really hate AS (it's not something
rational, I suspect). Plus I don't have it installed anymore.

So I tried to get `lldb` to work. I really prefer `gdb`, generally (I'm more
used to it), but from what I heard getting it to work was a pain.

I found [some instructions on
Stack-Overflow](https://stackoverflow.com/questions/53733781/how-do-i-use-lldb-to-debug-c-code-on-android-on-command-line)
that looked promising. Those were for `gdb`, even, so I tried to go for that.

So, `adb shell`, to get into the content process, then from there:

```
# gdbserver :5045 --attach 7944
```

Then leave that running, and in another terminal:

```
$ adb forward tcp:5045 tcp:5045
```

(not sure if this step is really necessary)

And finally:

```
$ gdb
(gdb) target remote :5045
```

That's connects to the remote host, and `info threads` shows a bunch of the
Gecko threads, great!

Note that I used `/path/to/ndk/prebuilt/linux-x86_64/bin/gdb`, but
regular `gdb` worked for me too here.

We're interested in the content process, so we're going to switch to that.
`info threads` claimed that that was the thread `12`, so I ran `thread 12`, then
`bt`, and... :sadface:

I got a stack that looked like:

```
[...]
#11 0xca7beba5 in ?? () from target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
#12 0xca7beefd in ?? () from target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
#13 0xca670127 in ?? () from target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
#14 0xca6706d6 in ?? () from target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
[...]
```

That's going to be annoying, since `libxul.so` is _exactly_ what I'm interested
in debugging. Seems like there were no debug symbols in the target binary.
Probably an artifact of the "export to local repo" and such?

So we need to get that working somehow. After a bit of DuckDuckGoing, I found
[a post](https://marcioandreyoliveira.blogspot.com/2008/03/how-to-debug-striped-programs-with-gdb.html)
that did _almost_ what I wanted.

Except what I wanted was to load symbols for a dynamic library. After browsing
a bit more the web and manpages, I found about a magic flag for the `maintenance
info sections` gdb command which that post uses, which dumps also the location
for the dynamic libraries...

So if you run:

```
(gdb) maintenance info sections ALLOBJ
```

You'll eventually find a section for the library you're interested in. In this
case:

```
  Object file: target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
    0xc3eaf154->0xc3eaf1ec at 0x00000154: .note.android.ident ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc3eaf1ec->0xc3eaf210 at 0x000001ec: .note.gnu.build-id ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc3eaf210->0xc3fd82d0 at 0x00000210: .dynsym ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc3fd82d0->0xc3ffd4e8 at 0x001292d0: .gnu.version ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc3ffd4e8->0xc3ffd588 at 0x0014e4e8: .gnu.version_r ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc3ffd588->0xc4091df0 at 0x0014e588: .hash ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc4091df0->0xc4764849 at 0x001e2df0: .dynstr ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc476484c->0xc4aaf734 at 0x008b584c: .rel.dyn ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc4aaf734->0xc4ab1be4 at 0x00c00734: .rel.plt ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc4ab1c00->0xc62b1590 at 0x00c02c00: .rodata ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc62b1590->0xc62b425c at 0x02402590: .gcc_except_table ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc62b425c->0xc68b46e8 at 0x0240525c: .eh_frame_hdr ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc68b46e8->0xc83ee774 at 0x02a056e8: .eh_frame ALLOC LOAD READONLY DATA HAS_CONTENTS
    0xc83ef000->0xceb16966 at 0x04540000: .text ALLOC LOAD READONLY CODE HAS_CONTENTS
    0xceb16966->0xceb18d5e at 0x0ac67966: text_env ALLOC LOAD READONLY CODE HAS_CONTENTS
    0xceb18d60->0xceb1d6d0 at 0x0ac69d60: .plt ALLOC LOAD READONLY CODE HAS_CONTENTS
    0xceb1e000->0xceb391fc at 0x0ac6f000: .data ALLOC LOAD DATA HAS_CONTENTS
    0xceb3a000->0xceb3a004 at 0x0ac8b000: .fini_array ALLOC LOAD DATA HAS_CONTENTS
    0xceb3a010->0xcedd4c5c at 0x0ac8b010: .data.rel.ro ALLOC LOAD DATA HAS_CONTENTS
    0xcedd4c5c->0xcedd4e60 at 0x0af25c5c: .init_array ALLOC LOAD DATA HAS_CONTENTS
    0xcedd4e60->0xcedd4f68 at 0x0af25e60: .dynamic ALLOC LOAD DATA HAS_CONTENTS
    0xcedd4f68->0xcedd6080 at 0x0af25f68: .got ALLOC LOAD DATA HAS_CONTENTS
    0xcedd6080->0xcedd72e4 at 0x0af27080: .got.plt ALLOC LOAD DATA HAS_CONTENTS
    0xcedd8000->0xcee8a898 at 0x0af282e4: .bss ALLOC
    0x0000->0x0000 at 0x00000000: *COM* IS_COMMON
    0x0000->0x0000 at 0x00000000: *UND*
    0x0000->0x0000 at 0x00000000: *ABS*
    0x0000->0x0000 at 0x00000000: *IND*
```

So I can see that the `.text` section starts at `0xc83ef000`. So if I point it
to my objdir binary, then:

```
(gdb) add-symbol-file /home/emilio/src/moz/gecko-4/obj-android-emulator-debug/toolkit/library/libxul.so 0xc83ef000
add symbol table from file "/home/emilio/src/moz/gecko-4/obj-android-emulator-debug/toolkit/library/libxul.so" at
	.text_addr = 0xc83ef000
(y or n) y
Reading symbols from /home/emilio/src/moz/gecko-4/obj-android-emulator-debug/toolkit/library/libxul.so...
(gdb) bt
[...]
#11 0xca7beba5 in mozilla::dom::ImageDocument::HandleEvent(mozilla::dom::Event*) (this=0xb33a7800, aEvent=0xafd504f0) at /home/emilio/src/moz/gecko-4/dom/html/ImageDocument.cpp:606
#12 0xca7beefd in  () at target:/data/app/org.mozilla.reference.browser.debug-2/lib/x86/libxul.so
#13 0xca670127 in mozilla::EventListenerManager::HandleEventSubType(mozilla::EventListenerManager::Listener*, mozilla::dom::Event*, mozilla::dom::EventTarget*)
    (this=0xafd5e5b0, aListener=0x0, aDOMEvent=0xafd504f0, aCurrentTarget=0xafd44000) at /home/emilio/src/moz/gecko-4/dom/events/EventListenerManager.cpp:1031
#14 0xca6706d6 in mozilla::EventListenerManager::HandleEventInternal(nsPresContext*, mozilla::WidgetEvent*, mozilla::dom::Event**, mozilla::dom::EventTarget*, nsEventStatus*, bool) (this=0xafd5e5b0, aPresContext=0xb3d9e0e0,
    aEvent=0xcfe88aa0, aDOMEvent=0xcfe88848, aCurrentTarget=0xafd44000, aEventStatus=0xcfe8884c, aItemInShadowTree=<optimized out>) at /home/emilio/src/moz/gecko-4/dom/events/EventListenerManager.cpp:1223
[...]
```

Hooray! It works!

After that, I just had to do a bit of `gdb` debugging, reproduce the bug in the
emulator, and [diagnose the
bug](https://bugzilla.mozilla.org/show_bug.cgi?id=1551659#c6). (Gotcha: JS
stacks and co appear on logcat rather than your gdb terminal).

Mission accomplished! I hope parts of this process get automated soon, but here
are my notes in case you (or me) need them.

There are things that could probably be done more easily, but I know nothing
about Gradle or such. If you want to send edits to this post or what not, you
should be able to send [a PR](https://github.com/emilio/words), or just feel
free to take this text and edit/publish it at your will.
