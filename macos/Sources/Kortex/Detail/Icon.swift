import AppKit

enum Icon {
    case settings, power, back, collapsed, expanded, close, lock, clear, search

    private static let grid: CGFloat = 24

    func draw(in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        let scale = rect.width / Icon.grid
        if context.isFlipped {
            transform.translateX(by: rect.minX, yBy: rect.minY)
            transform.scaleX(by: scale, yBy: scale)
        } else {
            transform.translateX(by: rect.minX, yBy: rect.maxY)
            transform.scaleX(by: scale, yBy: -scale)
        }
        transform.concat()
        color.set()
        paint()
        context.restoreGraphicsState()
    }

    private func paint() {
        switch self {
        case .settings:
            let gear = NSBezierPath()
            for tooth in 0..<8 {
                let center = CGFloat(tooth) * .pi / 4
                for (offset, radius) in [(-0.3, 7.6), (-0.17, 10.0), (0.17, 10.0), (0.3, 7.6)] as [(CGFloat, CGFloat)] {
                    let point = Icon.point(center + offset, radius)
                    if gear.isEmpty { gear.move(to: point) } else { gear.line(to: point) }
                }
            }
            gear.close()
            Icon.stroke(gear, width: 1.7)
            Icon.stroke(NSBezierPath(ovalIn: NSRect(x: 9, y: 9, width: 6, height: 6)), width: 1.7)
        case .power:
            let ring = Icon.arc(from: -55, to: 235, radius: 8, center: NSPoint(x: 12, y: 13))
            ring.move(to: NSPoint(x: 12, y: 3))
            ring.line(to: NSPoint(x: 12, y: 11))
            Icon.stroke(ring)
        case .back:
            Icon.stroke(Icon.line([(15, 5), (8, 12), (15, 19)]), width: 2.4)
        case .collapsed:
            Icon.stroke(Icon.line([(9, 5), (16, 12), (9, 19)]), width: 2.6)
        case .expanded:
            Icon.stroke(Icon.line([(5, 9), (12, 16), (19, 9)]), width: 2.6)
        case .close:
            let cross = Icon.line([(6, 6), (18, 18)])
            cross.append(Icon.line([(18, 6), (6, 18)]))
            Icon.stroke(cross, width: 2.4)
        case .lock:
            NSBezierPath(roundedRect: NSRect(x: 5, y: 11, width: 14, height: 10), xRadius: 2.5, yRadius: 2.5).fill()
            let shackle = NSBezierPath()
            shackle.move(to: NSPoint(x: 8, y: 12))
            shackle.line(to: NSPoint(x: 8, y: 8))
            shackle.appendArc(withCenter: NSPoint(x: 12, y: 8), radius: 4, startAngle: 180, endAngle: 0,
                              clockwise: false)
            shackle.line(to: NSPoint(x: 16, y: 12))
            Icon.stroke(shackle, width: 2.4)
        case .clear:
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 20, height: 20)).fill()
            context.setBlendMode(.clear)
            let cross = Icon.line([(8.5, 8.5), (15.5, 15.5)])
            cross.append(Icon.line([(15.5, 8.5), (8.5, 15.5)]))
            Icon.stroke(cross, width: 2.2)
            context.endTransparencyLayer()
        case .search:
            let lens = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 14, height: 14))
            lens.append(Icon.line([(15, 15), (21, 21)]))
            Icon.stroke(lens, width: 2.2)
        }
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat = 2) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func line(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let location = NSPoint(x: point.0, y: point.1)
            if index == 0 { path.move(to: location) } else { path.line(to: location) }
        }
        return path
    }

    private static func arc(from start: CGFloat, to end: CGFloat, radius: CGFloat,
                            center: NSPoint = NSPoint(x: 12, y: 12)) -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }

    private static func point(_ angle: CGFloat, _ radius: CGFloat) -> NSPoint {
        NSPoint(x: 12 + radius * cos(angle), y: 12 + radius * sin(angle))
    }
}
