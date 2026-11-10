import Foundation
import IOKit

struct AdapterInfo: Sendable {
    let name: String
    let watts: Double
    let volts: Double
    let amps: Double

    var delivered: Double {
        volts * amps
    }
}

struct BatterySnapshot: Sendable {
    let percentage: Double
    let connected: Bool
    let charging: Bool
    let fullyCharged: Bool
    let minutesRemaining: Int?
    let health: Double
    let cycles: Int
    let designCycles: Int
    let capacity: Double
    let designCapacity: Double
    let volts: Double
    let milliamps: Double
    let systemWatts: Double
    let batteryWatts: Double
    let adapter: AdapterInfo?

    var state: String {
        guard connected else { return "Con batería · descargando" + rate(-batteryWatts) }
        if fullyCharged { return "Conectado · cargada" }
        return charging ? "Conectado · cargando" + rate(batteryWatts) : "Conectado"
    }

    private func rate(_ watts: Double) -> String {
        watts >= 1 ? " a \(Format.decimal(watts, places: 0)) W" : ""
    }
}

struct PowerModes: Sendable {
    let battery: String
    let adapter: String

    static func name(of value: Int) -> String {
        switch value {
        case 1: "Bajo consumo"
        case 2: "Alto rendimiento"
        default: "Automático"
        }
    }
}

enum BatteryReader {
    private static let unknownTime = 65535

    static func snapshot() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var raw: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0)
        guard let values = raw?.takeRetainedValue() as? [String: Any] else { return nil }

        let data = values["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = values["PowerTelemetryData"] as? [String: Any] ?? [:]
        let remaining = number(values["TimeRemaining"]).map(Int.init) ?? unknownTime

        return BatterySnapshot(
            percentage: number(values["CurrentCapacity"]) ?? 0,
            connected: flag(values["ExternalConnected"]),
            charging: flag(values["IsCharging"]),
            fullyCharged: flag(values["FullyCharged"]),
            minutesRemaining: remaining == unknownTime || remaining <= 0 ? nil : remaining,
            health: number(values["MaxCapacity"]) ?? 0,
            cycles: Int(number(values["CycleCount"]) ?? 0),
            designCycles: Int(number(values["DesignCycleCount9C"]) ?? 0),
            capacity: number(data["FullChargeCapacity"]) ?? 0,
            designCapacity: number(data["DesignCapacity"]) ?? 0,
            volts: (number(values["Voltage"]) ?? 0) / 1000,
            milliamps: number(values["Amperage"]) ?? 0,
            systemWatts: (number(telemetry["SystemLoad"]) ?? 0) / 1000,
            batteryWatts: (number(telemetry["BatteryPower"]) ?? 0) / 1000,
            adapter: adapter(values["AdapterDetails"] as? [String: Any], telemetry)
        )
    }

    static func modes() async -> PowerModes? {
        await Task.detached(priority: .utility) {
            let output = run("/usr/bin/pmset", ["-g", "custom"])
            var battery: Int?
            var adapter: Int?
            var onBattery = true
            for line in output.split(separator: "\n") {
                if line.hasPrefix("Battery Power") { onBattery = true }
                if line.hasPrefix("AC Power") { onBattery = false }
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count == 2, fields[0] == "powermode", let value = Int(fields[1]) else {
                    continue
                }
                if onBattery { battery = value } else { adapter = value }
            }
            guard let battery, let adapter else { return nil }
            return PowerModes(battery: PowerModes.name(of: battery),
                              adapter: PowerModes.name(of: adapter))
        }.value
    }

    private static func adapter(_ details: [String: Any]?,
                                _ telemetry: [String: Any]) -> AdapterInfo? {
        guard let details else { return nil }
        let volts = (number(details["AdapterVoltage"]) ?? 0) / 1000
        let amps = (number(details["Current"]) ?? 0) / 1000
        let watts = number(details["Watts"]) ?? volts * amps
        guard watts > 0 else { return nil }
        return AdapterInfo(
            name: details["Name"] as? String ?? "Adaptador USB-C",
            watts: watts,
            volts: (number(telemetry["SystemVoltageIn"]) ?? 0) / 1000,
            amps: (number(telemetry["SystemCurrentIn"]) ?? 0) / 1000
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func flag(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
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
