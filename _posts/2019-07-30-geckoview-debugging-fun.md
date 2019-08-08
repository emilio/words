---
layout: post
title:  Debugging GeckoView in Reference-Browser in the x86 android emulator
date:   2019-07-30 19:07:00
---

*Aside*: Phew, it's been almost four years since I last wrote something.

## Building GeckoView

I'm interested in doing regular debugging with `gdb` / `lldb`, so I want an
unoptimized build.

I also want to run this in an x86 emulator, since debugging on a real ARM device
was a pain last time I tried.

A `mozconfig` like this would do the trick (replacing `/home/emilio` for the
appropriate path, or the relevant ndk path if you're using a custom one):

```sh
# Regular Gecko build bits.
mk_add_options AUTOCLOBBER=1
ac_add_options --enable-debug
ac_add_options --disable-optimize

# Android specific bits
ac_add_options --enable-application=mobile/android
ac_add_options --with-android-ndk=/home/emilio/.mozbuild/android-ndk-r17b

# For the x86 android emulator
ac_add_options --target=i686-linux-android
```

To get GVE (GeckoView Example) building, just:

```sh
$ ./mach build
```

To get it running, we first install / launch the android emulator with:

```sh
$ ./mach android-emulator --version x86-7.0
```

Then we install the GVE application:

```sh
$ ./mach android package-geckoview_example
$ ./mach android install-geckoview_example
```

Now you should be able to tap on GVE and load a website, and see all the logging
spew in `adb logcat`.

If it fails to start, it may be for a variety of reasons... In my case the first
time it failed with `Couldn't load mozglue. Trying native library dir.`. This
particular error went magically away with a rebase + rebuild that I did to peek
the fix for [bug 1561323](https://bugzilla.mozilla.org/show_bug.cgi?id=1561323).
I couldn't reproduce it again so I couldn't file a bug for that.

But anyhow, first step, done!

## Publishing GeckoView to a local Maven repository.

I've never done any Gradle stuff so this sounded like some obscure language to
me, but luckily this happens to be documented [here][gv-dependency-override],
and it's just a matter of:

```sh
$ ./gradlew geckoview:publishWithGeckoBinariesDebugPublicationToMavenLocal
```

## Building and installing Reference Browser.

This should be just a matter of, from the [`reference-browser` repo][rb]:

```
$ ./gradlew assembleDebug
$ ./gradlew installDebug
```

That should give you a nice "Reference Browser" icon that should, in theory
spawn it. However I hit a hard-to-workaround problem here, which is that there
was an Intel-specific build issue, so I had to stop here for today (or not
quite, see below).

## Making Reference Browser use the local GeckoView.

I got this to work while trying to figure out that aforementioned issue.

This was also documented [here][gv-dependency-override], though slightly out of
date. Also the example is for arm instead of x86.

Anyhow, the way I made it not complain was the following:

```patch
diff --git a/app/build.gradle b/app/build.gradle
index 55006ac..d804e6f 100644
--- a/app/build.gradle
+++ b/app/build.gradle
@@ -188,6 +188,8 @@ if (project.hasProperty("telemetry") && project.property("telemetry") == "true")
 }
 
 dependencies {
+    implementation "org.mozilla.geckoview:geckoview-nightly:70.0.2019073015432"
+
     implementation Deps.mozilla_concept_engine
     implementation Deps.mozilla_concept_tabstray
     implementation Deps.mozilla_concept_toolbar
diff --git a/build.gradle b/build.gradle
index 9402765..02cca08 100644
--- a/build.gradle
+++ b/build.gradle
@@ -19,6 +19,7 @@ plugins {
 
 allprojects {
     repositories {
+        mavenLocal()
         google()
 
         maven {
```

Note that my maven `geckoview` directory looks like:

```
└── geckoview-default
    ├── 70.0.20190730154324
    │   ├── geckoview-default-70.0.20190730154324.aar
    │   ├── geckoview-default-70.0.20190730154324-javadoc.jar
    │   ├── geckoview-default-70.0.20190730154324.pom
    │   └── geckoview-default-70.0.20190730154324-sources.jar
    └── maven-metadata-local.xml
```

But instead I had to use `geckoview-nightly` rather than `geckoview-default`.
That's a bit weird but *shrug*.

Now you should get your own GeckoView build in the Reference Browser.

## Gotchas

Once you have a build running, the building and debugging cycle for Gecko
changes is a bit annoying:

```sh
$ ./mach build
$ ./gradlew geckoview:publishWithGeckoBinariesDebugPublicationToMavenLocal
$ cd /path/to/reference-browser
$ ./gradlew assembleDebug
$ ./gradlew installDebug
```

Note that I _think_ that various bits in this process are a bit broken. For
example the `publishWithGeckoBinariesDebugPublicationToMavenLocal` didn't seem
to take my changes to `libxul.so` into account. I had to blow up the
`~/.m2/repository/org/mozilla/geckoview` directory and run it again. I haven't
seen if it's reproducible, will check once I can actually build and file a bug
if so.

Similarly, I'm not sure if `./gradlew assembleDebug` and co would peek changes
to the local Maven repo automatically, given it won't have a version change
AIUC, so might need `./gradlew clean` or such. Will try to update as needed.

## Thanks

Thanks a bunch to Emily Toop, James Willcox, Sebastian Kaspari, Nick Alexander,
Edouard Oger and all the other people that helped me out :)

[gv-dependency-override]: https://mozilla.github.io/geckoview/contributor/geckoview-quick-start#include-geckoview-as-a-dependency
