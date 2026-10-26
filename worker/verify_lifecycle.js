// 兼容 Frida 对 Objective-C 空对象的两种表示。
function isNil(value) { return value === null || (value.handle || value).isNull(); }
// 隐藏的隔离窗口验证清理；不向系统分发触摸、不修改用户设置。
const Touch = ObjC.classes.UITouch;
const Event = ObjC.classes.UIEvent;
let phase = 0;
let location = [100, 200];
const ProbeTouch = ObjC.registerClass({
    name: 'TVZLifecycleProbeTouch',
    super: Touch,
    methods: {
        '- phase': { types: Touch['- phase'].types, implementation() { return phase; } },
        '- type': { types: Touch['- type'].types, implementation() { return 0; } },
        '- timestamp': { types: Touch['- timestamp'].types, implementation() { return Date.now() / 1000; } },
        '- locationInView:': { types: Touch['- locationInView:'].types, implementation() { return location; } }
    }
});
let eventTouches;
const ProbeEvent = ObjC.registerClass({
    name: 'TVZLifecycleProbeEvent',
    super: Event,
    methods: {
        '- type': { types: Event['- type'].types, implementation() { return 0; } },
        '- allTouches': { types: Event['- allTouches'].types, implementation() { return eventTouches.handle; } }
    }
});
// 断言失败时打印确切字段，方便定位回归。
function assert(value, message) {
    if (!value) throw new Error(message);
}
let window;
let phaseResult;
ObjC.schedule(ObjC.mainQueue, () => {
    try {
        window = ObjC.classes._LNSceneTouchVisualizerWindow.alloc()
            .initWithFrame_touchVisualizationEnabled_quickPathEnabled_morphEnabled_trackingEnabled_contactConfig_rippleConfig_(
                [[0, 0], [390, 844]], false, true, true, true, NULL, NULL);
        window.setHidden_(true);
        const touch = ProbeTouch.alloc().init();
        eventTouches = ObjC.classes.NSSet.setWithObject_(touch);
        const event = ProbeEvent.alloc().init();
        window.sendTouchEvent_(event);
        assert(!window.hasAnyTouch(), '停用窗口处理了触摸');
        window.setTouchVisualizationEnabled_(true);
        assert(!isNil(window.rootViewController()), '启用后未恢复轨迹控制器');
        window.sendTouchEvent_(event);
        window.sendQuickPathEvent_(event);
        assert(window.hasAnyTouch(), '按下未记录活动触点');
        phase = 1;
        location = [130, 240];
        window.sendTouchEvent_(event);
        window.sendQuickPathEvent_(event);
        phase = 3;
        window.sendTouchEvent_(event);
        window.sendQuickPathEvent_(event);
        assert(!window.hasAnyTouch(), '抬起后残留活动触点');
        phase = 0;
        window.sendTouchEvent_(event);
        window.sendQuickPathEvent_(event);
        window.setTouchVisualizationEnabled_(false);
        assert(!window.hasAnyTouch(), '停用后残留触点');
        assert(isNil(window.rootViewController()), '停用后残留轨迹控制器');
        assert(Number(window.valueForKey_('_renderedTouchViews').count()) === 0, '停用后残留动画视图');
        assert(isNil(window.valueForKey_('_orientationObserver')), '停用后残留方向观察者');
        assert(!window.valueForKey_('_fingerTipRemovalScheduled').boolValue(), '停用后残留延迟清理');
        window.setTouchVisualizationEnabled_(true);
        assert(!isNil(window.rootViewController()), '再次启用未恢复轨迹控制器');
        assert(window.isMorphEnabled() && window.isTrackingEnabled(), '效果配置未保留');
        window.setTouchVisualizationEnabled_(false);
        phaseResult = 'passed';
        console.log(JSON.stringify({ lifecycle: phaseResult }));
    } catch (error) {
        console.log(JSON.stringify({ lifecycle: 'failed', error: String(error), stack: error.stack }));
    } finally {
        if (window) {
            window.setTouchVisualizationEnabled_(false);
            window.setHidden_(true);
            window.release();
        }
    }
});
