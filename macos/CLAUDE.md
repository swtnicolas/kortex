# kortex

Lightweight macOS menu bar system monitor (RAM, CPU, GPU, temperature, battery).

The bundle id is `local.kortex`. Its Dock icon is a setting, shown by default; the top menu bar item is text only, no icon.

## Layout

- `Sources/Kortex/` — Swift, pure AppKit, no SwiftUI. `Readers/` holds one type per data source, `Detail/` the detail panel and its views.
- `Sources/SMCKit/` — the SMC connection both executables share: key lookup, typed reads and writes, and the fan keys.
- `Sources/KortexFans/` — the setuid-root helper that writes the fan mode and target.
- `Tests/KortexTests/` — Swift Testing unit tests; `@testable import Kortex` reaches the executable target.
- `tools/` — measurement helpers: `ax.swift` drives the running app through Accessibility, `usage.swift` reads its CPU, including the child processes it has reaped, and its footprint with `proc_pid_rusage`, `memdiff.py` compares `heap`, `footprint` or `malloc_history` dumps, `pages.py` lays the live heap objects over 16 KB pages to split dirty malloc memory into live objects, holes and pages with nothing live.
- `Resources/Info.plist` — bundle manifest, copied into the app at build time.
- `assets/icon/` — `AppIcon.icns` and `AppIcon.iconset/`, rendered from the repo's master `assets/icon/AppIcon.svg`.

The decisions for both apps live in the repo's `docs/decisiones.md` (Spanish); every newly approved decision goes there.

## Build

Build on the Mac that runs the app. Gatekeeper blocks a downloaded build that Apple has not notarized, while a locally built, ad-hoc signed copy carries no quarantine flag, so never ship a prebuilt bundle or a release workflow. The version is `CFBundleShortVersionString` in `Resources/Info.plist`; macOS has no tag.

`scripts/build.sh` compiles in release and assembles `build/Kortex.app` and `build/KortexFans`, both ad-hoc signed. `scripts/install.sh` also replaces `~/Applications/Kortex.app` and launches it. SwiftPM on its own produces a bare binary, and the menu bar item and the Dock icon need the bundle, so run the scripts rather than `swift run`.

`scripts/install-fans.sh` installs the fan helper into `/Library/PrivilegedHelperTools/local.kortex.fans`, setuid root (owner, group and mode in the repo's `docs/decisiones.md`). It is the only step that asks for a password, and the build is reproducible, so `install.sh` compares both files and only tells you to run it when they differ.

`scripts/test.sh` runs `swift test`. The Command Line Tools keep the Swift Testing macros in `usr/lib/swift/host/plugins/testing`, a folder `swift test` does not search, so the script passes it with `-plugin-path`; a bare `swift test` fails with `plugin for module 'TestingMacros' not found`.

## Measure

`scripts/measure.sh` quits the running Kortex, opens `build/Kortex.app` (or `APP`) through LaunchServices on the RAM tab (or `TAB`), opens the detail for `OPEN` seconds (5 by default) and closes it, `CYCLES` times (5 by default), and prints the footprint, the lifetime peak and the highest footprint seen while the detail is open. At the end it relaunches `~/Applications/Kortex.app`. `IDLE=60` adds a closed minute with its CPU and mean footprint, `SNAPSHOTS=1` saves dumps of the first cycle and of that minute to `build/measure/`, and `KEY=VALUE` arguments reach the app's environment. `scripts/snapshot.sh <label>` dumps the running app on demand: `footprint`, the `vmmap` summary and regions, the `heap` summary and addresses, and with `STACKS=1` also `malloc_history`, which needs the app launched with `MallocStackLogging=1`. The helpers compile into `build/tools/`, and `ax` needs the Accessibility permission of the process that runs it.

Compare builds back to back on the same display setup. Every connected display adds a menu bar to draw the item on, which moves both the footprint and the idle CPU, a long-running instance also carries the status bar windows that monitor reconnections leave behind (see Gotchas), and a single run still varies by about 1 MB.

`Info.plist` picks the allocator through `LSEnvironment`. `MallocSpaceEfficient=1` with `MallocMaxMagazines=1` is a single-magazine allocator that marks empty pages reusable, so they leave the footprint; macOS 27's default, xzone malloc, segregates blocks by type and core and keeps freed pages dirty. `LIBDISPATCH_CONTINUATION_ALLOCATOR=0` drops libdispatch's per-core continuation heap. The costs are in the repo's `docs/decisiones.md`. LaunchServices applies `LSEnvironment` only to apps it opens, so running the binary directly measures the default allocator. `malloc_zone_pressure_relief` returns 0 bytes with either.

What stays after the detail closes is the caches filled on its first opening and holes between live objects; `pages.py` splits a snapshot into those parts. `ax` presses the status item through Accessibility, and every query leaves accessibility caches in the app, about 0.6 MB after a few cycles, that a click never creates: read stacks that end in `NSAccessibility` or `_AXXMIG` as the tool's own cost.

## Gotchas

Never set `NSStatusItem.isVisible` to false. macOS persists the hidden state in the app's own defaults under `NSStatusItem VisibleCC Item-0`, so every later launch starts hidden even after a rebuild, and recovering needs `defaults delete local.kortex`.

One SMC key read costs more than every other sensor in the app put together (measured in the repo's `docs/decisiones.md`). Anything new that reads temperatures budgets for that.

`IOReport.swift` binds `/usr/lib/libIOReport.dylib` by hand: Apple ships no headers for it, so every signature there is a guess that has to match. `IOReportStateGetCount` returns a negative count for channels that carry a single value, and a Swift range built from it traps. `IOReportCreateSubscription` returns a retained CF object that `deinit` releases; the GPU tab subscribes every time it opens.

`SelfUsage` takes the footer's closed CPU only from spans in which the detail stayed closed throughout and no child process ended. `top` and `ps` reach `RUSAGE_CHILDREN` when they are reaped, which can be after the panel closes, and one `top` is a large share of a 3-s span. A process spawned while the detail is closed would keep that reading from ever updating.

macOS 27 hosts status items in `MenuBarAgent` through FrontBoard scenes: the item's own `NSStatusBarWindow` plus a variant window for each other display, all in `NSApp.windows`, the variants with `screen == nil`. Each reconnection of a monitor brings new variant scenes, `com.apple.appkit.status-items:<uuid>-Variant[N]` with N counting up for the life of the process. When the cable or dock that carries two external monitors comes out, AppKit uninstalls the variants but discards only one scene, and the other stays alive with its window and its Core Animation backing; nothing tells it apart from a live variant but the count. Recreating the status item does not free it: `removeStatusItem` keeps one of the removed item's windows alive too, and `close()` releases neither. Powering one monitor off and on leaves none, and neither does a `CGVirtualDisplay`. `Created scene` and `Discarded scene` are Info messages that `log show` keeps only for a few minutes, so watch them with `log stream`.

`Info.plist` sets `LSUIElement`, so the app launches as an accessory and `AppDelegate.applyDockIcon()` makes it regular when the Dock icon setting is on. Without `LSUIElement`, a hidden icon flashes in the Dock at every launch.

The detail is a borderless, non-activating `DetailPanel`. Do not move it to `NSPopover`: on macOS 27 every popover resize that comes with new content allocates graphics memory, and a closed popover leaves memory behind that grows with each opening (the repo's `docs/decisiones.md`, Stack).

The panel becomes key without activating the app, so the views' tracking areas use `.activeAlways`. It closes on Esc, on `resignKey` and through a global mouse monitor. On macOS 27 the menu bar belongs to another process, so presses on Kortex's own status item also reach that monitor; `pressesStatusItem` leaves those to the item's action, which toggles the panel.

`NSStatusBarButton.highlight(_:)` draws nothing on macOS 27, so `MenuBarView` draws the capsule that marks the detail as open.

`cgColor` of a dynamic `NSColor` resolves with the current drawing appearance, and inside `viewDidChangeEffectiveAppearance` that is still the previous one. Layer colors are set in `updateLayer()`, which AppKit calls with the new appearance on every change; views that paint in `draw(_:)` already redraw on their own.

Every window draws in sRGB, the color space of every color in the app: `DetailPanel` sets its own, and `AppDelegate.pinColorSpaces` sets the status bar windows' when the item is created and on every screen change, which is when it reaches the variant windows AppKit adds after launch. Core Graphics caches about 15 ColorSync transforms, keyed by the pair of color spaces. A display profile with parametric curves, like the v4 profile macOS generates for some external monitors, makes each transform reserve large tables (sizes in the repo's `docs/decisiones.md`). Every reconnection gives the monitor a new color space whose gamut AppKit computes (`_NXDefaultWindowDepthLimit`) when a window awakes or changes color space there, so each reconnection adds a transform or two whatever the app does: pinning only at creation leaves AppKit to recompute it for every window on each screen change, and turning off the dynamic depth limit makes `setDepthLimit:` compute it instead.

The detail uses no AppKit control and no SF Symbol. `NSTextField` keeps the size of every distinct string it measures in a cache with no limit, thousands of strings per hour with the detail open, while `NSAttributedString.size()` and `draw` cache nothing; SF Symbols load the CoreUI and CoreSVG catalogs, which stay. `Label`, `DetailRowView`, `HoverButton`, `SegmentedView`, `ToggleView` and `Icon` draw everything, and each declares its accessibility role so VoiceOver and `tools/ax.swift` still find it.

The detail has no editable text field. An `NSSearchField` in the panel loads the text input system, about 3 MB in this app that stays after the panel closes even if the field never takes focus. The list search is the drawn `SearchView`, fed by `DetailPanel.keyDown`.

Core Animation already creates the system Metal device to draw the status item, so the `MTLCreateSystemDefaultDevice` in `GraphicsReader` costs nothing extra.

`DetailController` creates a tab's pane the first time the tab is shown and keeps it until the panel closes. Readings only reach the visible pane, and `apply` hands the latest one to a pane as it becomes visible; a new pane goes through `pane(for:)`.

`ProcessListView` keeps its `ProcessRowView`s across refreshes, and `RowsView` places them by frame with the height from `intrinsicContentSize`. Anything added to a list reports its height there.

The SMC answers `kIOReturnNotPrivileged` to a write from anyone but root, so fan control lives in `KortexFans`. On this chip the manual mode key is `F{n}md` in lowercase, and neither `F{n}Md` nor the `Ftst` of earlier Apple Silicon exists.

`FanControl` writes the level byte on every reading, not only when it changes: that write is also the helper's heartbeat, and the helper hands the fans back to macOS after a silence. The helper drops its effective uid to the user once the SMC is open and raises it only around a write, which is what lets `SelfReader` add its footprint to the app's own with `proc_pid_rusage`.

A pointer marked as customized in Accessibility (`cursorIsCustomized` under `com.apple.universalaccess`) makes every `[NSCursor set]` rebuild the cursor image in software, shadow blur included. AppKit calls it on each mouse-moved event that reaches the status item's window, so the app's own CPU reading climbs to about a third of a core while the pointer crosses the menu bar and falls back to 0.3% as soon as it leaves. Any app with a status item pays it. Read that default before chasing the app's own CPU.

## Constraints

Resource consumption, RAM first, is the top priority: the machine is meant to run local LLMs in the same unified memory. The budget and the costs measured against it live in the repo's `docs/decisiones.md`; any change that touches a reader or a redraw is checked against them before it is done.

The app must never require a permission prompt. Process lists come from the system's own setuid `top` and `ps`, and the single admin password is `scripts/install-fans.sh` (Permisos in the repo's `docs/decisiones.md`).
