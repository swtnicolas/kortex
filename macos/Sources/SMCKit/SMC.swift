import IOKit

public final class SMC {
    public struct Key: Sendable {
        public let code: UInt32
        public let name: String
        public let size: UInt32
        public let type: UInt32
    }

    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var memory: UInt32 = 0
    }

    private struct KeyInfo {
        var size: UInt32 = 0
        var type: UInt32 = 0
        var attributes: UInt8 = 0
    }

    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var limits = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var index: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command {
        static let read: UInt8 = 5
        static let write: UInt8 = 6
        static let keyFromIndex: UInt8 = 8
        static let keyInfo: UInt8 = 9
    }

    private static let dispatchSelector: UInt32 = 2
    private static let floatType = SMC.code(of: "flt ")
    private static let byteType = SMC.code(of: "ui8 ")

    private let connection: io_connect_t

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard opened == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    public func floatKeys(withPrefixes prefixes: [String]) -> [Key] {
        guard let count = keyCount() else { return [] }
        var found: [Key] = []
        for index in 0..<count {
            var input = Param()
            input.command = Command.keyFromIndex
            input.index = UInt32(index)
            guard let output = call(&input) else { continue }
            let name = SMC.name(of: output.key)
            guard prefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard let key = key(code: output.key, name: name), key.type == SMC.floatType else { continue }
            found.append(key)
        }
        return found
    }

    public func key(named name: String) -> Key? {
        key(code: SMC.code(of: name), name: name)
    }

    public func value(of key: Key) -> Double? {
        guard key.type == SMC.floatType, key.size == 4, let bytes = read(key) else { return nil }
        let raw = withUnsafeBytes(of: bytes) { buffer in
            UInt32(buffer[0]) | UInt32(buffer[1]) << 8 | UInt32(buffer[2]) << 16 | UInt32(buffer[3]) << 24
        }
        let value = Double(Float(bitPattern: raw))
        return value.isFinite ? value : nil
    }

    public func byte(of key: Key) -> UInt8? {
        guard key.type == SMC.byteType, key.size == 1, let bytes = read(key) else { return nil }
        return bytes.0
    }

    public func setValue(_ value: Double, of key: Key) -> Bool {
        guard key.type == SMC.floatType, key.size == 4 else { return false }
        let raw = Float(value).bitPattern
        return write(key, [UInt8(raw & 0xFF), UInt8(raw >> 8 & 0xFF),
                           UInt8(raw >> 16 & 0xFF), UInt8(raw >> 24 & 0xFF)])
    }

    public func setByte(_ byte: UInt8, of key: Key) -> Bool {
        guard key.type == SMC.byteType, key.size == 1 else { return false }
        return write(key, [byte])
    }

    private func keyCount() -> Int? {
        guard let key = key(code: SMC.code(of: "#KEY"), name: "#KEY"), key.size == 4,
              let bytes = read(key) else { return nil }
        return withUnsafeBytes(of: bytes) { buffer in
            Int(UInt32(buffer[0]) << 24 | UInt32(buffer[1]) << 16
                | UInt32(buffer[2]) << 8 | UInt32(buffer[3]))
        }
    }

    private func key(code: UInt32, name: String) -> Key? {
        var input = Param()
        input.key = code
        input.command = Command.keyInfo
        guard let output = call(&input) else { return nil }
        return Key(code: code, name: name, size: output.keyInfo.size, type: output.keyInfo.type)
    }

    private func read(_ key: Key) -> Bytes? {
        var input = Param()
        input.key = key.code
        input.keyInfo.size = key.size
        input.keyInfo.type = key.type
        input.command = Command.read
        return call(&input)?.bytes
    }

    private func write(_ key: Key, _ bytes: [UInt8]) -> Bool {
        var input = Param()
        input.key = key.code
        input.keyInfo.size = key.size
        input.keyInfo.type = key.type
        input.command = Command.write
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes) }
        return call(&input) != nil
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, SMC.dispatchSelector, &input,
                                              MemoryLayout<Param>.stride, &output, &size)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func code(of text: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in text.utf8 { value = value << 8 | UInt32(byte) }
        return value
    }

    private static func name(of code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF),
                     UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
