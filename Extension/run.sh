#!/bin/bash

# 启用错误追踪
set -e

# 设置日志文件
LOG_FILE="/tmp/popclip_ai_tool.log"

# 记录日志的函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
log "脚本目录: $SCRIPT_DIR"

# 获取 PopClip 传递的文本
TEXT="$POPCLIP_TEXT"

# 获取 PopClip 动作标识符
ACTION_ID="$POPCLIP_ACTION_IDENTIFIER"

# 记录日志
log "PopClip 文本: $TEXT"
log "PopClip Action ID: $ACTION_ID"

# 检查可执行文件是否存在
AI_TOOL="$SCRIPT_DIR/AskPop"
if [ ! -f "$AI_TOOL" ]; then
    log "错误: 找不到 AI 工具可执行文件: $AI_TOOL"
    exit 1
fi
    
# 检查文件权限
if [ ! -x "$AI_TOOL" ]; then
    log "错误: AI 工具可执行文件没有执行权限"
    chmod +x "$AI_TOOL"
    log "已添加执行权限"
fi
    
# 根据 Action ID 选择提示词
if [ "$ACTION_ID" = "qa_action" ]; then
    PROMPT="$POPCLIP_OPTION_QA_PROMPT"
    log "使用问答提示词"
elif [ "$ACTION_ID" = "translate_action" ]; then
    PROMPT="$POPCLIP_OPTION_TRANSLATE_PROMPT"
    log "使用翻译提示词"
elif [ "$ACTION_ID" = "note_action" ]; then
    PROMPT="$POPCLIP_OPTION_NOTE_PROMPT"
    log "使用笔记提示词"
else
    PROMPT="$POPCLIP_BEFORE_TEXT"
    log "使用默认提示词"
fi
    
# 记录最终结果
log "提示词: $PROMPT"
log "用户文本: $TEXT"

# 使用 base64 编码来保留所有格式
ESCAPED_TEXT=$(echo -n "$TEXT" | base64)

# 在后台运行 AI 助手程序，并立即返回
# 设置环境变量
export POPCLIP_OPTION_APIKEY="$POPCLIP_OPTION_APIKEY"
export POPCLIP_OPTION_API_URL="$POPCLIP_OPTION_API_URL"
export POPCLIP_OPTION_MODEL="$POPCLIP_OPTION_MODEL"
export POPCLIP_OPTION_TEMPERATURE="$POPCLIP_OPTION_TEMPERATURE"
export POPCLIP_ACTION_IDENTIFIER="$ACTION_ID"

nohup "$AI_TOOL" "$PROMPT" "base64:$ESCAPED_TEXT" >> "$LOG_FILE" 2>&1 &

# 记录后台进程 ID
PID=$!
log "后台进程 ID: $PID"
log "-----------------------------------"

# 立即返回成功状态
exit 0 