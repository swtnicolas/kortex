import Foundation
import ServiceManagement

@MainActor
enum Settings {
    static let intervals: [Double] = [1, 2, 3, 5, 7, 10]
    static let defaultBar: Double = 3
    static let defaultDetail: Double = 3

    private static let barKey = "barInterval"
    private static let detailKey = "detailInterval"
    private static let dockKey = "showsDockIcon"

    static var onChange: (() -> Void)?

    static var bar: Double {
        get { stored(barKey) ?? defaultBar }
        set { store(newValue, barKey) }
    }

    static var detail: Double {
        get { stored(detailKey) ?? defaultDetail }
        set { store(newValue, detailKey) }
    }

    static var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    static var showsDockIcon: Bool {
        get { UserDefaults.standard.object(forKey: dockKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: dockKey)
            onChange?()
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: barKey)
        UserDefaults.standard.removeObject(forKey: detailKey)
        UserDefaults.standard.removeObject(forKey: dockKey)
        opensAtLogin = false
        onChange?()
    }

    private static func stored(_ key: String) -> Double? {
        let value = UserDefaults.standard.double(forKey: key)
        return intervals.contains(value) ? value : nil
    }

    private static func store(_ value: Double, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }
}
