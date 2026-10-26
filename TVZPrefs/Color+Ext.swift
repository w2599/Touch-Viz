import SwiftUI

let TVZ_UICOLOR = UIColor(red: 235.0 / 255, green: 59.0 / 255, blue: 90.0 / 255, alpha: 1.0)
let TVZ_COLOR = Color(TVZ_UICOLOR)

extension Color {
    // 校验并限制颜色分量，损坏配置回退为透明色。
    init(rgbString: String) {
        let fields = rgbString.split(separator: ",", omittingEmptySubsequences: false)
        let components = fields.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard (3...4).contains(components.count), components.count == fields.count,
              components.allSatisfy({ $0.isFinite }) else {
            self = .clear
            return
        }
        self.init(.sRGB,
                  red: min(max(components[0], 0), 255) / 255,
                  green: min(max(components[1], 0), 255) / 255,
                  blue: min(max(components[2], 0), 255) / 255,
                  opacity: components.count == 4 ? min(max(components[3], 0), 1) : 1)
    }

    // 统一转换 RGB 和灰度颜色，避免按底层分量数量直接索引。
    func toRGBString() -> String {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            guard color.getWhite(&white, alpha: &alpha) else {
                return "0,0,0,0"
            }
            red = white
            green = white
            blue = white
        }
        let components = [red, green, blue, alpha].map { $0.isFinite ? min(max($0, 0), 1) : 0 }
        return "\(Int((components[0] * 255).rounded())),\(Int((components[1] * 255).rounded())),\(Int((components[2] * 255).rounded())),\(components[3])"
    }
}
