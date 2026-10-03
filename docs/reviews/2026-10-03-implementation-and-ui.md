# HassBar implementation and UI review

Date: 2026-10-03 (Asia/Taipei). Baseline: `c106197` on `main`, with a clean working tree.

## Scope and assessment

Reviewed the app shell, every Swift implementation file, persistence, Keychain wrapper, REST and WebSocket clients, store, entity models/action mapping, all settings/menu/control views, existing tests, Xcode target settings, entitlements, and original design document. The original June design describes an MVP; the current implementation additionally supports menu bar sensors, aliases/icons, light controls, and climate controls.

The client/store/view boundaries and protocol-based REST/Keychain injection provide a useful foundation. The main problems were observable correctness failures, asynchronous lifecycle races, unsafe optional-data handling, and UI states that concealed failures or missing selections. These were addressed in separate validated commits rather than replacing the native SwiftUI design.

## Findings and changes

| Priority | Baseline problem and user impact | Resolution |
| --- | --- | --- |
| P1 | WebSocket reads `event_type` inside `event.data`; actual state events place it on `event`. Live cache updates are ignored. | Typed envelope decoding, including `new_state: null` removals and mismatched-ID rejection. |
| P1 | Authentication success is immediately presented as a live connection, before the event subscription result arrives. Send failures are discarded. | Explicit handshake phases; require matching successful subscription acknowledgement; propagate transport failures into reconnect handling. |
| P1 | Cancelled receive/retry tasks can restart or report status after replacement. Authentication failure keeps the receive loop alive. | One generation-checked receive/reconnect task; cancellation exits retry sleep; authentication/subscription failures terminate the session. |
| P1 | Opening views and refreshing repeatedly restart WebSocket connections. Changing settings leaves old cache and requests active. | Coalesce snapshot requests, reuse the loaded cache and socket, invalidate work on connection changes, clear old-server state, and ignore replaced delegates. |
| P1 | A slower REST snapshot can overwrite a newer realtime event or restore a removed entity. Reconnect misses changes while offline. | Merge snapshots using per-entity revisions and resynchronize after subscription/reconnection. |
| P1 | Keychain save deletes the previous token before attempting insertion; settings writes the URL first and silently saves on disappearance. | Update existing Keychain items in place; persist credentials before URL; explicit Save; report deletion/save failures. Test drafts separately and invalidate stale test results. |
| P1 | Optional numeric strings can overflow integer conversion; reversed Kelvin ranges trap on construction; malformed optional names/units fail the full snapshot. | Finite/exact numeric conversion, validated ranges, brightness clamping, and tolerant optional attribute decoding. |
| P2 | Any URL scheme is treated as configured; WebSocket drops reverse-proxy prefixes. | Shared HTTP(S) URL validation, reject query/fragment/embedded credentials, preserve prefixes consistently across REST and WebSocket. |
| P2 | Realtime events prematurely clear pending service calls, allowing duplicate submissions. Attribute-only changes still cause full polling delays. | Keep requests pending until completion, reject duplicates, recognize state or attribute changes, and discard superseded action results. |
| P2 | Cover Stop exists in action mapping but the view only renders the first action. | Render secondary actions and allow Stop to supersede a pending cover action. This verifies request/UI behavior, not a physical device stopping. |
| P2 | Brightness support depends on a current brightness value; advertised cover/climate capabilities are ignored. Unknown scene state disables Run. | Use supported color modes and feature flags; allow off-light controls; distinguish single-temperature from range-only climates; keep unknown scenes/scripts runnable. |
| P2 | Custom sliders lack keyboard/accessibility adjustment and a visible empty track. Disabled SwiftUI controls do not disable native input interception. | Arrow-key and accessibility adjustment, native enabled-state checks, background track, shared rounding/clamping, and preserve edits through gestures/service calls. |
| P2 | Loading/failed fetches resemble “no favorites”; missing saved entities disappear and cannot be removed. | Separate loading/failure/empty/missing states, cache warnings, explicit missing-selection removal, and refresh feedback in both management tabs. |
| P2 | Menu bar label uses 4pt text; values are nearly unreadable in native rendering. Disclosure is a mouse-only image/gesture. | 11pt monospaced digits, balanced symbols, tooltip/accessibility summary, explicit disclosure buttons and named device actions. |
| P2 | Favorites appear twice in management, search filters only the all-entities section, and domain choices are hardcoded. | Separate favorites from available entities; search/domain filtering applies to both; derive domain choices from actual entities; normalize persisted duplicate IDs. |

## Validation

- Baseline tests passed after allowing Xcode outside the execution sandbox. The initial sandboxed attempt failed to run Swift macro plugins; this was an environment limitation.
- Added protocol-envelope/handshake, configuration failure, lifecycle/concurrency, snapshot/event ordering, capability, numeric robustness, slider rounding, missing-selection and action-interruption regression tests.
- Final Debug test suite: **92 tests passed**. Source concurrency warnings from the baseline were removed. Xcode's “No AppIntents.framework dependency” metadata note is informational.
- Release build passed with signing disabled, and `git diff --check` passed.
- Native UI verification used a separate temporary app built from the project views, a fake REST client, virtual entities, an ephemeral defaults suite, and an in-memory token store. Verified light/climate disclosure, brightness accessibility adjustment (50% → 51%), temperature adjustment (24.5 → 25), arrow-key input, Chinese search, management tabs, long names, unavailable entities, and missing-selection presentation. A separate 680×480 dark settings preview checks the minimum window layout. No real service calls were issued by these preview interactions.

## Boundaries and remaining coverage

- Actual Home Assistant connectivity, token permissions, reverse-proxy deployments, sleep/wake behavior, and physical device outcomes require acceptance against the user's server. Unit tests and virtual UI interactions do not establish those outcomes.
- The protocol tests verify message shape and handshake logic. Long-duration network outages and transport-level reconnect timing have not been exercised against a real server. The socket has no periodic heartbeat; silent half-open connections remain a follow-up reliability concern.
- Climate range-only devices deliberately do not receive a single-temperature slider. Dual setpoints, fan/preset/humidity controls, generic service forms, OAuth and multiple instances remain outside the present feature set.
- Native UI checks do not constitute a full VoiceOver audit or automated drag/drop suite. Favorites and menu bar sensors retain drag-based ordering.
- Keychain failure behavior is tested through a fake; real Keychain permissions/prompts and signed distribution were not exercised. Local builds used `CODE_SIGNING_ALLOWED=NO`.
- Reviewed entitlements permit outgoing network connections and the app remains a menu bar utility (`LSUIElement`). No dependencies, deployment target or signing team were changed.

## Protocol references

- [Home Assistant WebSocket API](https://developers.home-assistant.io/docs/api/websocket/): event envelope, auth phases, subscription result.
- [Light entity](https://developers.home-assistant.io/docs/core/entity/light/): brightness capabilities from supported color modes.
- [Cover feature constants](https://github.com/home-assistant/core/blob/dev/homeassistant/components/cover/const.py): OPEN/CLOSE/STOP flags.
- [Climate feature constants](https://github.com/home-assistant/core/blob/dev/homeassistant/components/climate/const.py): target-temperature, range, turn-on/off flags.
