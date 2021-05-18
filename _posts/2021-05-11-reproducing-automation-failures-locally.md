---
layout: post
title:  "Reproducing automation failures locally"
date:   2021-05-05 10:51 PM
---

So I am trying to do a change to the Firefox UI to draw shadows on popups on
Linux. How hard could it be? The patch is [relatively
simple](https://phabricator.services.mozilla.com/D113990).

So, for starters, my patch caused all sorts of weird timeouts on Windows. Turns
out that semi-transparent popups are _hard_.

Anyhow, the Windows failure reproduced locally, so even though I suck at Windbg
(and every single time I have to debug on Windows I miss rr like crazy) it was
not too terrible to figure out [one of
them](https://bugzilla.mozilla.org/show_bug.cgi?id=1710486). The [other
one](https://bugzilla.mozilla.org/show_bug.cgi?id=1710533) Sotaro figured out
before I got up the next day, yay!

But it was not so easy... There was some other orange in my try run. Some Linux
tests were crashing like this:

<details>

```
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -  3  libc.so.6!__assert_fail [assert.c : 101 + 0x1e]
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rbx = 0x00007f6582f090e8   rbp = 0x00007f6582f08f53
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc000   r12 = 0x0000000000000103
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r13 = 0x00007f6582f09398   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6584fc84a2
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -  4  libX11.so.6!poll_for_event [xcb_io.c : 256 + 0x1f]
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rbx = 0x00007f6585384840   rbp = 0x00007f6584d58890
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc030   r12 = 0x00007ffe013bc058
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc060   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6582e97e3a
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -  5  libX11.so.6!poll_for_response [xcb_io.c : 274 + 0x8]
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rbx = 0x00007f65668ae0c0   rbp = 0x00007f6584dd6000
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc050   r12 = 0x00007ffe013bc058
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc060   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6582e97ede
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -  6  libX11.so.6!_XEventsQueued [xcb_io.c : 358 + 0x8]
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rbx = 0x00007f6584dd6000   rbp = 0x0000000000000000
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc0a0   r12 = 0x0000000000000000
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc108   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6582e981cd
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -  7  libX11.so.6!XPending [Pending.c : 55 + 0xd]
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rbx = 0x00007f6584dd6000   rbp = 0x0000000000000000
[task 2021-05-10T20:57:14.716Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc0b0   r12 = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc108   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6582e89ced
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -  8  libgdk-3.so.0!gdk_event_source_prepare [gdkeventsource.c : 287 + 0x5]
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rbx = 0x00007f6584d68760   rbp = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc0d0   r12 = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc108   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f658360b09e
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -  9  libglib-2.0.so.0!g_main_context_prepare [gmain.c : 3474 + 0x10]
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rbx = 0x00007f6584dd1f50   rbp = 0x00007ffe013bc110
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc0f0   r12 = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc108   r14 = 0x000000007fffffff
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r15 = 0x00007ffe013bc190   rip = 0x00007f6580c3bc48
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO - 10  libglib-2.0.so.0!g_main_context_iterate.isra.26 [gmain.c : 3882 + 0xd]
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rbx = 0x00007f6584dd1f50   rbp = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc180   r12 = 0x00007f65698fcd20
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r13 = 0x00007ffe013bc194   r14 = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r15 = 0x0000000000000003   rip = 0x00007f6580c3c61b
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     Found by: call frame info
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO - 11  libglib-2.0.so.0!g_main_context_iteration [gmain.c : 3963 + 0x14]
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rbx = 0x00007f6584dd1f50   rbp = 0x0000000000000000
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     rsp = 0x00007ffe013bc1e0   r12 = 0x000000000024b1de
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r13 = 0x00007f657061c0a0   r14 = 0x00007f657198d1a0
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     r15 = 0x0000000000000001   rip = 0x00007f6580c3c7fc
[task 2021-05-10T20:57:14.717Z] 20:57:14     INFO -     Found by: call frame info
```

</details>

So, an assert deep in `libX11.so`. That sure looks like fun. It is intermittent,
but it happens frequently enough that it'll probably get me backed out if I try
to land my patch.

However, this one does _not_ reproduce locally. Automation is using an Ubuntu
LTS machine, and I'm on Fedora 34, so there's a lot of subtle differences in my
setup compared to automation.

So, how do I debug this? The issue is that I'm fairly certain than the failure
being related to semi-transparent popups. However the whole point of my patch is
to enable those, so that I can draw shadows around the popup's content (since in
Wayland or WebRender the OS compositor won't draw them).

I decided to try to reproduce the failure locally by using one of the VMs that
automation uses. That surely should work? Then hopefully I can pull rr into the
machine and debug it, or something.

*How hard could it be?*

## Step 1: Getting the Docker image

So [Mike](https://glandium.org) helpfully pointed me to the `./mach
taskcluster-load-image` command. That looked exactly like what I needed!

It accepts an image name, so after grepping a bit I found
[`ci/docker-image/kind.yml`](https://searchfox.org/mozilla-central/rev/6b099d836c882bc155d2ef285e0ad0ab9f5038f6/taskcluster/ci/docker-image/kind.yml),
which has an `ubuntu1804-test` image, which looks just like what I want?

Just `./mach taskcluster-load-image ubuntu1804-test` and we should be done,
right? But then I wouldn't need to write this up :)

In fact, `./mach taskcluster-load-image ubuntu1804-test` failed with:

```
$ ./mach taskcluster-load-image ubuntu1804-test
Could not find artifacts for a docker image named `ubuntu1804-test`. Local
commits and other changes in your checkout may cause this error. Try updating to
a fresh checkout of mozilla-central to download image.
```

Well, that's not very encouraging. I'm on a fresh checkout...

After asking in the `#firefox-ci` channel on matrix, I got told that passing
a task id is the way to go. However, which task id?

I tried to pass the task id of my failed try run job (which is at the left
column in the bottom panel Treeherder), but that didn't cut it.

Aki helped me and told me how:

> I'd click on the taskId in the lower left to go to the task, then click see
> more on the left to see the dependencies, then click on the
> `docker-image-ubuntu1804-test` task, then in the URL I'd see its taskId is
> `B-JJNLv6TD-oE1Ie80KG2`.

Great! Let's try:

```
`$ ./mach taskcluster-load-image --task-id B-JJNLv6TD-oE1Ie80KG2Q
Traceback (most recent call last):
  File "/home/emilio/src/moz/gecko-3/third_party/python/requests/requests/adapters.py", line 467, in send
    low_conn.endheaders()
  File "/usr/lib64/python3.9/http/client.py", line 1248, in endheaders
    self._send_output(message_body, encode_chunked=encode_chunked)
  File "/usr/lib64/python3.9/http/client.py", line 1008, in _send_output
    self.send(msg)
  File "/usr/lib64/python3.9/http/client.py", line 948, in send
    self.connect()
  File "/home/emilio/src/moz/gecko-3/third_party/python/requests-unixsocket/requests_unixsocket/adapters.py", line 32, in connect
    sock.connect(socket_path)
PermissionError: [Errno 13] Permission denied
```

Hmm... That's not great. After some printf debugging, socket_path was
`/var/run/docker.sock`, which was in fact on my machine. Why didn't that work?

I tried multiple things, with little success. Until I found out that Fedora has
a `podman-docker` package, which is what is providing my `docker.sock` file,
which is some kind of docker emulation on top of podman. I tried to make it
work, but couldn't, so I ended up uninstalling that and installing real docker:

```
$ sudo dnf remove podman-docker
$ sudo dnf install docker
```

Alright, one more try:

```
$ ./mach taskcluster-load-image --task-id B-JJNLv6TD-oE1Ie80KG2Q
Downloading from https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/B-JJNLv6TD-oE1Ie80KG2Q/artifacts/public/image.tar.zst
Loaded image: ubuntu1804-test:latest
Found docker image: docker.io/library/ubuntu1804-test:latest
Try: docker run -ti --rm docker.io/library/ubuntu1804-test:latest bash
```

Wait, it worked? _It worked!_

Ok, so now we have a docker image, and running that command does get me a shell
into the image. Now how the heck do I run the test?

## Step 2: Running the task

[Steve Fink](https://twitter.com/hotsphink) helpfully told me that he tried to
do something similar once and that setting the environment variables in the task
definition and running the command worked for him.

The task definition from my failed try job had a `payload` member with a bunch
of `env` variables, and a `command` array... Seemed easy enough. With a bit of
devtools and one more try (because it was trying to use a `TASKCLUSTER_ROOT_URL`
env var which wasn't there), I came up with a snippet which gave me what
I needed:

```js
(async function() {
  let task = await fetch("https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/IOHH3Zh8SVeWVa7CRM3wRA").then(response => response.json());
  let command = "TASKCLUSTER_ROOT_URL=\"https://firefox-ci-tc.services.mozilla.com\" ";
  for (let [k, v] of Object.entries(task.payload.env)) {
    command += (k + "=\"" + v.replaceAll("\"", "\\\"") + "\" ");
  }
  command += task.payload.command.join(" ")
  console.log(command);
  document.open(); document.write(command); document.close()
}());
```

That came up with a monster command that looked like this:

```
TASKCLUSTER_ROOT_URL="https://firefox-ci-tc.services.mozilla.com" PYTHON="python3" GECKO_PATH="/builds/worker/checkouts/gecko" ENABLE_E10S="false" MOZ_FETCHES="[{\"artifact\": \"public/build/fix-stacks.tar.xz\", \"extract\": true, \"task\": \"aJ65Yi9ERxOkr_NzWQHnaQ\"}, {\"artifact\": \"public/build/minidump_stackwalk.tar.xz\", \"extract\": true, \"task\": \"Z1qS3AoySACOdTdOnyE1Cg\"}]" WORKING_DIR="/builds/worker" TRY_SELECTOR="fuzzy" HG_STORE_PATH="/builds/worker/checkouts/hg-store" MOZ_NODE_PATH="/usr/local/bin/node" MOZ_SCM_LEVEL="1" GECKO_HEAD_REV="bb7b4afe31ae79d2b3ba8712af8fd4d88d2223e5" MOZHARNESS_URL="https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/DDYmQ8I0RTygbCciGfChpA/artifacts/public/build/mozharness.zip" MOZ_AUTOMATION="1" TOOLTOOL_CACHE="/builds/worker/tooltool-cache" TRY_COMMIT_MSG="" MOZ_FETCHES_DIR="fetches" NEED_PULSEAUDIO="true" SCCACHE_DISABLE="1" MOCHITEST_FLAVOR="chrome" MOZHARNESS_CONFIG="unittests/linux_unittest.py remove_executables.py" MOZHARNESS_SCRIPT="desktop_unittest.py" MOZILLA_BUILD_URL="https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/DDYmQ8I0RTygbCciGfChpA/artifacts/public/build/target.tar.bz2" TASKCLUSTER_CACHES="/builds/worker/checkouts;/builds/worker/tooltool-cache" NEED_WINDOW_MANAGER="true" TASKCLUSTER_VOLUMES="/builds/worker/.cache;/builds/worker/checkouts;/builds/worker/tooltool-cache;/builds/worker/workspace" GECKO_BASE_REPOSITORY="https://hg.mozilla.org/mozilla-unified" GECKO_HEAD_REPOSITORY="https://hg.mozilla.org/try" MOZHARNESS_TEST_PATHS="{\"mochitest-chrome\": [\"browser/components/aboutlogins/tests/chrome/chrome.ini\", \"caps/tests/mochitest/chrome.ini\", \"devtools/client/memory/test/chrome/chrome.ini\", \"devtools/client/performance/components/chrome/chrome.ini\", \"devtools/shared/qrcode/tests/chrome/chrome.ini\", \"devtools/shared/tests/chrome/chrome.ini\", \"devtools/shared/webconsole/test/chrome/chrome.ini\", \"dom/animation/test/chrome.ini\", \"dom/base/test/chrome.ini\", \"dom/base/test/chrome/chrome.ini\", \"dom/base/test/jsmodules/chrome.ini\", \"dom/bindings/test/chrome.ini\", \"dom/canvas/test/chrome/chrome.ini\", \"dom/grid/test/chrome.ini\", \"dom/html/test/forms/chrome.ini\", \"dom/indexedDB/test/chrome.ini\", \"dom/l10n/tests/mochitest/chrome.ini\", \"dom/network/tests/chrome.ini\", \"dom/promise/tests/chrome.ini\", \"dom/system/tests/ioutils/chrome.ini\", \"dom/tests/mochitest/beacon/chrome.ini\", \"dom/tests/mochitest/sessionstorage/chrome.ini\", \"dom/tests/mochitest/whatwg/chrome.ini\", \"dom/url/tests/chrome.ini\", \"dom/websocket/tests/chrome.ini\", \"editor/composer/test/chrome.ini\", \"editor/libeditor/tests/chrome.ini\", \"intl/l10n/test/mochitest/chrome.ini\", \"js/xpconnect/tests/chrome/chrome.ini\", \"layout/base/tests/chrome/chrome.ini\", \"layout/inspector/tests/chrome/chrome.ini\", \"security/manager/ssl/tests/mochitest/stricttransportsecurity/chrome.ini\", \"testing/mochitest/chrome/chrome.ini\", \"toolkit/components/aboutmemory/tests/chrome.ini\", \"toolkit/components/certviewer/tests/chrome/chrome.ini\", \"toolkit/components/extensions/test/mochitest/chrome.ini\", \"toolkit/components/places/tests/chrome/chrome.ini\", \"toolkit/components/viewsource/test/chrome.ini\", \"toolkit/components/windowcreator/test/chrome.ini\", \"toolkit/components/windowwatcher/test/chrome.ini\", \"toolkit/components/xulstore/tests/chrome/chrome.ini\", \"toolkit/content/tests/chrome/chrome.ini\", \"toolkit/modules/tests/chrome/chrome.ini\", \"toolkit/mozapps/extensions/test/mochitest/chrome.ini\", \"tools/profiler/tests/chrome/chrome.ini\", \"xpfe/appshell/test/chrome.ini\"]}" EXTRA_MOZHARNESS_CONFIG="{\"installer_url\": \"https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/DDYmQ8I0RTygbCciGfChpA/artifacts/public/build/target.tar.bz2\", \"test_packages_url\": \"https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/DDYmQ8I0RTygbCciGfChpA/artifacts/public/build/target.test_packages.json\"}" TASKCLUSTER_UNTRUSTED_CACHES="1" /builds/worker/bin/run-task --fetch-hgfingerprint -- /builds/worker/bin/test-linux.sh --mochitest-suite=mochitest-chrome --setpref=media.peerconnection.mtransport_process=false --setpref=network.process.enabled=false --disable-e10s --allow-software-gl-layers --download-symbols=ondemand
```

That seems good enough, and running it does try to do stuff. But unfortunately
the tests failed, but not as I was hoping:

```
ERROR - Couldn't find a v4l2loopback video device
```

Gahhh. Looking around the task definition, I see that there is an `scopes` array
that had various entries, including
`"docker-worker:capability:device:loopbackVideo"`, which seemed relevant. But
I didn't know how I could fix it.

[Ben Hearsum](https://bhearsum.blogspot.com) helpfully pointed me to the
Taskcluster [`docker-worker`
docs](https://github.com/taskcluster/taskcluster/blob/66941613e4242d69dd2aff3fb560359eb633d59c/ui/docs/reference/workers/docker-worker/capabilities.mdx#loopbackvideo)
which had this:

> This device requires the `v4l2loopback` driver be installed in the kernel.

Sure, fair enough! `sudo dnf install v4l2loopback` away, ensuring the module is
loaded, and retry... But still nothing.

Do I need the module on the VM instead? Let's try:

```
# apt update
# apt install v4l2loopback-dkms
# dkms build v4l2loopback/0.10.0
Error! Your kernel headers for kernel 5.11.17-300.fc34.x86_64 cannot be found.
Please install the linux-headers-5.11.17-300.fc34.x86_64 package,
or use the --kernelsourcedir option to tell DKMS where it's located
```

Huh, wtf? Why is it trying to compile it against my host OS?

I got it after a bit (container != vm... fun!). So looking at the code, the
mochitest harness expects a /dev/video* which is a loopback device...
I installed the kernel driver in my host OS, so after testing a bit I found it:

```
$ v4l2-ctl --all -d /dev/video2
Driver Info:
	Driver name      : v4l2 loopback
	Card type        : OBS Virtual Camera
	Bus info         : platform:v4l2loopback-000
	Driver version   : 5.11.17
	Capabilities     : 0x85208002
		Video Output
		Video Memory-to-Memory
		Read/Write
		Streaming
		Extended Pix Format
		Device Capabilities
	Device Caps      : 0x05208002
		Video Output
		Video Memory-to-Memory
		Read/Write
		Streaming
		Extended Pix Format
[...]
```

So I need to get that device to the container somehow. After playing a bit with
the options I see a `--device` flag in docker. Let's try:

```
$ docker run -ti --device /dev/video2 docker.io/library/ubuntu1804-test:latest bash
```

That should work, right? I see a /dev/video2 file now... Well, it doesn't.

Some more debugging reveals the open() call
[here](https://searchfox.org/mozilla-central/rev/6b099d836c882bc155d2ef285e0ad0ab9f5038f6/testing/mochitest/runtests.py#775)
fails. Let's build a dumb script to test it:

<details>

```
import ctypes
import sys
from ctypes.util import find_library

libc = ctypes.cdll.LoadLibrary(find_library("c"))
O_RDWR = 2
# These are from linux/videodev2.h

class v4l2_capability(ctypes.Structure):
    _fields_ = [
        ("driver", ctypes.c_char * 16),
        ("card", ctypes.c_char * 32),
        ("bus_info", ctypes.c_char * 32),
        ("version", ctypes.c_uint32),
        ("capabilities", ctypes.c_uint32),
        ("device_caps", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32 * 3),
    ]

VIDIOC_QUERYCAP = 0x80685600

fd = libc.open("/dev/video2", O_RDWR)
if fd < 0:
    sys.exit(1);

vcap = v4l2_capability()
if libc.ioctl(fd, VIDIOC_QUERYCAP, ctypes.byref(vcap)) != 0:
    sys.exit(2);

print(vcap.driver)
if vcap.driver != "v4l2 loopback":
    sys.exit(3);

class v4l2_control(ctypes.Structure):
    _fields_ = [("id", ctypes.c_uint32), ("value", ctypes.c_int32)]

# These are private v4l2 control IDs, see:
# https://github.com/umlaeute/v4l2loopback/blob/fd822cf0faaccdf5f548cddd9a5a3dcebb6d584d/v4l2loopback.c#L131
KEEP_FORMAT = 0x8000000
SUSTAIN_FRAMERATE = 0x8000001
VIDIOC_S_CTRL = 0xC008561C

control = v4l2_control()
control.id = KEEP_FORMAT
control.value = 1
libc.ioctl(fd, VIDIOC_S_CTRL, ctypes.byref(control))

control.id = SUSTAIN_FRAMERATE
control.value = 1
libc.ioctl(fd, VIDIOC_S_CTRL, ctypes.byref(control))
```

</details>

So adding the `video` group should do:

```
$ docker run -ti --device /dev/video2 --group-add=video [...]
```

But that still fails. I try to run it on the host and it also fails. If I use
`O_RDONLY` then `open()` works, but `ioctl()` fails... :((

So I think I'm going to try to work around it by avoiding this hacky loopback
device thing, if I can manage to do that...

In fact, a patch like this pushed to try along my changes allows me to run
tests!

```diff

diff --git a/testing/mochitest/runtests.py b/testing/mochitest/runtests.py
--- a/testing/mochitest/runtests.py
+++ b/testing/mochitest/runtests.py
@@ -2151,17 +2151,17 @@ toolbar#nav-bar {
                 "Increasing default timeout to {} seconds".format(extended_timeout)
             )
             prefs["testing.browserTestHarness.timeout"] = extended_timeout
 
         if getattr(self, "testRootAbs", None):
             prefs["mochitest.testRoot"] = self.testRootAbs
 
         # See if we should use fake media devices.
-        if options.useTestMediaDevices:
+        if False:
             prefs["media.audio_loopback_dev"] = self.mediaDevices["audio"]
             prefs["media.video_loopback_dev"] = self.mediaDevices["video"]
             prefs["media.cubeb.output_device"] = "Null Output"
             prefs["media.volume_scale"] = "1.0"
 
         self.profile.set_preferences(prefs)
 
         # Extra prefs from --setpref
@@ -3045,17 +3045,17 @@ toolbar#nav-bar {
         # https://github.com/mozilla/mozbase/blob/master/mozrunner/mozrunner/local.py#L42
 
         debuggerInfo = None
         if options.debugger:
             debuggerInfo = mozdebug.get_debugger_info(
                 options.debugger, options.debuggerArgs, options.debuggerInteractive
             )
 
-        if options.useTestMediaDevices:
+        if False:
             devices = findTestMediaDevices(self.log)
             if not devices:
                 self.log.error("Could not find test media devices to use")
                 return 1
             self.mediaDevices = devices
 
         # See if we were asked to run on Valgrind
         valgrindPath = None
 
```

(Not a very impressive patch, I know).

With that, I managed to run a whole task successfully. Takes a while though. It
still didn't reproduce the bug I was interested in, at least not first try, but
will try a couple more times before giving up!
