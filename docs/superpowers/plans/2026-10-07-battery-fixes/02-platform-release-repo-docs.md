# Battery Fixes, Part 2 of 2: Platform, Release, Repo, Docs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shipped app match what the project claims: runs on macOS 13+, carries the release tag's version, ships without debug entitlements, and is documented correctly. Also clean build artifacts out of git.

**Architecture:** Mostly build settings, the release workflow and docs. The only Swift change removes dead pre-macOS-13 code paths. Builds on Part 1 (`01-device-model-k3v2-hid-bluetooth.md`, branch `fix/battery-sources-k3v2`).

**Tech Stack:** Xcode 26.6 project settings, GitHub Actions (`macos-latest`), SwiftPM (`BatteryKit`), Markdown.

**Spec:** No spec document. Argues from the codebase review in this session and findings ledgered during Part 1 (`get-task-allow` in Release, Task 3).

## Facts checked before writing (2026-10-07, this Mac)

- A Release build with `MACOSX_DEPLOYMENT_TARGET=13.0` compiles with no warnings; `vtool -show-build` reports `minos 13.0`.
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` removes `com.apple.security.get-task-allow`, leaving `app-sandbox`, `device.bluetooth`, `device.usb`.
- Passing `MARKETING_VERSION=9.9.9` to `xcodebuild` sets `CFBundleShortVersionString` to `9.9.9`.
- Tracked artifacts: `KeychronBattery_V1.0.7.dmg`, `KeychronBattery.xcodeproj/project.pbxproj.backup`, 3 files under `xcuserdata/`. No shared schemes exist; CI's `-scheme KeychronBattery` relies on xcodebuild's auto-created scheme.
- Tags `v1.0.3`…`v1.0.7` exist; the project says `MARKETING_VERSION = 1.0`.

## Global Constraints

- Deployment target: `MACOSX_DEPLOYMENT_TARGET = 13.0` (project and target, Debug and Release). `BatteryKit` already declares `.macOS(.v13)`.
- Release tags match `v<MAJOR>.<MINOR>.<PATCH>` with numeric parts only; `CFBundleShortVersionString` is the tag without the `v`.
- Release signing: no `com.apple.security.get-task-allow`. Debug keeps it (needed to attach the debugger).
- No git history rewrite. Files are untracked with `git rm --cached`; their past blobs stay in history.
- Untracked files that aren't ours (`GEMINI.md`, `.gemini/`, `.github/copilot-instructions.md`) are not touched.
- App build command (same as Part 1):
  `xcodebuild -project KeychronBattery.xcodeproj -scheme KeychronBattery -configuration Release -derivedDataPath ./build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build`
- Package tests: `swift test --package-path BatteryKit`

## Review Focus

1. **A user on macOS 13 or 14 opens the DMG:** the app launches. We have no such machine; the binary's `minos 13.0` plus no `#available` above 13 is the evidence. Check: Task 1 Step 3 (`vtool`) and Step 2 (grep for availability annotations above 13).
2. **Launch at Login after removing the fallbacks:** toggling it registers and unregisters the login item. Check: Task 1 Step 5 (manual, System Settings → General → Login Items).
3. **A tag the version can't use** (`v1.1.0-beta`, `v1.1`): the release job fails before building, with a message naming the tag. Check: Task 2 Step 2 (the guard script run locally against good and bad tags).
4. **A fresh clone after untracking `xcuserdata`:** CI's build still finds the `KeychronBattery` scheme. Check: Task 3 Step 5 (build from a clean clone).
5. **A broken BatteryKit change pushed with a tag:** the release fails instead of shipping. Check: Task 2 Step 1 (tests run in the workflow before the build).

---

### Task 1: Deployment target 13.0, remove dead fallbacks

**Files:**
- Modify: `KeychronBattery.xcodeproj/project.pbxproj` (both `MACOSX_DEPLOYMENT_TARGET = 15.7;` lines)
- Modify: `KeychronBattery/AppDelegate.swift` (`isLaunchAtLoginEnabled`, `enableLaunchAtLogin`, `disableLaunchAtLogin`)

**Interfaces:**
- Consumes: nothing.
- Produces: unchanged signatures `isLaunchAtLoginEnabled() -> Bool`, `enableLaunchAtLogin()`, `disableLaunchAtLogin()` (used by `StatusMenuController`).

No unit test can reach `SMAppService`; this task is verified by build, binary inspection and a manual toggle.

- [ ] **Step 1: Set `MACOSX_DEPLOYMENT_TARGET = 13.0` on both lines; replace each launch-at-login function body with its `SMAppService.mainApp` branch only**

Drop the `#available` checks, the `launchctl` `Process` fallback, `SMLoginItemSetEnabled`, and the now-unused `bundleId` guards. Keep the existing log lines.

- [ ] **Step 2: Check nothing needs a newer OS**

Run: `grep -rnE "#available|@available\(macOS (1[4-9]|2[0-9])" KeychronBattery BatteryKit/Sources`
Expected: no output.

- [ ] **Step 3: Build and inspect the binary**

Run the app build command, then `vtool -show-build build/Build/Products/Release/KeychronBattery.app/Contents/MacOS/KeychronBattery | grep minos` and `plutil -p build/Build/Products/Release/KeychronBattery.app/Contents/Info.plist | grep LSMinimumSystemVersion`.
Expected: `** BUILD SUCCEEDED **` with no Swift or SwiftLint warnings; `minos 13.0`; `"LSMinimumSystemVersion" => "13.0"`.

- [ ] **Step 4: Run `swift test --package-path BatteryKit`**

Expected: 30 tests pass.

- [ ] **Step 5: Manual check of Launch at Login**

Launch the built app, click Launch at Login. Expected: checkmark on; the app appears in System Settings → General → Login Items. Click again. Expected: checkmark off; it disappears from Login Items.

- [ ] **Step 6: Commit**

```bash
git add KeychronBattery.xcodeproj/project.pbxproj KeychronBattery/AppDelegate.swift
git commit -m "chore: target macOS 13 and drop unreachable login item fallbacks"
```

---

### Task 2: Release builds carry the tag version, run tests, ship without debug entitlements

**Files:**
- Create: `scripts/version-from-tag.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `KeychronBattery.xcodeproj/project.pbxproj` (target Release config)

**Interfaces:**
- Produces: `scripts/version-from-tag.sh <tag>` prints `MAJOR.MINOR.PATCH` and exits 0, or prints `error: tag '<tag>' is not vMAJOR.MINOR.PATCH` to stderr and exits 1.

- [ ] **Step 1: Write the failing check for the guard script**

Run:
```bash
for t in v1.0.8 v12.3.45 v1.1.0-beta v1.1 1.0.8; do printf '%s → ' "$t"; sh scripts/version-from-tag.sh "$t"; echo " (exit $?)"; done
```
Expected now: `No such file or directory` for every tag.

- [ ] **Step 2: Implement `scripts/version-from-tag.sh` (POSIX sh, executable) and rerun Step 1**

Expected: `v1.0.8 → 1.0.8 (exit 0)`, `v12.3.45 → 12.3.45 (exit 0)`, and exit 1 with the error message for `v1.1.0-beta`, `v1.1` and `1.0.8`.

- [ ] **Step 3: Set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` in the target's Release config only**

- [ ] **Step 4: Update `.github/workflows/release.yml`**

- `Get version from tag`: keep `VERSION` (the tag, used in the DMG name) and add `MARKETING=$(sh scripts/version-from-tag.sh "$VERSION")` to `$GITHUB_OUTPUT`.
- New step before `Build app`: `swift test --package-path BatteryKit`.
- `Build app`: add `MARKETING_VERSION=${{ steps.get_version.outputs.MARKETING }} CURRENT_PROJECT_VERSION=${{ github.run_number }}`.
- `Verify app bundle`: fail the job if `CFBundleShortVersionString` differs from `MARKETING`, or if `codesign -d --entitlements - --xml` output contains `get-task-allow`.
- Release notes: requirements `macOS 13.0 or later`; requirement line `Keychron keyboard with Bluetooth` becomes `A Keychron keyboard, or any Bluetooth device that reports its battery`; add feature line `🎧 Headsets and other Bluetooth Classic devices`.

- [ ] **Step 5: Check the workflow parses**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "ok"'` (and `actionlint .github/workflows/release.yml` if installed).
Expected: `ok`; actionlint reports nothing.

- [ ] **Step 6: Reproduce the CI build locally**

Run the app build command with `MARKETING_VERSION=$(sh scripts/version-from-tag.sh v1.0.8) CURRENT_PROJECT_VERSION=42` appended, then:
```bash
plutil -p build/Build/Products/Release/KeychronBattery.app/Contents/Info.plist | grep -E 'ShortVersion|CFBundleVersion"'
codesign -d --entitlements - --xml build/Build/Products/Release/KeychronBattery.app | plutil -p -
```
Expected: `1.0.8` and `42`; entitlements are exactly `app-sandbox`, `device.bluetooth`, `device.usb`.

- [ ] **Step 7: Debug keeps the debugger entitlement**

Run the app build command with `-configuration Debug` and `-derivedDataPath ./build-debug`, then the `codesign` line against `build-debug/Build/Products/Debug/KeychronBattery.app`.
Expected: `get-task-allow => true` is present. Delete `./build-debug` afterwards.

- [ ] **Step 8: Commit**

```bash
git add scripts/version-from-tag.sh .github/workflows/release.yml KeychronBattery.xcodeproj/project.pbxproj
git commit -m "ci: version releases from the tag, run BatteryKit tests, drop get-task-allow from Release"
```

---

### Task 3: Untrack build artifacts and per-user Xcode state

**Files:**
- Modify: `.gitignore`
- Untrack: `KeychronBattery_V1.0.7.dmg`, `KeychronBattery.xcodeproj/project.pbxproj.backup`, everything under `**/xcuserdata/`

**Interfaces:** none.

- [ ] **Step 1: Write the failing check**

Run: `git ls-files | grep -E '\.dmg$|\.backup$|xcuserdata/'`
Expected now: 5 paths.

- [ ] **Step 2: Untrack and ignore**

`git rm --cached` those paths (files stay on disk). Add to `.gitignore`: `*.dmg`, `*.backup`, `xcuserdata/`, `*.swp`, `build-debug`.

- [ ] **Step 3: Rerun Step 1 and check nothing new leaks in**

Run Step 1's command, then `git status --short --ignored | grep -E '\.dmg|\.backup|xcuserdata|\.swp'`.
Expected: Step 1 prints nothing; the second command lists those files only with `!!` (ignored).

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: stop tracking DMGs, project backups and per-user Xcode state"
```

- [ ] **Step 5: Build from a clean clone (Review Focus 4)**

```bash
S=$(mktemp -d) && git clone -q --branch "$(git branch --show-current)" . "$S/repo" && cd "$S/repo" && xcodebuild -project KeychronBattery.xcodeproj -scheme KeychronBattery -configuration Release -derivedDataPath ./build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build | tail -1
```
Expected: `** BUILD SUCCEEDED **`, proving the auto-created scheme works without `xcuserdata`. Remove `$S` afterwards.

---

### Task 4: Docs and user-facing copy

**Files:**
- Modify: `README.md`
- Modify: `KeychronBattery/Info.plist` (`NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`)

**Interfaces:** none.

- [ ] **Step 1: Write the failing check for the known-wrong statements**

Run: `grep -nE 'main\.swift|build/Release/KeychronBattery\.app' README.md`
Expected now: 3 matches (lines 107, 182, 281).

- [ ] **Step 2: Fix the README**

- Project Structure: remove `main.swift`; add `StatusMenuController.swift`, `RegistryBatteryMonitor.swift`, `ClassicBatteryMonitor.swift`, and a `BatteryKit/` entry ("pure logic and unit tests").
- Every app path uses `build/Build/Products/Release/KeychronBattery.app` (the `-derivedDataPath ./build` layout).
- Features: add Bluetooth Classic devices (headsets, keyboards such as the K3 V2 when macOS reports their battery) and wired Keychron raw HID (experimental: no battery reply decoded yet).
- Add a "Running tests" section: `swift test --package-path BatteryKit`.
- Releases: say the version comes from the tag and that tags must be `vMAJOR.MINOR.PATCH`.
- Troubleshooting: add "A Bluetooth device doesn't show" → check `system_profiler SPBluetoothDataType` for a `Battery Level:` line; without one macOS has no level to share.
- Requirements stay `macOS 13.0 or later` (true after Task 1).

- [ ] **Step 3: Update the Bluetooth usage strings**

Both keys: `This app needs Bluetooth access to show the battery level of your keyboard and other Bluetooth devices.`

- [ ] **Step 4: Rerun Step 1 and validate the plist**

Run Step 1's command, then `plutil -lint KeychronBattery/Info.plist`.
Expected: no matches; `OK`.

- [ ] **Step 5: Build and run the tests once more**

Run the app build command and `swift test --package-path BatteryKit`.
Expected: `** BUILD SUCCEEDED **` with no warnings; 30 tests pass.

- [ ] **Step 6: Commit**

```bash
git add README.md KeychronBattery/Info.plist
git commit -m "docs: correct README structure, paths and support; broaden Bluetooth usage text"
```
