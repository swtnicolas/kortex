import re
import sys
from collections import defaultdict

UNITS = {"B": 1 / 1024, "KB": 1, "MB": 1024, "GB": 1024 * 1024}
ALLOCATOR = re.compile(
    r"malloc|calloc|realloc|_os_alloc|operator new|swift_allocObject|swift_slowAlloc|_objc_rootAlloc"
    r"|class_createInstance|_CFRuntimeCreateInstance|objc_alloc|allocWithZone|alloc_instrumented"
    r"|vm_allocate|mmap|posix_memalign|aligned_alloc|swift_allocBox|_malloc_type|CFAllocatorAllocate"
)
FRAME = re.compile(r"0x[0-9a-f]+ \(([^)]+)\) (.*?)\s*$")


def heap(path):
    rows = defaultdict(lambda: [0, 0])
    started = False
    for line in open(path, errors="replace"):
        if re.match(r"\s*COUNT\s+BYTES\s+AVG\s+CLASS_NAME", line):
            started = True
            continue
        match = started and re.match(r"\s*(\d+)\s+(\d+)\s+[\d.]+\s+(.*?)\s*$", line)
        if not match:
            continue
        key = re.sub(r"\s{2,}", " ", match.group(3))
        rows[key][0] += int(match.group(1))
        rows[key][1] += int(match.group(2)) / 1024
    return rows


def footprint(path):
    rows = defaultdict(lambda: [0, 0])
    pattern = r"\s*([\d.]+) (B|KB|MB|GB)\s+[\d.]+ (?:B|KB|MB|GB)\s+([\d.]+) (B|KB|MB|GB)\s+\d+\s+(.+?)\s*$"
    for line in open(path, errors="replace"):
        match = re.match(pattern, line)
        if match and match.group(5) != "TOTAL":
            rows[match.group(5)][0] += float(match.group(3)) * UNITS[match.group(4)]
            rows[match.group(5)][1] += float(match.group(1)) * UNITS[match.group(2)]
    return rows


def stacks(path):
    rows = defaultdict(lambda: [0, 0])
    for line in open(path, errors="replace"):
        match = re.match(r"^(\d+) calls? for (\d+) bytes: (.*)$", line)
        if not match or int(match.group(2)) >= 16 * 1048576:
            continue
        frames = [m.groups() for m in (FRAME.match(p.strip()) for p in match.group(3).split(" | ")) if m]
        if any("vm_allocate" in name or "mmap" in name for _, name in frames[-4:]):
            continue
        own = [name for module, name in frames if module == "local.kortex"]
        inner = [(module, name) for module, name in frames if not ALLOCATOR.search(name)]
        key = own[-1][:90] if own else (f"{inner[-1][0]}: {inner[-1][1][:90]}" if inner else "?")
        rows[key][0] += int(match.group(1))
        rows[key][1] += int(match.group(2)) / 1024
    return rows


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("heap", "footprint", "stacks"):
        sys.exit("usage: memdiff.py heap|footprint|stacks <before> <after> [limit]")
    reader = {"heap": heap, "footprint": footprint, "stacks": stacks}[sys.argv[1]]
    before, after = reader(sys.argv[2]), reader(sys.argv[3])
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 30
    unit = "reclaimable KB" if sys.argv[1] == "footprint" else "count"
    deltas = sorted(
        ((after[k][1] - before[k][1], after[k][0] - before[k][0], k) for k in set(before) | set(after)),
        reverse=True,
    )
    print(f"total {sum(d[0] for d in deltas) / 1024:+.2f} MB")
    for size, other, key in deltas[:limit]:
        print(f"{size / 1024:+8.2f} MB  {other:+10.0f} {unit}  {key}")


main()
