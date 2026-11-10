import Darwin
import SMCKit

enum Failure: Int32 {
    case notPrivileged = 2
    case noSMC = 3
    case noFans = 4
    case rejected = 5
    case noEvents = 6
}

final class FanHelper {
    private static let automatic: UInt8 = 0
    private static let manual: UInt8 = 1
    private static let highestLevel: UInt8 = 100
    private static let watchdog = timespec(tv_sec: 30, tv_nsec: 0)
    private static let signals = [SIGTERM, SIGINT, SIGHUP]

    private let smc: SMC
    private let fans: [Fan]
    private let user = getuid()
    private var held: UInt8?
    private var engaged = false

    init?(smc: SMC) {
        fans = smc.fans()
        guard !fans.isEmpty else { return nil }
        self.smc = smc
    }

    func run() -> Int32 {
        let queue = kqueue()
        var changes = [kevent(ident: UInt(STDIN_FILENO), filter: Int16(EVFILT_READ), flags: UInt16(EV_ADD),
                              fflags: 0, data: 0, udata: nil)]
        for signal in FanHelper.signals {
            Darwin.signal(signal, SIG_IGN)
            changes.append(kevent(ident: UInt(signal), filter: Int16(EVFILT_SIGNAL), flags: UInt16(EV_ADD),
                                  fflags: 0, data: 0, udata: nil))
        }
        guard queue >= 0, kevent(queue, changes, Int32(changes.count), nil, 0, nil) == 0 else {
            return Failure.noEvents.rawValue
        }

        var event = kevent()
        var timeout = FanHelper.watchdog
        var buffer = [UInt8](repeating: 0, count: 64)
        while true {
            let count = kevent(queue, nil, 0, &event, 1, &timeout)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { break }
            guard count > 0 else {
                release()
                continue
            }
            guard event.filter != Int16(EVFILT_SIGNAL) else { break }
            let received = read(STDIN_FILENO, &buffer, buffer.count)
            if received < 0, errno == EINTR || errno == EAGAIN { continue }
            guard received > 0 else { break }
            let level = buffer[received - 1]
            guard level <= FanHelper.highestLevel else {
                release()
                continue
            }
            guard hold(level) else {
                release()
                return Failure.rejected.rawValue
            }
        }
        release()
        return 0
    }

    private func hold(_ level: UInt8) -> Bool {
        let drifted = fans.contains { smc.byte(of: $0.mode) != FanHelper.manual }
        guard level != held || drifted else { return true }
        engaged = true
        held = nil
        let applied = privileged {
            fans.allSatisfy { fan in
                smc.setByte(FanHelper.manual, of: fan.mode)
                    && smc.setValue(fan.speed(at: level), of: fan.target)
            }
        }
        if applied { held = level }
        return applied
    }

    private func release() {
        guard engaged else { return }
        _ = privileged {
            fans.map { smc.setByte(FanHelper.automatic, of: $0.mode) }.allSatisfy { $0 }
        }
        engaged = false
        held = nil
    }

    private func privileged(_ body: () -> Bool) -> Bool {
        seteuid(0)
        defer { seteuid(user) }
        return body()
    }
}

func serve() -> Int32 {
    guard geteuid() == 0 else { return Failure.notPrivileged.rawValue }
    guard let smc = SMC() else { return Failure.noSMC.rawValue }
    seteuid(getuid())
    guard let helper = FanHelper(smc: smc) else { return Failure.noFans.rawValue }
    return helper.run()
}

exit(serve())
