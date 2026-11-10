# kortex

Lightweight system monitor for KDE Plasma 6 on Wayland (RAM, CPU, GPU, temperature). A plasmoid shows the readings as text in the panel and a detail popup on click; a Rust user service reads the data and answers over D-Bus.

The plasmoid id is `local.kortex`, the D-Bus name, interface and path are `local.Kortex` and `/local/Kortex`.

## Layout

- `service/` — Rust, edition 2024, no crates. `bus.rs` calls sd-bus from libsystemd through FFI, `nvml.rs` loads `libnvidia-ml.so.1` with `dlopen`, `json.rs` writes the replies, and `memory.rs`, `processor.rs`, `temperature.rs`, `processes.rs`, `usage.rs` read `/proc`, `/sys` and NVML. `kortex.service` is the systemd user unit.
- `plasmoid/` — KPackage applet in QML. `main.qml` holds the state, the timers and every D-Bus call; `CompactView.qml` is the panel text, `DetailView.qml` the popup with one pane per tab, `ProcessList.qml` the app lists, `Footer.qml` the service's own usage.
- `scripts/` — `install.sh`, `uninstall.sh`, `test.sh`, `package.sh`.
- `tools/measure.py` — CPU and PSS of the plasmoid and the service per update interval.

The icon is the repo's `assets/icon/AppIcon.svg`, installed as `local.kortex` in the hicolor theme: `install.sh` takes it from `assets/` beside its own folder in the package, or from the repo root. The decisions for both apps live in the repo's `docs/decisiones.md` (Spanish); every newly approved decision goes there.

## D-Bus API

The plasmoid pulls; the service has no timer of its own. `Bar` and `List` return one JSON string.

- `Bar(s tab)` — panel totals and the service's own usage. A non-empty `tab` means a popup is open and adds that tab's totals under `detail`. Every reply also goes out as the signal `Reading(s)`.
- `List(s tab, s query, u limit)` — `ram`, `cpu`, `gpu`: app groups with their processes; `temp`: zones and fans.
- `Terminate(s targets, b force) → u` — `targets` is `pid:starttime,…`; the service checks start time, owner and unit before each signal.
- `Close()` — a popup closed; the service releases the process state. A `Bar` with an empty `tab` releases it too, but only 30 s or more after the last call for an open popup: an empty `tab` may come from another plasmoid while one popup is open.

Several plasmoids in one session share readings through `Reading`, and the service exits when nobody calls; the rules are in the repo's `docs/decisiones.md` (Consumo). D-Bus activation starts it again through `SystemdService=kortex.service`.

## Build and install

`scripts/install.sh` builds in release and installs under the user's home without sudo (layout in the repo's `docs/decisiones.md`). After an upgrade plasmashell keeps the old QML until `systemctl --user restart plasma-plasmashell`. `scripts/test.sh` runs `cargo test` and `cargo clippy -D warnings`.

`scripts/package.sh` writes `dist/kortex-install.sh`, one self-extracting file for sharing without the sources: a tar of the release binary, the unit, the icon, the plasmoid and both scripts, laid out as in `linux/`. `install.sh` skips the build when `service/Cargo.toml` is absent, so the packaged copy installs the bundled binary. `bash kortex-install.sh` installs and `--uninstall` removes. The binary needs x86-64, glibc 2.34 and libsystemd; NVML is optional.

Pushing a `linux-v<version>` tag runs the repo root's `.github/workflows/release.yml` inside `linux/`: tests, `package.sh`, a check that fails when the binary needs a glibc newer than 2.34, and a GitHub release with `kortex-install.sh` attached. The repository is public, at `swtnicolas/kortex`.

To try the plasmoid without installing it, link `plasmoid/` as `<dir>/plasma/plasmoids/local.kortex`, run the service binary from `service/target/release/`, and start `plasmawindowed local.kortex` with `XDG_DATA_DIRS=<dir>:/usr/share` and `XDG_DATA_HOME` pointing at an empty folder, since an installed copy in `~/.local/share` wins over `XDG_DATA_DIRS`. `plasmawindowed` writes `plasmawindowed-appletsrc` into `XDG_CONFIG_HOME`; point that at a scratch folder holding links to `kdeglobals` and `plasmarc`. Its window keeps its own size, so the detail's fixed height only shows in the real panel.

To open the detail in the real panel from a script, give the widget a global shortcut through `evaluateScript` on `org.kde.plasmashell` (`widget.globalShortcut = "…"`), call `invokeShortcut "activate widget <id>"` on `/component/plasmashell` of `org.kde.kglobalaccel`, and clear the shortcut afterwards.

## Measure

`tools/measure.py` runs patched copies of the plasmoid in `plasmawindowed` with the bar at 1 and 10 s and the RAM list at 1 and 10 s, raises the window through a KWin script so it keeps rendering, and prints the CPU and PSS of both processes plus the per-interval costs that `SettingsPane.qml` shows. The plasmoid's real home is plasmashell, so its numbers are a proxy. Runs on a desktop in use vary; alternate the variants and repeat before trusting a difference.

## Gotchas

`nvmlInit_v2` loads `libcuda.so` and dirties a large anonymous region next to it (size in the repo's `docs/decisiones.md`), and `nvmlShutdown` frees none of it. It is most of the service's PSS, and Plasma's own GPU sensors pay the same through `nvidia-smi dmon`.

`/proc/PID/smaps_rollup` is readable only for the user's own processes, so per-process memory is `resident − shared` from `statm`, which is `RssAnon`.

Per-process CPU needs two walks of `/proc`. A walk closer than 0.2 s to the previous one keeps the earlier rates, so switching tabs never zeroes the CPU list; the first walk reports `baseline` and the plasmoid asks again after 1 s.

Apps launched by Plasma are children of `systemd --user`, and one app can span two units; the grouping rule is in the repo's `docs/decisiones.md` (Listas de apps).

QML: QtQuick's `Palette` type shadows a local `Palette.qml`; `Item` already owns `data` and `palette`; `escape` is a JS global and cannot be a method name. Signal handlers must qualify properties (`root.expanded`), or Qt warns about injected parameters.

`org.kde.plasma.workspace.dbus`: `asyncCall` resolves with the pending reply, and a string return arrives wrapped as `{ value: "…" }`. `SignalWatcher` calls a function named `dbus<Member>` and only matches signals from the service name it is given; it keeps matching after the service exits and is activated again.

Plasma 6 stores each popup's size as `popupWidth`/`popupHeight` in the applet's config on first open and reuses it. `DetailView.qml` pins minimum, preferred and maximum to one size, so the stored size always matches it.

Labels and buttons inside the detail inherit their font from the `QQC2.Control` that wraps it; set sizes there, not per label.

`pkill -f plasmawindowed` also matches the shell that runs it; use `pkill -x`.

The Temp tab lists `fan*_input` from any hwmon device and the GPU fans from NVML.

## Constraints

Resource consumption, RAM first, is the top priority. The reference and the costs measured against it live in the repo's `docs/decisiones.md`; any change that touches a reader, a timer or a binding that updates every reading is measured before it is done.

The app never requires a permission prompt or root (Permisos in the repo's `docs/decisiones.md`).
