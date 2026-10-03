# HassBar

Home Assistant quick access in the macOS menu bar. Requires macOS 15.7 or later; the project uses Xcode 26.3.

## Setup

1. Build and run the `HassBar` scheme in Xcode. Choose your signing team if needed.
2. Open **Connection** settings from the menu. Enter your Home Assistant HTTP(S) URL and a long-lived access token, created in your Home Assistant profile's security settings.
3. Use **Test Connection** to check the draft, then **Save** to apply it. The token is stored in Keychain. Reverse-proxy URL prefixes are supported.
4. In **Entities**, search by name, ID or alias, filter by domain, and select favorites. Customize aliases/icons and drag the handles to reorder favorites within their groups.
5. In **Menu Bar**, choose sensors to display beside the status icon, configure symbols, and drag to reorder them. The house icon remains available as a fallback when no sensor values can be displayed.

## Controls and state

- Lights/switches: on/off; supported lights also expose brightness and color temperature.
- Climate: supported on/off actions, HVAC modes and single target temperature. Range-only climates do not show the single-temperature slider.
- Covers: contextual open/close plus Stop when supported; locks: lock/unlock; scenes/scripts: Run.
- Other entities remain read-only. Unsupported actions are hidden when capability flags are available.
- Sliders support dragging, horizontal trackpad scrolling, arrow keys after clicking, and accessibility increment/decrement.

REST loads the initial snapshot. WebSocket events update entity states, with snapshot synchronization after reconnect. Opening a view reuses cached entities; **Refresh** explicitly requests current states. Failed refreshes retain the last known data and show an error. Missing saved favorites/sensors can be removed in settings.

## Validation

```sh
xcodebuild test -project HassBar.xcodeproj -scheme HassBar \
  -destination 'platform=macOS' -derivedDataPath /tmp/HassBar-build \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -project HassBar.xcodeproj -scheme HassBar \
  -configuration Release -derivedDataPath /tmp/HassBar-build \
  CODE_SIGNING_ALLOWED=NO
```

Tests use fake configuration/clients and cover decoding, request construction, protocol handshake, lifecycle races, persistence and action mapping. Real server/device acceptance and distribution signing are separate checks.

See the [implementation and UI review](docs/reviews/2026-10-03-implementation-and-ui.md) for findings, changes and verification limits.
