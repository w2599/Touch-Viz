//
//  LNTouchVisualizerWindow.m
//  TouchVisualizer
//
//  Created by Joe Blau on 3/22/14.
//  Copyright (c) 2014 conopsys. All rights reserved.
//

#import "LNOverlayVisualizerWindow.h"
#import "LNTouchImageFactory.h"
#import "LNTouchImageView.h"

#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <LNTouchVisualizer/LNTouchConfig.h>
#import <LNTouchVisualizer/LNTouchVisualizerWindow.h>

#import "TouchViz-Swift.h"

static const NSTimeInterval TOUCH_VISUALIZER_WINDOW_REMOVE_DELAY = 6.0;
static NSString *const LNTouchMorphAnimationKey = @"touchviz.morph";

@interface UIWindow (Private)
- (UIInterfaceOrientation)_windowInterfaceOrientation;
@end

@interface FBSOrientationUpdate : NSObject
- (unsigned long long)sequenceNumber;
- (UIInterfaceOrientation)orientation;
@end

@interface FBSOrientationObserver : NSObject
- (void)setHandler:(void (^)(FBSOrientationUpdate *))handler;
- (void)invalidate;
@end

__attribute__((visibility("hidden")))
@interface LNTouchVisualizerWindow ()
@property(nonatomic, strong) UIWindow *overlayWindow;
@property(nonatomic, strong) UIImage *touchImage;
@property(nonatomic, strong) UIImage *rippleImage;
@end

@implementation LNTouchVisualizerWindow {
    FBSOrientationObserver *_orientationObserver;
    unsigned long long _globalSequenceNumber;
    UIInterfaceOrientation _globalInterfaceOrientation;
    NSMutableDictionary<NSNumber *, LNTouchImageView *> *_activeTouchViews;
    NSMutableSet<LNTouchImageView *> *_renderedTouchViews;
    BOOL _fingerTipRemovalScheduled;
    NSTimeInterval _rippleFrameInterval;
}

// 创建默认触摸窗口。
- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame
        touchVisualizationEnabled:YES
                 quickPathEnabled:NO
                     morphEnabled:NO
                  trackingEnabled:NO
                    contactConfig:nil
                     rippleConfig:nil];
}

// 初始化配置，停用时不创建观察者或绘制界面。
- (instancetype)initWithFrame:(CGRect)frame
    touchVisualizationEnabled:(BOOL)touchVisualizationEnabled
             quickPathEnabled:(BOOL)quickPathEnabled
                 morphEnabled:(BOOL)morphEnabled
              trackingEnabled:(BOOL)trackingEnabled
                contactConfig:(nullable LNTouchConfig *)contactConfig
                 rippleConfig:(nullable LNTouchConfig *)rippleConfig {
    self = [super initWithFrame:frame];
    if (self) {
        _quickPathEnabled = quickPathEnabled;
        _morphEnabled = morphEnabled;
        _trackingEnabled = trackingEnabled;
        _touchContactConfig = contactConfig ?: [LNTouchConfig touchConfig];
        _touchRippleConfig = rippleConfig ?: [LNTouchConfig rippleConfig];
        _activeTouchViews = [NSMutableDictionary dictionary];
        _renderedTouchViews = [NSMutableSet set];
        _rippleFrameInterval = 1.0 / MAX(UIScreen.mainScreen.maximumFramesPerSecond, 60);
        self.touchVisualizationEnabled = touchVisualizationEnabled;
    }
    return self;
}

// 释放方向观察资源。
- (void)dealloc {
    [_orientationObserver setHandler:nil];
    if ([_orientationObserver respondsToSelector:@selector(invalidate)]) {
        [_orientationObserver invalidate];
    }
}

// 仅在显示期间观察方向，避免停用后仍收到方向事件。
- (void)startObservingOrientation {
    if (_orientationObserver != nil) {
        return;
    }
    _globalSequenceNumber = 0;
    _globalInterfaceOrientation = [self _windowInterfaceOrientation];
    _orientationObserver = [[FBSOrientationObserver alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak FBSOrientationObserver *weakObserver = _orientationObserver;
    [_orientationObserver setHandler:^(FBSOrientationUpdate *orientationUpdate) {
        // 方向回调可能来自工作队列，统一在主线程更新绘制状态。
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.touchVisualizationEnabled &&
                strongSelf->_orientationObserver == weakObserver &&
                orientationUpdate.sequenceNumber >= strongSelf->_globalSequenceNumber) {
                strongSelf->_globalSequenceNumber = orientationUpdate.sequenceNumber;
                strongSelf->_globalInterfaceOrientation = orientationUpdate.orientation;
            }
        });
    }];
}

// 启停整个渲染管线，停用时立即取消所有后续工作。
- (void)setTouchVisualizationEnabled:(BOOL)enabled {
    if (_touchVisualizationEnabled == enabled) {
        return;
    }
    _touchVisualizationEnabled = enabled;
    if (enabled) {
        [self startObservingOrientation];
    } else {
        [self resetTouchVisualization];
        [_orientationObserver setHandler:nil];
        if ([_orientationObserver respondsToSelector:@selector(invalidate)]) {
            [_orientationObserver invalidate];
        }
        _orientationObserver = nil;
    }
    [self reloadRootViewController];
}

// 清空触摸、动画及延迟清理，不创建覆盖窗口。
- (void)resetTouchVisualization {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    _fingerTipRemovalScheduled = NO;
    [_activeTouchViews removeAllObjects];
    for (LNTouchImageView *view in _renderedTouchViews.allObjects) {
        [view.layer removeAllAnimations];
        [view removeFromSuperview];
    }
    [_renderedTouchViews removeAllObjects];
    [self resetQuickPathTouches];
    _overlayWindow.hidden = YES;
    _overlayWindow.windowScene = nil;
    _overlayWindow = nil;
}

// 按实际启用状态创建或销毁轨迹界面。
- (void)reloadRootViewController {
    BOOL needsQuickPath = self.touchVisualizationEnabled && self.quickPathEnabled;
    if (needsQuickPath && !self.rootViewController) {
        self.rootViewController = [[TVZQuickPathViewController alloc] initWithNibName:nil bundle:nil];
    } else if (!needsQuickPath && self.rootViewController) {
        self.rootViewController = nil;
    }
}

// 关闭轨迹时立即清空轨迹模型和计时器。
- (void)setQuickPathEnabled:(BOOL)quickPathEnabled {
    if (_quickPathEnabled == quickPathEnabled) {
        return;
    }
    _quickPathEnabled = quickPathEnabled;
    if (!quickPathEnabled) {
        [self resetQuickPathTouches];
    }
    [self reloadRootViewController];
}

// 动态切换当前触点的形变动画。
- (void)setMorphEnabled:(BOOL)morphEnabled {
    if (_morphEnabled == morphEnabled) {
        return;
    }
    _morphEnabled = morphEnabled;
    for (LNTouchImageView *view in _activeTouchViews.objectEnumerator) {
        [view.layer removeAnimationForKey:LNTouchMorphAnimationKey];
        if (morphEnabled) {
            [self addMorphAnimationToTouchView:view];
        }
    }
}

// 更新触点配置并使图片缓存失效。
- (void)setTouchContactConfig:(LNTouchConfig *)touchContactConfig {
    _touchContactConfig = touchContactConfig;
    _touchImage = nil;
}

// 更新拖尾配置并使图片缓存失效。
- (void)setTouchRippleConfig:(LNTouchConfig *)touchRippleConfig {
    _touchRippleConfig = touchRippleConfig;
    _rippleImage = nil;
}

// 外观切换后按新颜色重新生成图片。
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
        _touchImage = nil;
        _rippleImage = nil;
    }
}

// 按需生成并缓存触点图片。
- (UIImage *)touchImage {
    if (_touchImage == nil) {
        _touchImage = [LNTouchImageFactory imageWithTouchConfig:self.touchContactConfig];
    }
    return _touchImage;
}

// 按需生成并缓存拖尾图片。
- (UIImage *)rippleImage {
    if (_rippleImage == nil) {
        _rippleImage = [LNTouchImageFactory imageWithTouchConfig:self.touchRippleConfig];
    }
    return _rippleImage;
}

// 将系统触摸坐标转换为覆盖窗口坐标。
- (CGPoint)locationOfTouch:(UITouch *)touch {
    UIInterfaceOrientation o = [self _windowInterfaceOrientation];
    UIWindow *overlayWindow = self.overlayWindow;
    CGRect fixedSpace = overlayWindow.screen.fixedCoordinateSpace.bounds;
    CGFloat fixedWidth = CGRectGetWidth(fixedSpace);
    CGFloat fixedHeight = CGRectGetHeight(fixedSpace);
    CGPoint a = [touch locationInView:nil];
    CGPoint b = a;
    switch (o) {
    case UIInterfaceOrientationPortrait:
        break;
    case UIInterfaceOrientationPortraitUpsideDown:
        a.x = fixedWidth - b.x;
        a.y = fixedHeight - b.y;
        break;
    case UIInterfaceOrientationLandscapeLeft:
        a.x = fixedHeight - b.y;
        a.y = b.x;
        break;
    case UIInterfaceOrientationLandscapeRight:
        a.x = b.y;
        a.y = fixedWidth - b.x;
        break;
    default:
        break;
    }
    return a;
}

// 合并窗口和前台界面的方向变换。
- (CGAffineTransform)coordinateTransform {
    CGAffineTransform affineTransform = CGAffineTransformIdentity;
    UIInterfaceOrientation windowOrientation = [self _windowInterfaceOrientation];
    switch (windowOrientation) {
    case UIInterfaceOrientationPortrait:
        break;
    case UIInterfaceOrientationPortraitUpsideDown:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(M_PI));
        break;
    case UIInterfaceOrientationLandscapeLeft:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(M_PI_2));
        break;
    case UIInterfaceOrientationLandscapeRight:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(-M_PI_2));
        break;
    default:
        break;
    }
    UIInterfaceOrientation orientation = self->_globalInterfaceOrientation;
    switch (orientation) {
    case UIInterfaceOrientationPortrait:
        break;
    case UIInterfaceOrientationPortraitUpsideDown:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(M_PI));
        break;
    case UIInterfaceOrientationLandscapeLeft:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(-M_PI_2));
        break;
    case UIInterfaceOrientationLandscapeRight:
        affineTransform = CGAffineTransformConcat(affineTransform, CGAffineTransformMakeRotation(M_PI_2));
        break;
    default:
        break;
    }
    return affineTransform;
}

// 仅在轨迹效果启用时转发触摸。
- (void)sendQuickPathEvent:(UIEvent *)event {
    if (self.touchVisualizationEnabled && self.quickPathEnabled) {
        [super sendQuickPathEvent:event];
    }
}

// 按触点直接查找视图，避免逐事件扫描整个视图树。
- (void)sendTouchEvent:(UIEvent *)event {
    if (!self.touchVisualizationEnabled || event.type != UIEventTypeTouches) {
        return;
    }

    CGAffineTransform coordinateTransform = self.coordinateTransform;
    NSTimeInterval eventTime = NSProcessInfo.processInfo.systemUptime;
    for (UITouch *touch in event.allTouches) {
        if (touch.type != UITouchTypeDirect) {
            continue;
        }
        UITouchPhase phase = touch.phase;
        if (phase != UITouchPhaseBegan && phase != UITouchPhaseMoved &&
            phase != UITouchPhaseStationary && phase != UITouchPhaseEnded &&
            phase != UITouchPhaseCancelled) {
            continue;
        }

        NSNumber *key = @(touch.hash);
        LNTouchImageView *touchView = _activeTouchViews[key];
        if (phase == UITouchPhaseStationary) {
            // 其它手指移动时，静止触点只刷新失联保护时间。
            touchView.timestamp = eventTime;
            continue;
        }
        if (phase == UITouchPhaseCancelled) {
            [self removeFingerTipForKey:key animated:YES];
            continue;
        }
        if (phase == UITouchPhaseEnded && touchView == nil) {
            continue;
        }

        CGPoint newCenter = [self locationOfTouch:touch];
        CGAffineTransform newTransform = coordinateTransform;
        if (self.touchContactConfig.shouldAutoRotate && touchView != nil) {
            CGFloat dx = newCenter.x - touchView.center.x;
            CGFloat dy = newCenter.y - touchView.center.y;
            if (dx * dx + dy * dy > 1.0) {
                newTransform = CGAffineTransformRotate(coordinateTransform, atan2(dy, dx) + M_PI_2);
            } else {
                newTransform = touchView.transform;
            }
        }

        if (touchView != nil) {
            [self addRippleForTouch:touch inView:touchView toCenter:newCenter withTransform:newTransform];
        } else {
            touchView = [[LNTouchImageView alloc] initWithImage:self.touchImage];
            touchView.userInteractionEnabled = NO;
            _activeTouchViews[key] = touchView;
            [_renderedTouchViews addObject:touchView];
            [self.overlayWindow addSubview:touchView];
            if (self.morphEnabled) {
                [self addMorphAnimationToTouchView:touchView];
            }
        }

        touchView.transform = newTransform;
        touchView.alpha = self.touchContactConfig.alpha;
        touchView.center = newCenter;
        touchView.timestamp = eventTime;
        if (phase == UITouchPhaseEnded) {
            [self removeFingerTipForKey:key animated:YES];
        }
    }
    [self scheduleFingerTipRemoval];
}

// 仅对可见位移生成拖尾，每个触点每屏幕帧最多一次。
- (void)addRippleForTouch:(UITouch *)touch
                  inView:(LNTouchImageView *)touchView
                toCenter:(CGPoint)newCenter
           withTransform:(CGAffineTransform)newTransform {
    if (!self.trackingEnabled || self.touchRippleConfig.fadeDuration <= 0.0 ||
        CGPointEqualToPoint(touchView.center, newCenter) ||
        touch.timestamp - touchView.lastRippleTimestamp < _rippleFrameInterval * 0.9) {
        return;
    }
    touchView.lastRippleTimestamp = touch.timestamp;
    LNTouchImageView *rippleView = [[LNTouchImageView alloc] initWithImage:self.rippleImage];
    rippleView.userInteractionEnabled = NO;
    rippleView.alpha = self.touchRippleConfig.alpha;
    rippleView.center = newCenter;
    rippleView.transform = newTransform;
    [_renderedTouchViews addObject:rippleView];
    [self.overlayWindow addSubview:rippleView];

    // 使用未旋转的尺寸计算缩放，避免自动旋转时拖尾尺寸波动。
    CGFloat scale = 1.0 / MAX(self.touchRippleConfig.radius, 1.0);
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:self.touchRippleConfig.fadeDuration
        delay:0.0
        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
        animations:^{
            rippleView.alpha = 0.0;
            rippleView.transform = CGAffineTransformScale(newTransform, scale, scale);
        }
        completion:^(BOOL finished) {
            [rippleView removeFromSuperview];
            [weakSelf removeRenderedTouchView:rippleView];
        }];
}

// 动画结束时释放视图索引。
- (void)removeRenderedTouchView:(LNTouchImageView *)view {
    [_renderedTouchViews removeObject:view];
}

// 只报告尚未抬起的触点。
- (BOOL)hasAnyTouch {
    return _activeTouchViews.count > 0;
}

// 首次绘制才创建独立覆盖窗口。
- (UIWindow *)overlayWindow {
    if (_overlayWindow == nil) {
        _overlayWindow = [[LNOverlayVisualizerWindow alloc] initWithFrame:self.frame];
        _overlayWindow.userInteractionEnabled = NO;
        _overlayWindow.windowLevel = CGFLOAT_MAX;
        _overlayWindow.backgroundColor = UIColor.clearColor;
        _overlayWindow.windowScene = self.windowScene;
        _overlayWindow.hidden = NO;
    }
    return _overlayWindow;
}

// 有活动触点时才安排一次超时保护，空闲时不轮询。
- (void)scheduleFingerTipRemoval {
    if (_activeTouchViews.count == 0) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeInactiveFingerTips) object:nil];
        _fingerTipRemovalScheduled = NO;
        return;
    }
    if (_fingerTipRemovalScheduled) {
        return;
    }
    NSTimeInterval earliest = DBL_MAX;
    for (LNTouchImageView *view in _activeTouchViews.objectEnumerator) {
        earliest = MIN(earliest, view.timestamp + TOUCH_VISUALIZER_WINDOW_REMOVE_DELAY);
    }
    _fingerTipRemovalScheduled = YES;
    NSTimeInterval delay = MAX(0.01, earliest - NSProcessInfo.processInfo.systemUptime);
    [self performSelector:@selector(removeInactiveFingerTips) withObject:nil afterDelay:delay
                  inModes:@[NSRunLoopCommonModes]];
}

// 清理系统未发送结束事件的触点，然后安排下一个真实截止时间。
- (void)removeInactiveFingerTips {
    _fingerTipRemovalScheduled = NO;
    if (!self.touchVisualizationEnabled) {
        return;
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    for (NSNumber *key in _activeTouchViews.allKeys) {
        if (now >= _activeTouchViews[key].timestamp + TOUCH_VISUALIZER_WINDOW_REMOVE_DELAY) {
            [self removeFingerTipForKey:key animated:YES];
        }
    }
    [self scheduleFingerTipRemoval];
}

// 抬手立即停止形变并释放活动触点，仅保留一次渐隐动画。
- (void)removeFingerTipForKey:(NSNumber *)key animated:(BOOL)animated {
    LNTouchImageView *view = _activeTouchViews[key];
    if (view == nil) {
        return;
    }
    [_activeTouchViews removeObjectForKey:key];
    [view.layer removeAnimationForKey:LNTouchMorphAnimationKey];
    NSTimeInterval duration = animated ? self.touchContactConfig.fadeDuration : 0.0;
    if (duration <= 0.0) {
        [view removeFromSuperview];
        [_renderedTouchViews removeObject:view];
        return;
    }
    CGFloat liftScale = self.touchContactConfig.liftScale;
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:duration
        delay:0.0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{
            view.alpha = 0.0;
            view.transform = CGAffineTransformScale(view.transform, liftScale, liftScale);
        }
        completion:^(BOOL finished) {
            [view removeFromSuperview];
            [weakSelf removeRenderedTouchView:view];
        }];
}

// 由合成器重复形变动画，避免主线程永久重复计时器。
- (void)addMorphAnimationToTouchView:(LNTouchImageView *)view {
    NSTimeInterval duration = self.touchContactConfig.morphDuration;
    if (duration <= 0.0) {
        return;
    }
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    animation.values = @[
        [NSValue valueWithCATransform3D:CATransform3DIdentity],
        [NSValue valueWithCATransform3D:CATransform3DMakeScale(1.0, 1.2, 1.0)],
        [NSValue valueWithCATransform3D:CATransform3DMakeScale(1.2, 0.9, 1.0)],
        [NSValue valueWithCATransform3D:CATransform3DMakeScale(0.9, 0.9, 1.0)],
        [NSValue valueWithCATransform3D:CATransform3DIdentity]
    ];
    animation.keyTimes = @[@0.0, @0.25, @0.5, @0.75, @1.0];
    animation.duration = duration;
    animation.additive = YES;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[animation];
    group.duration = MAX(duration, self.touchContactConfig.morphDelay);
    group.beginTime = [view.layer convertTime:CACurrentMediaTime() fromLayer:nil] +
        MAX(0.0, self.touchContactConfig.morphDelay);
    group.repeatCount = HUGE_VALF;
    [view.layer addAnimation:group forKey:LNTouchMorphAnimationKey];
}

// 允许窗口以系统覆盖层方式显示。
+ (BOOL)_isSystemWindow {
    return YES;
}

// 覆盖层不参与系统触摸命中测试。
- (BOOL)_ignoresHitTest {
    return YES;
}

// 保持原有安全窗口上下文属性。
- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}

@end
