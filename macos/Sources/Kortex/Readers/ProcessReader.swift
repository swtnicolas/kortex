import Foundation

struct ProcessTarget: Sendable {
    let pid: Int32
    let started: UInt64
}

struct ProcessEntry: Sendable {
    let pid: Int32
    let name: String
    let value: Double
    let target: ProcessTarget?
}

struct ProcessGroup: Sendable {
    let pid: Int32
    let name: String
    let value: Double
    let children: [ProcessEntry]
    let targets: [ProcessTarget]
}

enum ProcessReader {
    private static let processorSpan = 0.5

    private struct Snapshot: Sendable {
        struct Entry: Sendable {
            let parent: Int32
            let owner: UInt32
            let time: Double
            let name: String
        }

        var entries: [Int32: Entry] = [:]
        var clock = 0.0
    }

    static func memory() async -> [ProcessGroup] {
        await Task.detached(priority: .utility) {
            group(sizes(), tree())
        }.value
    }

    static func processor() async -> [ProcessGroup] {
        let first = await Task.detached(priority: .utility) { tree() }.value
        try? await Task.sleep(for: .seconds(processorSpan))
        let second = await Task.detached(priority: .utility) { tree() }.value

        let span = second.clock - first.clock
        guard span > 0 else { return [] }
        var usage: [Int32: Double] = [:]
        for (pid, entry) in second.entries {
            let before = first.entries[pid]?.time ?? entry.time
            usage[pid] = max(0, (entry.time - before) / span * 100)
        }
        return group(usage, second)
    }

    static func energy() async -> [ProcessGroup] {
        let first = await Task.detached(priority: .utility) { joules() }.value
        try? await Task.sleep(for: .seconds(processorSpan))
        let second = await Task.detached(priority: .utility) { joules() }.value
        let snapshot = await Task.detached(priority: .utility) { tree() }.value

        let span = second.clock - first.clock
        guard span > 0 else { return [] }
        var watts: [Int32: Double] = [:]
        for (pid, energy) in second.values {
            guard let before = first.values[pid] else { continue }
            let value = (energy - before) / 1e9 / span
            if value > 0 { watts[pid] = value }
        }
        return group(watts, snapshot)
    }

    static func groups(of values: [Int32: Double]) async -> [ProcessGroup] {
        let snapshot = await Task.detached(priority: .utility) { tree() }.value
        return group(values, snapshot)
    }

    static func signal(_ targets: [ProcessTarget], force: Bool) {
        for target in targets where started(target.pid) == target.started {
            kill(target.pid, force ? SIGKILL : SIGTERM)
        }
    }

    private static func started(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    private static func joules() -> (values: [Int32: Double], clock: Double) {
        var pids = [Int32](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                                  Int32(pids.count * MemoryLayout<Int32>.size))
        let count = max(0, Int(bytes) / MemoryLayout<Int32>.size)
        var values: [Int32: Double] = [:]
        for index in 0..<count where pids[index] > 0 {
            var usage = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pids[index], RUSAGE_INFO_V6, $0)
                }
            }
            guard result == 0, usage.ri_energy_nj > 0 else { continue }
            values[pids[index]] = Double(usage.ri_energy_nj)
        }
        return (values, Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9)
    }

    private static func sizes() -> [Int32: Double] {
        let output = run("/usr/bin/top", ["-l", "1", "-o", "mem", "-stats", "pid,mem"])
        var sizes: [Int32: Double] = [:]
        var rest = output[...]
        var started = false
        while let line = nextLine(&rest) {
            guard started else {
                started = line.hasPrefix("PID")
                continue
            }
            var fields = line
            guard let pid = Int32(field(&fields)), let bytes = size(field(&fields)) else { continue }
            sizes[pid] = bytes
        }
        return sizes
    }

    private static func tree() -> Snapshot {
        let output = run("/bin/ps", ["-eo", "pid=,ppid=,uid=,cputime=,comm="])
        var snapshot = Snapshot()
        snapshot.clock = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9
        snapshot.entries.reserveCapacity(1024)
        var rest = output[...]
        while let line = nextLine(&rest) {
            var fields = line
            guard let pid = Int32(field(&fields)), let parent = Int32(field(&fields)),
                  let owner = UInt32(field(&fields)) else { continue }
            let time = seconds(field(&fields))
            let path = fields.drop { $0 == " " }
            guard !path.isEmpty else { continue }
            let name = path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? path
            snapshot.entries[pid] = Snapshot.Entry(parent: parent, owner: owner, time: time, name: String(name))
        }
        return snapshot
    }

    private static func group(_ values: [Int32: Double], _ snapshot: Snapshot) -> [ProcessGroup] {
        let user = getuid()
        var targets: [Int32: [ProcessTarget]] = [:]
        var targetOf: [Int32: ProcessTarget] = [:]
        for (pid, entry) in snapshot.entries where entry.owner == user {
            guard let started = started(pid) else { continue }
            let target = ProcessTarget(pid: pid, started: started)
            targetOf[pid] = target
            targets[root(of: pid, in: snapshot), default: []].append(target)
        }
        var children: [Int32: [ProcessEntry]] = [:]
        for (pid, value) in values {
            let name = snapshot.entries[pid]?.name ?? "\(pid)"
            children[root(of: pid, in: snapshot), default: []].append(
                ProcessEntry(pid: pid, name: name, value: value, target: targetOf[pid])
            )
        }
        return children.map { owner, entries in
            ProcessGroup(
                pid: owner,
                name: snapshot.entries[owner]?.name ?? entries.first?.name ?? "\(owner)",
                value: entries.reduce(0) { $0 + $1.value },
                children: entries.sorted { before($0.value, $0.name, $0.pid, $1.value, $1.name, $1.pid) },
                targets: targetOf[owner] == nil ? [] : targets[owner] ?? []
            )
        }
        .sorted { before($0.value, $0.name, $0.pid, $1.value, $1.name, $1.pid) }
    }

    private static func before(_ leftValue: Double, _ leftName: String, _ leftPid: Int32,
                               _ rightValue: Double, _ rightName: String, _ rightPid: Int32) -> Bool {
        if leftValue != rightValue { return leftValue > rightValue }
        if leftName != rightName { return leftName.localizedStandardCompare(rightName) == .orderedAscending }
        return leftPid < rightPid
    }

    private static func root(of pid: Int32, in snapshot: Snapshot) -> Int32 {
        var current = pid
        for _ in 0..<32 {
            guard let parent = snapshot.entries[current]?.parent, parent > 1 else { return current }
            current = parent
        }
        return current
    }

    private static func nextLine(_ text: inout Substring) -> Substring? {
        guard !text.isEmpty else { return nil }
        let end = text.firstIndex(of: "\n") ?? text.endIndex
        let line = text[..<end]
        text = text[end...].dropFirst()
        return line
    }

    private static func field(_ text: inout Substring) -> Substring {
        let start = text.drop { $0 == " " }
        let end = start.firstIndex(of: " ") ?? start.endIndex
        text = start[end...]
        return start[..<end]
    }

    private static func seconds(_ field: Substring) -> Double {
        var days = 0.0
        var rest = field
        if let dash = rest.firstIndex(of: "-") {
            days = Double(rest[..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        var value = 0.0
        while !rest.isEmpty {
            let colon = rest.firstIndex(of: ":") ?? rest.endIndex
            value = value * 60 + (Double(rest[..<colon]) ?? 0)
            rest = rest[colon...].dropFirst()
        }
        return days * 86400 + value
    }

    private static func size(_ field: Substring) -> Double? {
        let digits = field.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return nil }
        switch field.dropFirst(digits.count).first {
        case "K": return value * 1024
        case "M": return value * 1024 * 1024
        case "G": return value * 1024 * 1024 * 1024
        case "T": return value * 1024 * 1024 * 1024 * 1024
        default: return value
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
