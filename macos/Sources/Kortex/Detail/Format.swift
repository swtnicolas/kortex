import Foundation

enum Format {
    private static let gigabyte = 1024.0 * 1024 * 1024
    private static let megabyte = 1024.0 * 1024

    static func decimal(_ value: Double, places: Int = 2) -> String {
        let scale = pow(10.0, Double(places))
        let rounded = (value * scale).rounded() / scale
        let digits = rounded == rounded.rounded() ? 0 : places
        return String(format: "%.\(digits)f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    static func fixed(_ value: Double, places: Int) -> String {
        let scale = pow(10.0, Double(places))
        return String(format: "%.\(places)f", (value * scale).rounded() / scale)
            .replacingOccurrences(of: ".", with: ",")
    }

    static func size(_ bytes: Double) -> String {
        bytes >= gigabyte ? "\(decimal(bytes / gigabyte)) GB" : "\(decimal(bytes / megabyte)) MB"
    }

    static func gigahertz(_ megahertz: Double) -> String {
        fixed(megahertz / 1000, places: 2)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(max(0, value).rounded()))%"
    }

    static func share(_ value: Double) -> String {
        value < 1 ? "\(decimal(value))%" : percent(value)
    }

    static func watts(_ value: Double, places: Int = 1) -> String {
        "\(decimal(value, places: places)) W"
    }

    static func cost(_ percent: Double) -> String {
        "Usa ~\(decimal(percent, places: percent < 0.1 ? 2 : 1))% de CPU"
    }

    static func degrees(_ value: Double, places: Int = 0) -> String {
        "\(fixed(value, places: places)) °C"
    }
}
