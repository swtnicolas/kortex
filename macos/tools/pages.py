import re
import sys
from bisect import bisect_right
from collections import defaultdict

PAGE = 16384
MB = 1048576
UNITS = {"K": 1024, "M": MB, "G": 1024 * MB}
REGION = re.compile(r"^(Malloc[^\[]*?)\s+([0-9a-f]+)-([0-9a-f]+)\s+\[\s*[\d.]+[KMG]\s+[\d.]+[KMG]\s+([\d.]+[KMG])")
OBJECT = re.compile(r"^0x([0-9a-f]+): (.*?) \((\d+) bytes\)")


def regions(path):
    found = []
    for line in open(path, errors="replace"):
        match = REGION.match(line)
        if match:
            dirty = float(match.group(4)[:-1]) * UNITS[match.group(4)[-1]]
            kind = re.sub(r"\s+", " ", match.group(1)).strip()
            found.append((int(match.group(2), 16), int(match.group(3), 16), kind, dirty))
    return sorted(found)


def pages(path):
    used = defaultdict(lambda: [0, []])
    for line in open(path, errors="replace"):
        match = OBJECT.match(line)
        if not match:
            continue
        address, name, size = int(match.group(1), 16), re.sub(r"\s{2,}", " ", match.group(2)), int(match.group(3))
        end = address + size
        while address < end:
            page = address // PAGE
            step = min(end, (page + 1) * PAGE) - address
            used[page][0] += step
            used[page][1].append(name)
            address += step
    return used


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: pages.py <label.regions> <label.addresses> [limit]")
    spans = regions(sys.argv[1])
    used = pages(sys.argv[2])
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    starts = [span[0] for span in spans]
    per_span = defaultdict(lambda: [0, 0, 0])
    pinned = defaultdict(lambda: [0.0, 0])
    for page, (live, names) in used.items():
        index = bisect_right(starts, page * PAGE) - 1
        if index < 0 or page * PAGE >= spans[index][1]:
            continue
        row = per_span[index]
        row[0] += 1
        row[1] += live
        row[2] += PAGE - live
        if live < PAGE / 2:
            for name in names:
                pinned[name][0] += (PAGE - live) / len(names)
                pinned[name][1] += 1
    totals = defaultdict(lambda: [0.0, 0.0, 0, 0, 0.0])
    for index, (_, _, kind, dirty) in enumerate(spans):
        count, live, holes = per_span.get(index, (0, 0, 0))
        row = totals[kind]
        row[0] += dirty
        row[1] += min(dirty, count * PAGE)
        row[2] += live
        row[3] += holes
        row[4] += max(0.0, dirty - count * PAGE)
    print(f"{'region':22} {'dirty':>7} {'in use':>7} {'live':>7} {'holes':>7} {'unused':>7}")
    for kind, (dirty, busy, live, holes, unused) in sorted(totals.items(), key=lambda item: -item[1][0]):
        print(f"{kind:22} {dirty / MB:6.1f}M {busy / MB:6.1f}M {live / MB:6.1f}M "
              f"{holes / MB:6.1f}M {unused / MB:6.1f}M")
    print("holes in pages under half full, split among the objects that keep them:")
    for name, (free, count) in sorted(pinned.items(), key=lambda item: -item[1][0])[:limit]:
        print(f"{free / MB:7.2f}M {count:6d}  {name[:90]}")


main()
