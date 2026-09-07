#!/usr/bin/env python3
"""devicectl --console requires a real PTY when launched from an automation tool."""
import os
import pathlib
import pty
import sys

device = os.environ.get("WHALE_CAL_DEVICE")
bundle = os.environ.get("WHALE_CAL_BUNDLE_ID")
if not device or not bundle:
    sys.exit("Set WHALE_CAL_DEVICE to your device ID and WHALE_CAL_BUNDLE_ID to your app bundle identifier.")
path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/whale-cal-device-console.log")
pid, fd = pty.fork()
if pid == 0:
    os.execvp("xcrun", ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
                        "--terminate-existing", "--console", bundle])
try:
    with path.open("wb", buffering=0) as log:
        while True:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            log.write(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
finally:
    os.close(fd)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
