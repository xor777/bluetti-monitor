# Bluetti Monitor

Bluetti Monitor is a small macOS menu bar app for the BLUETTI Premium 100 V2.

When mains power goes out, the power station keeps the Mac running so smoothly that the outage can be easy to miss. Bluetti Monitor watches the station over Bluetooth and warns when external power disappears. This gives you time to save your work and shut the Mac down calmly.

## What it shows

- external power status and input voltage;
- battery charge;
- the station-reported remaining discharge time while running on battery under load and not charging;
- current input and output power;
- connection and data freshness;
- an orange battery warning at 20% or below, and a red warning at 10% or below;
- notifications when mains power is lost or restored;
- a low-battery notification while the station is running without external power;
- notifications when the connection to the device is lost or restored.

The app lives in the menu bar and uses a single icon slot. It does not open a Dock window. Launch at login is available as an opt-in setting. The interface follows the macOS language and appearance by default; Settings also offers manual English or Russian and Light or Dark overrides. Changes apply immediately and persist across launches.

## Install

1. Download the latest ZIP from [GitHub Releases](https://github.com/xor777/bluetti-monitor/releases/latest).
2. Unzip it and move `Bluetti Monitor.app` to `Applications`.
3. Control-click the app, choose **Open**, and confirm the first launch.
4. In the setup popover, choose **Find station** and allow Bluetooth when macOS asks.
5. Select the station if more than one is found.
6. Wait for the app to confirm the station's current power state. The monitoring screen appears automatically when fresh data arrives.
7. Enable notifications from the monitoring screen if you want outage warnings.
8. Optionally open **Settings…** and enable **Launch at login**. Manual launch continues to work when login registration is unavailable.

The current build requires macOS 13 or newer and an Apple silicon Mac. It is ad-hoc signed and not notarized, which is why the first launch needs the extra confirmation.

Keep the official BLUETTI mobile app disconnected while using Bluetti Monitor. The station may allow only one active Bluetooth connection.

To switch stations later, open **Settings…** from the menu in the top-right corner of the popover, then choose **Change…** in the **Device** section. The chooser shows a stable Bluetooth identity so identical model names can be distinguished.

## Privacy

Everything stays on the Mac. Bluetti Monitor connects directly to the power station over Bluetooth. It does not use a BLUETTI account, send analytics, or make network requests.

The connection is read-only: the app reads telemetry and does not change device settings or switch outputs.

## Current scope

This is an early MVP built and tested for one model: `Premium 100 V2` (`PR100V2`). Other BLUETTI devices may use different data layouts and are not supported yet.

Monitoring works while the Mac is awake. The current version has no history, cloud sync, remote access, or device controls. Launch at login is optional and can require approval in macOS System Settings.

## Build from source

Requirements:

- macOS 13 or newer;
- Apple silicon;
- Xcode Command Line Tools.

Build and verify the app:

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
```

The standalone app is written to `dist/Bluetti Monitor.app`.

Render the real SwiftUI popover in deterministic light and dark fixtures:

```bash
./scripts/render-previews.sh
```

The PNG gallery and its manifest are written to `.artifacts/ui-previews`. Fixture rendering starts through a dedicated command-line branch and does not scan for Bluetooth devices, request permissions, register a login item, or send notifications.

### Add a language

Localization uses standard Foundation resources in `Sources/BluettiCore/Resources`. To add a language, create a `<language>.lproj` directory beside `en.lproj` and `ru.lproj`, then add complete translations for `Localizable.strings`, `Localizable.stringsdict`, and `InfoPlist.strings`. Keep every format placeholder and plural key aligned with the English files.

No Swift language switch is needed. The Settings picker discovers localized resource directories and shows each language in its native name. Finish by running the tests, app build, app verifier, and preview renderer shown above; the tests check key and placeholder parity for every shipped localization, while the verifier checks that the resources still work in a copied standalone app.

The repository also contains the original Python probe under `spike/`. It was used to understand the device protocol; the menu bar app itself is written in Swift.

## License

[MIT](LICENSE)

BLUETTI is a trademark of its respective owner. This is an independent open-source project and is not affiliated with or endorsed by BLUETTI.
