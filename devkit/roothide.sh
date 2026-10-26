#!/bin/sh

# 兼容两种常用安装目录，优先保留原有路径。
if [ -d "$HOME/theos-roothide" ] || [ ! -d "$HOME/theos_roothide" ]; then
    export THEOS="$HOME/theos-roothide"
else
    export THEOS="$HOME/theos_roothide"
fi
export THEOS_PACKAGE_SCHEME=roothide
export THEOS_DEVICE_IP=127.0.0.1
export THEOS_DEVICE_PORT=58422
export THEOS_DEVICE_SIMULATOR=
