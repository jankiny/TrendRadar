#!/bin/bash
set -e

echo "═══════════════════════════════════════════"
echo "  🏆 员工获奖信息监控系统 - 启动中..."
echo "═══════════════════════════════════════════"

# 1. 确保目录存在
mkdir -p /app/config/custom/keyword

# 2. 从 employees.txt 自动生成关键词
if [ -f "/generate_keywords.sh" ]; then
    bash /generate_keywords.sh
else
    echo "⚠️ generate_keywords.sh 未找到，跳过"
fi

# 3. 调用 TrendRadar 原始入口脚本
echo "▶️ 启动 TrendRadar..."
exec /entrypoint.sh
