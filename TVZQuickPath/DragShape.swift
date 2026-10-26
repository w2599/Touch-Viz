import SwiftUI

struct DragShape: Shape {
    let points: [CGPoint]
    let maximumWidth: CGFloat

    // 使用线段法向量构造渐宽轨迹，避免逐点三角函数计算。
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1, maximumWidth > 0, maximumWidth.isFinite else { return path }

        let widthMultiplier = maximumWidth / CGFloat(points.count)
        var lastPoint = points[0]
        var lastLeft = lastPoint
        var lastRight = lastPoint
        for index in 1..<points.count {
            let point = points[index]
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            let length = hypot(dx, dy)
            guard length > 0, length.isFinite else { continue }

            let width = widthMultiplier * CGFloat(index)
            let offsetX = dy / length * width
            let offsetY = -dx / length * width
            let newLeft = CGPoint(x: point.x + offsetX, y: point.y + offsetY)
            let newRight = CGPoint(x: point.x - offsetX, y: point.y - offsetY)

            path.move(to: lastLeft)
            path.addLine(to: newLeft)
            path.addLine(to: newRight)
            path.addLine(to: lastRight)
            path.closeSubpath()

            lastLeft = newLeft
            lastRight = newRight
            lastPoint = point

            if index == points.count - 1 {
                path.move(to: lastLeft)
                path.addArc(center: point, radius: width,
                            startAngle: .degrees(0), endAngle: .degrees(360),
                            clockwise: false)
                path.closeSubpath()
            }
        }
        return path
    }
}
