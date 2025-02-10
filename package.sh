#!/bin/bash

echo "开始打包 PopClip 扩展..."

# 清理旧的构建文件
rm -rf .build

# 设置编译环境
export SDKROOT="$(xcrun --show-sdk-path --sdk macosx)"

# 编译程序
echo "编译程序..."
swift build -c release \
    -Xswiftc "-sdk" \
    -Xswiftc "$SDKROOT" \
    -Xswiftc "-target" \
    -Xswiftc "x86_64-apple-macosx13.0"

# 如果编译成功，继续打包步骤
if [ $? -eq 0 ]; then
    echo "编译成功，开始打包..."
    
    # 创建扩展目录
    EXTENSION_DIR="AskPop.popclipext"
    rm -rf "$EXTENSION_DIR"
    mkdir -p "$EXTENSION_DIR"
    
    # 复制文件
    cp Extension/Config.plist "$EXTENSION_DIR/"
    cp Extension/run.sh "$EXTENSION_DIR/"
    cp .build/release/AskPop "$EXTENSION_DIR/"
    
    # 设置权限
    chmod +x "$EXTENSION_DIR/run.sh"
    chmod +x "$EXTENSION_DIR/AskPop"
    chmod 644 "$EXTENSION_DIR/Config.plist"
    
    echo "打包完成！"
    echo "扩展目录：$EXTENSION_DIR"
else
    echo "编译失败"
    exit 1
fi