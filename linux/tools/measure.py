#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TICKS = os.sysconf("SC_CLK_TCK")
SECONDS = int(os.environ.get("SECONDS_PER_RUN", "45"))
ACTIVATE = """
for (const w of workspace.windowList()) {
    if (String(w.resourceClass).indexOf("plasmawindowed") >= 0) {
        workspace.activeWindow = w;
    }
}
"""
VARIANTS = [
    ("bar 10 s", 10, 3, False),
    ("bar 1 s", 1, 3, False),
    ("detail, RAM list 10 s", 3, 10, True),
    ("detail, RAM list 1 s", 3, 1, True),
]


def package(root, bar, detail, full):
    target = root / "data/plasma/plasmoids/local.kortex"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(REPO / "plasmoid", target)
    config = target / "contents/config/main.xml"
    text = config.read_text()
    text = re.sub(r'(name="barInterval" type="Int">\s*<default>)\d+', rf"\g<1>{bar}", text)
    text = re.sub(r'(name="detailInterval" type="Int">\s*<default>)\d+', rf"\g<1>{detail}", text)
    text = re.sub(r'(name="tab" type="String">\s*<default>)\w+', r"\g<1>ram", text)
    config.write_text(text)
    if full:
        main = target / "contents/ui/main.qml"
        text = main.read_text().replace(
            "preferredRepresentation: compactRepresentation", "preferredRepresentation: fullRepresentation"
        )
        main.write_text(text.replace("    Timer {", "    Component.onCompleted: expanded = true\n\n    Timer {", 1))


def ticks(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])


def proportional(pid):
    for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
        if line.startswith("Pss:"):
            return int(line.split()[1]) / 1024


def bus(*args):
    return subprocess.run(["busctl", "--user", "call", "org.kde.KWin", *args], capture_output=True, text=True).stdout


def activate(script):
    bus("/Scripting", "org.kde.kwin.Scripting", "unloadScript", "s", "mm-measure")
    reply = bus("/Scripting", "org.kde.kwin.Scripting", "loadScript", "ss", str(script), "mm-measure").split()
    bus(f"/Scripting/Script{reply[1]}", "org.kde.kwin.Script", "run")
    time.sleep(0.3)
    bus("/Scripting", "org.kde.kwin.Scripting", "unloadScript", "s", "mm-measure")


def service():
    found = subprocess.run(["pgrep", "-x", "kortex-service"], capture_output=True, text=True).stdout.split()
    if found:
        return found[0]
    subprocess.Popen([REPO / "service/target/release/kortex-service"])
    time.sleep(0.5)
    return service()


def run(root, script, label, bar, detail, full):
    package(root, bar, detail, full)
    (root / "config/plasmawindowed-appletsrc").unlink(missing_ok=True)
    env = dict(
        os.environ,
        XDG_DATA_DIRS=f"{root / 'data'}:/usr/local/share:/usr/share",
        XDG_CONFIG_HOME=str(root / "config"),
        XDG_CACHE_HOME=str(root / "cache"),
    )
    ui = subprocess.Popen(
        ["plasmawindowed", "local.kortex"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    time.sleep(6)
    activate(script)
    time.sleep(4)
    pid = service()
    ui_start, service_start, start = ticks(ui.pid), ticks(pid), time.time()
    time.sleep(SECONDS)
    elapsed = time.time() - start
    ui_cpu = (ticks(ui.pid) - ui_start) / TICKS / elapsed * 100
    service_cpu = (ticks(pid) - service_start) / TICKS / elapsed * 100
    print(
        f"{label:24s} plasmoid {ui_cpu:5.2f}%  service {service_cpu:5.3f}%  "
        f"plasmoid PSS {proportional(ui.pid):6.1f} MB  service PSS {proportional(pid):5.1f} MB",
        flush=True,
    )
    ui.terminate()
    ui.wait()
    return ui_cpu + service_cpu


def main():
    with tempfile.TemporaryDirectory(prefix="kortex-measure-") as temporary:
        root = Path(temporary)
        (root / "config").mkdir()
        for name in ("kdeglobals", "plasmarc"):
            source = Path.home() / ".config" / name
            if source.exists():
                (root / "config" / name).symlink_to(source)
        script = root / "activate.js"
        script.write_text(ACTIVATE)
        total = {label: run(root, script, label, bar, detail, full) for label, bar, detail, full in VARIANTS}
    per_bar = (total["bar 1 s"] - total["bar 10 s"]) / 0.9
    per_list = (total["detail, RAM list 1 s"] - total["detail, RAM list 10 s"]) / 0.9
    fixed = total["detail, RAM list 10 s"] - per_list / 10
    print(f"\nbar: {per_bar:.2f}% at 1 s  detail: {fixed:.2f}% fixed + {per_list:.2f}% at 1 s")


if __name__ == "__main__":
    sys.exit(main())
