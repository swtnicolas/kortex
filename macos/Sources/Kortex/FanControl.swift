import Foundation

@MainActor
final class FanControl {
    enum Mode: String {
        case automatic, curve
    }

    enum Problem: Equatable {
        case missing
        case failed(Int32)
    }

    static let scale: ClosedRange<Double> = 40...100
    static let shortestSpan = 5.0
    static let standardRange: ClosedRange<Double> = 60...90
    static let helperPath = "/Library/PrivilegedHelperTools/local.kortex.fans"

    private static let hysteresis = 2.0
    private static let modeKey = "fanMode"
    private static let fromKey = "fanFrom"
    private static let toKey = "fanTo"

    private var process: Process?
    private var input: FileHandle?

    private(set) var level: Int?
    private(set) var problem: Problem?

    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: FanControl.modeKey)
            problem = nil
            if mode == .automatic { release() }
        }
    }

    var range: ClosedRange<Double> {
        didSet {
            guard range != oldValue else { return }
            UserDefaults.standard.set(range.lowerBound, forKey: FanControl.fromKey)
            UserDefaults.standard.set(range.upperBound, forKey: FanControl.toKey)
        }
    }

    var installed: Bool {
        access(FanControl.helperPath, X_OK) == 0
    }

    var helper: pid_t? {
        process?.processIdentifier
    }

    init() {
        let defaults = UserDefaults.standard
        mode = defaults.string(forKey: FanControl.modeKey).flatMap(Mode.init(rawValue:)) ?? .automatic
        let from = defaults.double(forKey: FanControl.fromKey)
        let to = defaults.double(forKey: FanControl.toKey)
        range = FanControl.scale.contains(from) && FanControl.scale.contains(to)
            && to - from >= FanControl.shortestSpan ? from...to : FanControl.standardRange
    }

    func follow(_ temperature: Double?) {
        guard mode == .curve, problem == nil || problem == .missing,
              let temperature, let level = level(at: temperature) else { return release() }
        hold(level)
    }

    func release() {
        level = nil
        guard input != nil else { return }
        stop()
    }

    private func level(at temperature: Double) -> UInt8? {
        let entry = level == nil ? range.lowerBound : range.lowerBound - FanControl.hysteresis
        guard temperature >= entry else { return nil }
        let fraction = (temperature - range.lowerBound) / (range.upperBound - range.lowerBound)
        return UInt8((min(max(fraction, 0), 1) * 100).rounded())
    }

    private func hold(_ level: UInt8) {
        guard let input = input ?? start() else { return }
        var byte = level
        guard write(input.fileDescriptor, &byte, 1) == 1 else { return stop() }
        self.level = Int(level)
    }

    private func start() -> FileHandle? {
        guard process == nil else { return nil }
        guard installed else {
            problem = .missing
            return nil
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: FanControl.helperPath)
        let pipe = Pipe()
        helper.standardInput = pipe
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        helper.terminationHandler = { [weak self] helper in
            let status = helper.terminationReason == .exit ? helper.terminationStatus : -helper.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.ended(status) }
            }
        }
        guard (try? helper.run()) != nil else {
            problem = .missing
            return nil
        }
        try? pipe.fileHandleForReading.close()
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        problem = nil
        process = helper
        input = pipe.fileHandleForWriting
        return input
    }

    private func stop() {
        try? input?.close()
        input = nil
        level = nil
    }

    private func ended(_ status: Int32) {
        process = nil
        guard input != nil else { return }
        stop()
        problem = .failed(status)
    }
}
