#import "NSBundle+TVZPrefs.h"

#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUUID.h>
#import <HBLog.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && !TARGET_OS_SIMULATOR
#import <roothide.h>
#else
#import <libroot.h>
#endif

// 按当前打包方案转换资源路径，模拟器保留原有重定向。
static NSString *TVZJailbreakPath(NSString *path) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && !TARGET_OS_SIMULATOR
    return jbroot(path);
#else
    return JBROOT_PATH_NSSTRING(path);
#endif
}

@implementation NSBundle (TouchViz)

+ (NSBundle *)tvz_supportBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"TVZPrefs"
                                                                  ofType:@"bundle"];
      NSString *aliasBundlePath;
      aliasBundlePath = TVZJailbreakPath(@"/Library/PreferenceBundles/TVZPrefs.bundle");
      bundle = [NSBundle bundleWithPath:tweakBundlePath ?: aliasBundlePath];
#if TARGET_IPHONE_SIMULATOR
      if (!bundle) {
          aliasBundlePath = @"/opt/simject/PreferenceBundles/TVZPrefs.bundle";
          bundle = [NSBundle bundleWithPath:aliasBundlePath];
      }
#endif
      NSLog(@"[TouchViz] Support bundle path: %@", [bundle bundlePath]);
    });
    return bundle;
}

+ (NSString *)tvz_packageVersion {
    return @PACKAGE_VERSION;
}

+ (NSString *)tvz_fillImageRoot {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = TVZJailbreakPath(@"/var/mobile/Library/Touch-Viz");
#if DEBUG
      HBLogWarn(@"[Touch-Viz] Fill image root: %@", path);
#endif
    });
    return path;
}

+ (BOOL)tvz_ensureFillImageRoot {
    return [[NSFileManager defaultManager] createDirectoryAtPath:[self tvz_fillImageRoot]
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:nil];
}

+ (UIImage *)tvz_defaultFillImage {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      image = [UIImage imageNamed:@"default"
                       inBundle:[self tvz_supportBundle]
  compatibleWithTraitCollection:nil];
    });
    return image;
}

// 按路径和文件属性复用图片，切换文件或修改内容时重新加载。
+ (UIImage *)tvz_fillImageNamed:(NSString *)name {
    static NSString *gFillImagePath = nil;
    static NSDate *gLastModified = nil;
    static NSNumber *gFileSize = nil;
    static UIImage *gFillImage = nil;
    if (!name || [name isEqualToString:@"default.png"]) {
        gFillImagePath = nil;
        gLastModified = nil;
        gFileSize = nil;
        gFillImage = nil;
        return [self tvz_defaultFillImage];
    }
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:name];
    NSDictionary *imageAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:imagePath error:nil];
    NSDate *imageModified = imageAttrs[NSFileModificationDate];
    NSNumber *imageSize = imageAttrs[NSFileSize];
    if (gFillImage && [imagePath isEqualToString:gFillImagePath]
        && [imageModified isEqualToDate:gLastModified] && [imageSize isEqualToNumber:gFileSize]) {
        return gFillImage;
    }
    gFillImage = imageAttrs ? [UIImage imageWithContentsOfFile:imagePath] : nil;
    gFillImagePath = [imagePath copy];
    gLastModified = imageModified;
    gFileSize = imageSize;
    return gFillImage ?: [self tvz_defaultFillImage];
}

+ (NSString *)tvz_saveFillImageWithPath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *imageExt = [path pathExtension];
    NSString *imageName = [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString], imageExt];
    [self tvz_ensureFillImageRoot];
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
    [fileManager removeItemAtPath:imagePath error:nil];
    BOOL copied = [fileManager copyItemAtPath:path toPath:imagePath error:nil];
    [fileManager setAttributes:@{NSFileModificationDate : [NSDate date]} ofItemAtPath:imagePath error:nil];
    return copied ? imageName : nil;
}

+ (NSString *)tvz_saveFillImageWithImage:(UIImage *)image {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *imageName = [NSString stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]];
    [self tvz_ensureFillImageRoot];
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
    [fileManager removeItemAtPath:imagePath error:nil];
    BOOL wrote = [UIImagePNGRepresentation(image) writeToFile:imagePath atomically:YES];
    [fileManager setAttributes:@{NSFileModificationDate : [NSDate date]} ofItemAtPath:imagePath error:nil];
    return wrote ? imageName : nil;
}

+ (BOOL)tvz_removeAllFillImages {
    [[NSFileManager defaultManager] removeItemAtPath:[self tvz_fillImageRoot] error:nil];
    return [self tvz_ensureFillImageRoot];
}

@end
