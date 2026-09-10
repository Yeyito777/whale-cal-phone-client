# Whale Cal for iPhone

A native SwiftUI iPhone client for [Whale Cal](https://github.com/Yeyito777/whale-cal), with live calendar sync over pinned SSH. Your existing `cald` daemon remains the source of truth—no cloud calendar copy, public calendar API, or embedded terminal.

## Features

- Compact month-first interface with month, week, agenda and deadline-checklist views.
- Dedicated Pending / Completed / All deadline filters, overdue/today/tomorrow sections, readable due dates and notes. All one-off deadlines remain available; recurring deadlines include their past occurrences and the next 12 months.
- Explicit, scoped bulk completion/reopening of selected deadlines, with confirmation, per-occurrence recurrence handling and partial-failure reporting.
- Full chronological day schedules, with earlier entries always visible—no collapsed sections or oversized overview card.
- Parallel, calendar-colored event cards on a scrollable day timeline, with exact shared time boundaries, compressed empty stretches and a subtle current-time line. Dense overlaps scroll horizontally instead of squeezing away titles.
- Completed occurrences stay as muted history but release their reservation. Maximal free spans are green, unboxed text—even alongside completed cards. Reopening reserves the time again.
- Event details link to directly overlapping unfinished reservations and show their exact shared time. All-day items, deadlines and unknown durations do not block availability.
- Events and deadlines, multiline notes, locations, optional durations and recurring series.
- Create, edit, delete, and complete/reopen individual recurring occurrences.
- Calendar management, colors and persistent calendar groups. Create/rename/delete groups, assign or ungroup calendars; deleting a group preserves its calendars and events.
- Calendar visibility filters are local to this phone and SSH source, persist across launches and work offline. They do not modify the terminal or other phones. Canonical server visibility flags are not used as phone filters.
- Locally remembered collapsible groups in the drawer. Collapsing never changes calendar visibility.
- Swipe right for the left-side calendar drawer; tap to select/deselect calendars, then swipe left or tap outside to dismiss.
- Search and connection details tucked into the overflow menu; no persistent statusline or connection badge.
- Automatic SSH connection, reconnect/backoff, heartbeat and live updates from other clients.
- Protected read-only offline snapshots. Changes are never silently queued or automatically retried.

Dates and times use the daemon's floating local wall-clock semantics, without timezone conversion. Weeks start on Monday. Week view is a week strip and selected-day timeline, not a seven-column hourly grid. Agenda/search cover the displayed range; deadline-checklist search covers its full checklist. Editing or deleting a recurring item affects its whole series; completion affects only the selected occurrence. Snapshot-based local recurrence expansion is parity-tested against the real daemon, including month-end/leap-day clamping and occurrence IDs.

## Requirements

- Xcode 16.2 or later, Swift 6, iOS 17 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- An Apple Development signing team and a paired iPhone in Developer Mode for installation.
- An SSH-accessible computer running a Whale Cal daemon with snapshot (`bootstrap`), completion and calendar-group IPC, plus a loopback-only TCP-to-Unix-socket bridge.

## Local configuration

Real hostnames, SSH public host keys, signing teams, device IDs, logs and calendar captures are intentionally **not** part of this repository.

```sh
git clone https://github.com/Yeyito777/whale-cal-phone-client.git
cd whale-cal-phone-client
cp Config/Local.example.xcconfig Config/Local.xcconfig
cp Config/Connection.example.json WhaleCal/Resources/Connection.local.json
```

Edit the two ignored local files:

1. `Config/Local.xcconfig`: set your `DEVELOPMENT_TEAM` and a unique `WHALE_CAL_BUNDLE_ID` (for example `com.yourname.whale-cal-phone`).
2. `WhaleCal/Resources/Connection.local.json`: set your SSH hostname, username, SSH port and the server's **verified Ed25519 public host key**, including the `ssh-ed25519` prefix. Leave `bridgeHost` at `127.0.0.1`; its port must match the bridge below.

Obtain the host key through a trusted channel on the server:

```sh
cat /etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Do not blindly trust an unauthenticated `ssh-keyscan` result. The app fails closed when configuration or a trusted host key is missing; it never accepts arbitrary host keys. Only public connection settings belong in the JSON file—never put an SSH private key or password in the app bundle.

## Computer-side bridge

On a Linux/systemd host, install `socat`, then copy `Server/whale-cal-phone-bridge.service` to `~/.config/systemd/user/`. Replace the example socket path in the unit with your running `cald` socket. `%h` is systemd's home-directory specifier.

```sh
systemctl --user daemon-reload
systemctl --user enable --now whale-cal-phone-bridge.service
systemctl --user status whale-cal-phone-bridge.service
ss -lntp | grep 46282
```

The listener **must** be `127.0.0.1:46282`, never `0.0.0.0` or `[::]`. Keep the calendar daemon managed by its existing installation. On macOS or another host, run the equivalent loopback-only `socat` bridge under that platform's service manager.

Traffic follows this route:

```text
iPhone → pinned SSH → direct-tcpip 127.0.0.1:46282 → cald Unix socket
```

## Build, sign and install

After creating your local configuration:

```sh
bash Scripts/generate-project.sh
xcodebuild -project WhaleCalPhoneClient.xcodeproj -scheme WhaleCalPhoneClient \
  -destination 'id=<your-device-UDID>' -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath DerivedData build

xcrun devicectl device install app --device '<your-device-ID>' \
  DerivedData/Build/Products/Debug-iphoneos/WhaleCal.app
```

You can also open the generated Xcode project and run it normally. The project itself is ignored because XcodeGen/Xcode may embed local signing metadata in it. Dependency versions are pinned in the root `Package.resolved`; the generation script copies this into the generated project's SwiftPM directory. When intentionally updating dependencies, copy the updated resolved file back to the root and review the diff.

### First-device authorization

On first launch, the app generates a unique Ed25519 private key **on the iPhone** and stores it in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Its public key is available under **⋯ → Connection** and in the `WHALE_CAL_DEVICE_PUBLIC_KEY` development-console entry.

Add only that public key to your server's `~/.ssh/authorized_keys`, with forwarding-only restrictions:

```text
restrict,port-forwarding,permitopen="127.0.0.1:46282",command="/usr/bin/false" ssh-ed25519 <device-public-key> whale-cal-ios
```

The app reconnects automatically after authorization. A first installation cannot authenticate until this step is complete. Revoke the device by removing its specific public-key line; never copy a private key from the computer onto the phone. Keep the bundle identifier stable across updates to retain access to the device's Keychain identity.

For an attached console from automation:

```sh
export WHALE_CAL_DEVICE='<your-device-ID>'
export WHALE_CAL_BUNDLE_ID='com.yourname.whale-cal-phone'
python3 Scripts/device-console.py
```

The helper allocates the PTY required by `devicectl --console`; ordinary redirected pipes can fail with POSIX error 22. The phone must be unlocked to launch. Console output and exported test artifacts can contain deployment details or private calendar data—keep them out of Git.

## Development and tests

```sh
bash Scripts/test-models.sh
# Requires Bun and a local Whale Cal source checkout; uses a temporary isolated daemon.
WHALE_CAL_REPO=/path/to/whale-cal python3 Scripts/test-ipc.py

# Requires your configured, authorized and unlocked iPhone.
xcodebuild -project WhaleCalPhoneClient.xcodeproj -scheme WhaleCalPhoneClient \
  -destination 'id=<your-device-UDID>' -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath DerivedData \
  -resultBundlePath .build/DeviceUITests.xcresult test
```

The model checks cover scheduling, overlap/overnight clipping, deadlines, per-occurrence completion, date grids and decoding. IPC tests exercise command shapes against an isolated real daemon, never your live calendar. UI tests perform read-only navigation/search/reconnect checks and capture screenshots; they do not modify calendar data.

### Layout

- `WhaleCal/App` — SwiftUI lifecycle.
- `WhaleCal/Core` — domain models, scheduling, local configuration, Keychain, pinned SSH, IPC, reconnect and offline cache.
- `WhaleCal/UI` — calendar, day/details, forms, calendar management and connection settings.
- `Config` — public configuration templates; actual settings are ignored.
- `Server` — example loopback bridge service.
- `Scripts` / `Tests` — icon generation, device console and regression tests.

The offline snapshot uses iOS file protection and may be purged by the OS. It is not an independent calendar store. Forms close only after a correlated daemon acknowledgment. If delivery is uncertain, inspect the live calendar before retrying.

## License

[MIT](LICENSE). Dependencies retain their respective licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
