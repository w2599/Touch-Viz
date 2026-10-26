// 兼容 Frida 对 Objective-C 空对象的两种表示。
function isNil(value) { return value === null || (value.handle || value).isNull(); }
// 只读取当前窗口，不创建窗口或修改用户偏好。
ObjC.schedule(ObjC.mainQueue, () => {
    const defaults = ObjC.classes.TVZUserDefaults.standardUserDefaults();
    const state = {};
    for (const key of ['isEnabled', 'isRecordingOnly', 'enableOverride', 'disableOverride', 'disableOverrideWhenRecording']) {
        state[key] = !!defaults.boolForKey_(key);
    }
    const windows = ObjC.chooseSync(ObjC.classes.LNTouchVisualizerWindow);
    const result = {
        captured: !!ObjC.classes.UIScreen.mainScreen().isCaptured(),
        preferences: state,
        windows: windows.map(window => ({
            hidden: !!window.isHidden(),
            enabled: !!window.isTouchVisualizationEnabled(),
            touches: !!window.hasAnyTouch(),
            controller: !isNil(window.rootViewController())
        }))
    };
    console.log(JSON.stringify(result));
});
