//
//  UIWindowScene+TouchVisualizer.m
//  LNTouchVisualizer
//
//  Created by Leo Natan on 3/24/21.
//

#import <LNTouchVisualizer/LNTouchVisualizerWindow.h>
#import <LNTouchVisualizer/UIWindowScene+TouchVisualizer.h>

#import <objc/runtime.h>

#import "TouchViz-Swift.h"

static const void *LNTouchVisualizerWindowKey = &LNTouchVisualizerWindowKey;

__attribute__((visibility("hidden")))
@interface _LNSceneTouchVisualizerWindow : LNTouchVisualizerWindow
@end
@implementation _LNSceneTouchVisualizerWindow

#ifndef LNPopupControllerEnforceStrictClean
// 禁止覆盖层改变状态栏或成为主窗口。
+ (void)load {
    @autoreleasepool {
        NSMutableString *name = [@"_" mutableCopy];
        [name appendString:@"canAffect"];
        [name appendString:[NSStringFromClass(UIStatusBarManager.class) substringWithRange:NSMakeRange(2, 9)]];
        [name appendString:[NSStringFromClass(UIBarAppearance.class) substringFromIndex:5]];

        Method m = class_getInstanceMethod(self, @selector(_cASBA));
        class_addMethod(self, NSSelectorFromString(name), method_getImplementation(m), method_getTypeEncoding(m));

        name = [@"_" mutableCopy];
        [name appendString:[NSStringFromSelector(@selector(canBecomeFirstResponder)) substringToIndex:9]];
        [name appendString:[NSStringFromSelector(@selector(isKeyWindow)) substringFromIndex:2]];

        m = class_getInstanceMethod(self, @selector(_cASBA));
        class_addMethod(self, NSSelectorFromString(name), method_getImplementation(m), method_getTypeEncoding(m));
    }
}

// 不影响状态栏外观。
- (BOOL)_cASBA {
    return NO;
}

// 不允许成为主窗口。
- (BOOL)_cBKW {
    return NO;
}
#endif

// 场景窗口直接承载触点，避免额外创建覆盖窗口。
- (UIWindow *)overlayWindow {
    return self;
}

@end

@implementation UIWindowScene (TouchVisualizer)

// 仅显式请求窗口时创建停用状态的覆盖层。
- (LNTouchVisualizerWindow *)touchVisualizerWindow {
    LNTouchVisualizerWindow *rv = objc_getAssociatedObject(self, LNTouchVisualizerWindowKey);

    if (rv != nil) {
        return rv;
    }
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        rv = [[_LNSceneTouchVisualizerWindow alloc] initWithFrame:UIScreen.mainScreen.bounds
                                     touchVisualizationEnabled:NO
                                              quickPathEnabled:NO
                                                  morphEnabled:NO
                                               trackingEnabled:NO
                                                 contactConfig:nil
                                                  rippleConfig:nil];
        rv.windowLevel = CGFLOAT_MAX;
        rv.backgroundColor = UIColor.clearColor;
        rv.hidden = YES;
        rv.userInteractionEnabled = NO;
        rv.frame = UIScreen.mainScreen.bounds;
        rv.windowScene = self;

        objc_setAssociatedObject(self, LNTouchVisualizerWindowKey, rv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return rv;
}

// 停用不创建窗口，并同步关闭全部触摸效果。
- (void)setTouchVisualizerEnabled:(BOOL)touchVisualizerEnabled {
    LNTouchVisualizerWindow *window = touchVisualizerEnabled ? self.touchVisualizerWindow :
        objc_getAssociatedObject(self, LNTouchVisualizerWindowKey);
    window.touchVisualizationEnabled = touchVisualizerEnabled;
    window.hidden = !touchVisualizerEnabled;
}

// 查询状态不触发窗口创建。
- (BOOL)touchVisualizerEnabled {
    LNTouchVisualizerWindow *window = objc_getAssociatedObject(self, LNTouchVisualizerWindowKey);
    return window != nil && window.touchVisualizationEnabled && !window.hidden;
}

@end
