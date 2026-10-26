import SwiftUI
import QuartzCore

@objc(TVZQuickPathViewController)
open class QuickPathEffectRootViewController: UIViewController {
    // 创建透明轨迹容器。
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let controller = QuickPathEffectViewController()
        addChild(controller)

        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        controller.view.backgroundColor = .clear
        view.addSubview(controller.view)

        controller.didMove(toParent: self)
    }

    open override var shouldAutorotate: Bool {
        false
    }

    // 允许锁屏时显示轨迹。
    @objc(_canShowWhileLocked)
    open func _canShowWhileLocked() -> Bool {
        true
    }
}

fileprivate final class QuickPathEffectViewController: UIHostingController<QuickPathEffectView> {
    // 装载轨迹视图。
    init() {
        super.init(rootView: QuickPathEffectView())
    }

    // 禁止通过归档创建控制器。
    @objc required dynamic public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 允许锁屏时显示轨迹。
    @objc(_canShowWhileLocked)
    public func _canShowWhileLocked() -> Bool {
        true
    }
}

fileprivate struct QuickPathEffectView: View {
    @ObservedObject var vm = QuickPathEffect.shared

    var body: some View {
        ZStack {
            ForEach(Array(vm.touches.values)) {
                TouchCursor(
                    touch: $0,
                    maximumWidth: vm.fillWidth,
                    animationDuration: vm.animationDuration
                )
                .foregroundColor(vm.fillColor)
            }
        }.edgesIgnoringSafeArea(.all)
    }
}

fileprivate struct TouchCursor: View {
    @ObservedObject var touch: QuickPathEffect.Touch

    let maximumWidth: CGFloat
    let animationDuration: TimeInterval

    var body: some View {
        DragShape(points: touch.points, maximumWidth: maximumWidth)
            .fill()
            .opacity(touch.ended ? 0 : 1.0)
            .animation(.easeIn(duration: animationDuration), value: touch.ended)
    }
}

fileprivate final class QuickPathEffect: ObservableObject {
    static let shared = QuickPathEffect()
    private var decayTimer: Timer?
    private var scheduledFireTime: CFTimeInterval?
    private var nextDecayTime: CFTimeInterval?
    private var nextTouchID = 0
    private var activeTouches: [ObjectIdentifier: Touch] = [:]

    // 轨迹模型由主线程上的窗口事件共用。
    private init() {}

    final class Touch: ObservableObject, Identifiable {
        @Published var points: [CGPoint]
        @Published var ended = false
        let id: Int
        private(set) var removalTime: CFTimeInterval?

        // 记录初始坐标，不为静止触摸创建计时器。
        init(id: Int, from uiTouch: UITouch, in window: UIWindow) {
            self.points = [Self.location(from: uiTouch, in: window)]
            self.id = id
        }

        // 冻结结束轨迹，确保短尾迹也完成设定时长的渐隐。
        func end(after duration: TimeInterval) {
            guard !ended else { return }
            removalTime = CACurrentMediaTime() + max(0, duration)
            ended = true
        }

        // 忽略重复坐标，并限制异常事件流的轨迹长度。
        func append(_ point: CGPoint) {
            guard points.last != point else { return }
            if points.count >= 256 {
                points.removeFirst(points.count - 255)
            }
            points.append(point)
        }

        // 收缩轨迹尾部，保留仍按下的触摸位置。
        func decay() {
            if points.count > 10 {
                points.removeFirst(points.count / 10)
            } else if points.count > 1 {
                points.removeFirst()
            }
        }

        // 将触摸坐标转换为覆盖窗口的固定方向坐标。
        static func location(from uiTouch: UITouch, in window: UIWindow) -> CGPoint {
            let orientation = window._windowInterfaceOrientation()
            let fixedSpace = window.screen.fixedCoordinateSpace.bounds
            let location = uiTouch.location(in: nil)
            switch orientation {
            case .portraitUpsideDown:
                return CGPoint(x: fixedSpace.width - location.x, y: fixedSpace.height - location.y)
            case .landscapeLeft:
                return CGPoint(x: fixedSpace.height - location.y, y: location.x)
            case .landscapeRight:
                return CGPoint(x: location.y, y: fixedSpace.width - location.x)
            default:
                return location
            }
        }
    }

    @Published var touches: [Int: Touch] = [:]
    @Published var fillColor: Color = Color.black.opacity(0.4)
    @Published var fillWidth: CGFloat = 10.0
    @Published var animationDuration: TimeInterval = 0.3

    // 为每次手势分配独立显示标识，保留同一 UITouch 上次的渐隐轨迹。
    func begin(_ uiTouch: UITouch, in window: UIWindow) {
        let key = ObjectIdentifier(uiTouch)
        activeTouches[key]?.end(after: animationDuration)
        nextTouchID &+= 1
        let touch = Touch(id: nextTouchID, from: uiTouch, in: window)
        activeTouches[key] = touch
        touches[touch.id] = touch
    }

    // 从移动事件恢复中途开启效果的触摸。
    func move(_ uiTouch: UITouch, in window: UIWindow) {
        guard let touch = activeTouches[ObjectIdentifier(uiTouch)] else {
            begin(uiTouch, in: window)
            return
        }
        touch.append(Touch.location(from: uiTouch, in: window))
    }

    // 结束当前手势，同时允许 UITouch 被下一次手势复用。
    func end(_ uiTouch: UITouch, in window: UIWindow) {
        guard let touch = activeTouches.removeValue(forKey: ObjectIdentifier(uiTouch)) else { return }
        touch.append(Touch.location(from: uiTouch, in: window))
        touch.end(after: animationDuration)
    }

    // 活跃尾迹按需收缩，仅渐隐时直接等待最近的回收时间。
    func scheduleDecay() {
        let now = CACurrentMediaTime()
        var needsDecay = false
        var fireTime = CFTimeInterval.infinity
        for touch in touches.values {
            if let removalTime = touch.removalTime {
                fireTime = min(fireTime, removalTime)
            } else if touch.points.count > 1 {
                needsDecay = true
            }
        }
        if needsDecay {
            if nextDecayTime == nil {
                nextDecayTime = now + 0.05
            }
            fireTime = min(fireTime, nextDecayTime!)
        } else {
            nextDecayTime = nil
        }
        guard fireTime.isFinite else {
            decayTimer?.invalidate()
            decayTimer = nil
            scheduledFireTime = nil
            return
        }
        if let scheduledFireTime, abs(scheduledFireTime - fireTime) < 0.001 {
            return
        }
        decayTimer?.invalidate()
        scheduledFireTime = fireTime
        let timer = Timer(timeInterval: max(0.001, fireTime - now), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.decayTimer = nil
            self.scheduledFireTime = nil
            self.decayTouches()
            self.scheduleDecay()
        }
        timer.tolerance = 0.005
        decayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // 收缩仍按下的尾迹，独立回收已经完成渐隐的手势。
    private func decayTouches() {
        let now = CACurrentMediaTime()
        let shouldDecay = nextDecayTime.map { $0 <= now } ?? false
        if shouldDecay {
            nextDecayTime = nil
        }
        var finished: [Int] = []
        for touch in touches.values {
            if let removalTime = touch.removalTime {
                if removalTime <= now {
                    finished.append(touch.id)
                }
            } else if shouldDecay {
                touch.decay()
            }
        }
        for id in finished {
            touches.removeValue(forKey: id)
        }
    }

    // 让当前手势正常渐隐，同时解除活动触摸的关联。
    func endAll() {
        for touch in activeTouches.values {
            touch.end(after: animationDuration)
        }
        activeTouches.removeAll()
        scheduleDecay()
    }

    // 停用效果时立即取消计时器和全部轨迹。
    func reset() {
        decayTimer?.invalidate()
        decayTimer = nil
        scheduledFireTime = nil
        nextDecayTime = nil
        activeTouches.removeAll()
        guard !touches.isEmpty else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            touches.removeAll()
        }
    }

}

extension UIWindow {
    // 直接遍历事件，静止触摸不追加轨迹点。
    @objc
    public func sendQuickPathEvent(_ event: UIEvent) {
        guard let touches = event.allTouches else { return }
        for touch in touches where touch.type == .direct {
            switch touch.phase {
            case .began: QuickPathEffect.shared.begin(touch, in: self)
            case .moved: QuickPathEffect.shared.move(touch, in: self)
            case .cancelled, .ended: QuickPathEffect.shared.end(touch, in: self)
            case .stationary, .regionEntered, .regionMoved, .regionExited: break
            @unknown default: break
            }
        }
        QuickPathEffect.shared.scheduleDecay()
    }

    // 仅在颜色改变时通知轨迹视图。
    @objc
    public func setQuickPathFillColor(_ color: UIColor) {
        let value = Color(color)
        if QuickPathEffect.shared.fillColor != value {
            QuickPathEffect.shared.fillColor = value
        }
    }

    // 仅在宽度改变时通知轨迹视图。
    @objc
    public func setQuickPathFillWidth(_ width: CGFloat) {
        if QuickPathEffect.shared.fillWidth != width {
            QuickPathEffect.shared.fillWidth = width
        }
    }

    // 仅在渐隐时长改变时通知轨迹视图。
    @objc
    public func setQuickPathAnimationDuration(_ duration: TimeInterval) {
        if QuickPathEffect.shared.animationDuration != duration {
            QuickPathEffect.shared.animationDuration = duration
        }
    }

    // 让当前轨迹正常渐隐并按需回收。
    @objc
    public func endAllQuickPathTouches() {
        QuickPathEffect.shared.endAll()
    }

    // 隐藏窗口或停用效果时立即释放轨迹和计时器。
    @objc
    public func resetQuickPathTouches() {
        QuickPathEffect.shared.reset()
    }
}
