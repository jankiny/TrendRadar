#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 员工/公司名单 → TrendRadar 关键词配置 自动生成脚本
#
# 用途：容器启动时自动运行，从 employees.txt 生成关键词配置文件
#       放入 config/custom/keyword/ 目录，TrendRadar 会自动加载
#
# 输入：/app/config/employees.txt（每行一个姓名或公司名）
# 输出：/app/config/custom/keyword/employees_keywords.txt
# ═══════════════════════════════════════════════════════════════

EMPLOYEES_FILE="/app/config/employees.txt"
OUTPUT_DIR="/app/config/custom/keyword"
OUTPUT_FILE="$OUTPUT_DIR/employees_keywords.txt"

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$EMPLOYEES_FILE" ]; then
    echo "⚠️ employees.txt 不存在 ($EMPLOYEES_FILE)，跳过员工关键词生成"
    exit 0
fi

# 检查文件是否为空
if [ ! -s "$EMPLOYEES_FILE" ]; then
    echo "⚠️ employees.txt 为空，跳过员工关键词生成"
    exit 0
fi

echo "📋 正在从 employees.txt 生成员工关键词配置..."

# 写入文件头
cat > "$OUTPUT_FILE" << 'HEADER'
# ═══════════════════════════════════════════════════════════════
#      员工/公司获奖监控 - 关键词（自动生成，请勿手动修改）
#      由 generate_keywords.sh 在容器启动时从 employees.txt 生成
# ═══════════════════════════════════════════════════════════════

[WORD_GROUPS]

HEADER

total=0
current_prefix=""
group_count=0

# 按首字分组
while IFS= read -r name || [ -n "$name" ]; do
    # 清理：去回车、去首尾空白
    name=$(echo "$name" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # 跳过空行和注释
    [ -z "$name" ] && continue
    [[ "$name" == \#* ]] && continue

    # 提取首字（支持中文和英文）
    prefix=$(echo "$name" | cut -c1)

    # 新的首字 → 开始新组
    if [ "$prefix" != "$current_prefix" ]; then
        if [ -n "$current_prefix" ]; then
            echo "" >> "$OUTPUT_FILE"
        fi
        current_prefix="$prefix"
        group_count=$((group_count + 1))
        echo "[监控-${prefix}]" >> "$OUTPUT_FILE"
    fi

    echo "$name" >> "$OUTPUT_FILE"
    total=$((total + 1))
done < "$EMPLOYEES_FILE"

echo "✅ 已生成员工关键词: ${total} 个词条, ${group_count} 个分组"
echo "   输出文件: $OUTPUT_FILE"
