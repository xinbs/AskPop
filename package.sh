#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${BLUE}🔄 $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo -e "${BLUE}🚀 开始打包 AskPop PopClip 扩展...${NC}"

# 获取系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET_ARCH="arm64"
    BUILD_PATH=".build/arm64-apple-macosx/release"
    log "检测到 Apple Silicon (ARM64) 架构"
else
    TARGET_ARCH="x86_64"
    BUILD_PATH=".build/x86_64-apple-macosx/release"
    log "检测到 Intel (x86_64) 架构"
fi

# 清理旧的构建文件
log "清理旧的构建文件..."
rm -rf .build

# 设置编译环境
export SDKROOT="$(xcrun --show-sdk-path --sdk macosx)"
log "设置编译环境: $SDKROOT"

# 验证必要文件是否存在
log "验证项目文件..."
if [ ! -f "src/main.swift" ]; then
    error "找不到 src/main.swift 文件"
    exit 1
fi

if [ ! -f "Package.swift" ]; then
    error "找不到 Package.swift 文件"
    exit 1
fi

if [ ! -f "AskPop.popclipext/Config.plist" ]; then
    error "找不到 AskPop.popclipext/Config.plist 文件"
    exit 1
fi

# 验证 plist 文件语法
log "验证 Config.plist 文件语法..."
plutil -lint AskPop.popclipext/Config.plist
if [ $? -ne 0 ]; then
    error "Config.plist 语法错误"
    exit 1
fi
success "Config.plist 语法验证通过"

# 编译程序
log "编译程序 (目标架构: $TARGET_ARCH)..."
swift build -c release

# 检查编译结果
if [ $? -eq 0 ]; then
    success "编译成功"
    
    # 验证可执行文件是否存在
    EXECUTABLE_PATH="$BUILD_PATH/AskPop"
    if [ ! -f "$EXECUTABLE_PATH" ]; then
        error "找不到编译后的可执行文件: $EXECUTABLE_PATH"
        exit 1
    fi
    
    # 检查可执行文件架构
    log "检查可执行文件架构..."
    EXEC_ARCH=$(lipo -info "$EXECUTABLE_PATH" | grep "architecture" | awk '{print $NF}')
    log "可执行文件架构: $EXEC_ARCH"
    
    # 更新扩展目录
    EXTENSION_DIR="AskPop.popclipext"
    log "更新扩展目录: $EXTENSION_DIR"
    
    # 确保扩展目录存在
    if [ ! -d "$EXTENSION_DIR" ]; then
        error "扩展目录不存在: $EXTENSION_DIR"
        exit 1
    fi
    
    # 复制可执行文件
    log "复制可执行文件..."
    cp "$EXECUTABLE_PATH" "$EXTENSION_DIR/"
    
    # 代码签名 (解决 macOS 安全限制)
    log "对可执行文件进行代码签名..."
    codesign --force --sign - "$EXTENSION_DIR/AskPop"
    if [ $? -eq 0 ]; then
        success "代码签名完成"
    else
        warning "代码签名失败，但继续执行..."
    fi
    
    # 验证签名
    log "验证代码签名..."
    codesign -v "$EXTENSION_DIR/AskPop"
    if [ $? -eq 0 ]; then
        success "代码签名验证通过"
    else
        warning "代码签名验证失败，可能需要手动处理..."
    fi
    
    # 验证必要文件是否存在
    if [ ! -f "$EXTENSION_DIR/run.sh" ]; then
        error "找不到 run.sh 文件"
        exit 1
    fi
    
    if [ ! -f "$EXTENSION_DIR/AskPopLogo.png" ]; then
        warning "找不到 AskPopLogo.png 文件"
    fi
    
    # 设置权限
    log "设置文件权限..."
    chmod +x "$EXTENSION_DIR/run.sh"
    chmod +x "$EXTENSION_DIR/AskPop"
    chmod 644 "$EXTENSION_DIR/Config.plist"
    
    # 验证权限设置
    if [ ! -x "$EXTENSION_DIR/AskPop" ]; then
        error "可执行文件权限设置失败"
        exit 1
    fi
    
    # 创建发布包
    log "创建发布包..."
    
    # 先删除旧的压缩包
    [ -f "AskPop.zip" ] && rm "AskPop.zip"
    
    # 创建新的压缩包，包含所有相关文件
    zip -r AskPop.zip "$EXTENSION_DIR" *.md
    
    if [ $? -eq 0 ]; then
        success "发布包创建成功"
    else
        error "发布包创建失败"
        exit 1
    fi
    
    # 显示文件信息
    log "文件信息："
    echo "📁 扩展目录: $EXTENSION_DIR"
    echo "📦 发布包: AskPop.zip"
    echo "🏗️  架构: $TARGET_ARCH"
    echo "📋 扩展内容:"
    ls -la "$EXTENSION_DIR/"
    
    # 显示压缩包大小
    if [ -f "AskPop.zip" ]; then
        ZIP_SIZE=$(ls -lh AskPop.zip | awk '{print $5}')
        echo "📦 发布包大小: $ZIP_SIZE"
    fi
    
    echo ""
    success "🎉 打包完成！"
    echo ""
    echo "📋 安装步骤："
    echo "1. 确保 PopClip 已安装并运行"
    echo "2. 双击 $EXTENSION_DIR 文件夹"
    echo "3. 或者拖拽文件夹到 PopClip 图标上"
    echo "4. 在 PopClip 设置中配置 API 参数"
    echo ""
    echo "🛠 功能特性："
    echo "- ✨ AI 问答和翻译"
    echo "- 🎨 文本转公告图片"
    echo "- 📝 笔记管理集成"
    echo "- 🔄 Blinko 同步支持"
    echo ""
    
else
    error "编译失败"
    exit 1
fi