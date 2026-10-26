ifeq ($(THEOS_DEVICE_SIMULATOR),1)
ARCHS := x86_64 arm64
TARGET := simulator:clang:latest:15.0
IPHONE_SIMULATOR_ROOT := $(shell ../devkit/sim-root.sh)
else
ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES := Preferences
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := TVZPrefs

TVZPrefs_FILES += $(wildcard *.mm)
TVZPrefs_FILES += $(wildcard *.swift)

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
TVZPrefs_FILES += ../libroot/dyn.c
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
TVZPrefs_LIBRARIES += roothide
endif

# 发布构建优先减小体积，保留现有架构和所有设置功能。
ifeq ($(DEBUG),0)
TVZPrefs_CFLAGS += -Oz
TVZPrefs_SWIFTFLAGS += -Osize
TVZPrefs_LDFLAGS += -Wl,-dead_strip
endif

TVZPrefs_CFLAGS += -fobjc-arc
TVZPrefs_CFLAGS += -I..
TVZPrefs_CFLAGS += -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\"

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
TVZPrefs_CFLAGS += -DIPHONE_SIMULATOR_ROOT=\"$(IPHONE_SIMULATOR_ROOT)\"
endif

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
TVZPrefs_LDFLAGS += -FFrameworks/_Simulator
TVZPrefs_LDFLAGS += -FFrameworks/_Simulator/MCEmojiPicker.xcframework/ios-arm64_x86_64-simulator -framework MCEmojiPicker
TVZPrefs_SWIFTFLAGS += -FFrameworks/_Simulator/MCEmojiPicker.xcframework/ios-arm64_x86_64-simulator -framework MCEmojiPicker
else
TVZPrefs_LDFLAGS += -FFrameworks
TVZPrefs_LDFLAGS += -FFrameworks/MCEmojiPicker.xcframework/ios-arm64_arm64e -framework MCEmojiPicker
TVZPrefs_SWIFTFLAGS += -FFrameworks/MCEmojiPicker.xcframework/ios-arm64_arm64e -framework MCEmojiPicker
endif

TVZPrefs_FRAMEWORKS += UIKit
TVZPrefs_PRIVATE_FRAMEWORKS += Preferences

TVZPrefs_SWIFT_BRIDGING_HEADER += TVZPrefs-Bridging-Header.h
TVZPrefs_INSTALL_PATH += /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
