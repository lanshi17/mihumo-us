#!/bin/bash

# ================= 用户配置区域 =================
# 1. 你上传的原始配置文件路径 (绝对路径)
INPUT_FILE="$HOME/mihomo/config_source.yaml"

# 2. 最终生效的配置文件路径 (通常 Mihomo 读取这里)
OUTPUT_FILE="$HOME/.config/mihomo/config.yaml"

# 3. 目标代理组名称
TARGET_GROUP_NAME="仅美国节点"

# 4. 工作目录
WORK_DIR="$HOME/mihomo"
BACKUP_DIR="$HOME/.config/mihomo/backups"
LOG_FILE="$WORK_DIR/process_us_only.log"
# ===============================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "❌ 错误: $1"
    # 如果出错且有备份，尝试恢复
    if [ -f "$BACKUP_DIR/latest_backup.yaml" ]; then
        log "⚠️ 正在恢复旧配置..."
        cp "$BACKUP_DIR/latest_backup.yaml" "$OUTPUT_FILE"
        sudo systemctl restart mihomo
        log "✅ 已恢复旧配置，服务未中断。"
    fi
    exit 1
}

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    error_exit "找不到输入文件: $INPUT_FILE (请确认文件已上传)"
fi

log "🚀 开始处理本地文件..."
log "📂 源文件: $INPUT_FILE"
log "🎯 目标文件: $OUTPUT_FILE"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份当前正在使用的配置
if [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" "$BACKUP_DIR/latest_backup.yaml"
    cp "$OUTPUT_FILE" "$BACKUP_DIR/backup_$(date +%F_%H%M).yaml"
    log "✅ 已备份当前运行配置。"
fi

# 执行 Python 处理逻辑
log "🧠 正在智能筛选美国节点..."
export INPUT_FILE="$INPUT_FILE"
export OUTPUT_FILE="$OUTPUT_FILE"
export TARGET_GROUP_NAME="$TARGET_GROUP_NAME"
python3 << 'PYTHON_SCRIPT'
import yaml
import sys
import os

input_file = os.environ.get('INPUT_FILE')
output_file = os.environ.get('OUTPUT_FILE')
target_group = os.environ.get('TARGET_GROUP_NAME', '仅美国节点')

# 匹配规则
strict_keywords = ["🇺🇸", "美国", "US-", "United States"]
loose_keywords = ["US", "America", "Los Angeles", "New York", "Dallas", "Chicago", "Silicon Valley", "San Jose", "Seattle", "Phoenix", "Miami", "Denver"]

def is_us_node(name):
    if not isinstance(name, str):
        return False, None
    
    # 严格匹配
    for kw in strict_keywords:
        if kw in name:
            return True, "Strict"
    
    # 宽松匹配
    name_upper = name.upper()
    for kw in loose_keywords:
        if kw.upper() in name_upper:
            # 排除非美地区
            exclude_tags = ["HK", "JP", "SG", "TW", "KR", "TH", "VN", "IN", "UK", "GB", "DE", "FR", "CA", "AU", "NL"]
            if not any(ex in name_upper for ex in exclude_tags):
                return True, "Loose"
    return False, None

try:
    with open(input_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)

    if not isinstance(config, dict):
        raise ValueError("配置文件格式错误：根节点必须是字典")

    # 标准化键名 (兼容旧版 Clash)
    key_map = {'Proxy': 'proxies', 'Proxy Group': 'proxy-groups', 'Rule': 'rules'}
    for old_key, new_key in key_map.items():
        if old_key in config and new_key not in config:
            config[new_key] = config.pop(old_key)

    proxies = config.get('proxies', [])
    if not isinstance(proxies, list):
        raise ValueError("'proxies' 字段不是列表")

    log_msg_prefix = f"[统计]"
    us_nodes = []
    strict_count = 0
    loose_count = 0

    for p in proxies:
        if not isinstance(p, dict):
            continue
        name = p.get('name', '')
        is_us, method = is_us_node(name)
        if is_us:
            us_nodes.append(name)
            if method == "Strict":
                strict_count += 1
            else:
                loose_count += 1

    total = len(proxies)
    found = len(us_nodes)
    print(f"{log_msg_prefix} 总节点: {total}, 找到美国节点: {found} (严格:{strict_count}, 宽松:{loose_count})")

    if found == 0:
        print("⚠️ 警告: 未找到任何美国节点！")
        print("样本节点名称:", [p.get('name') for p in proxies[:5]])
        # 如果没有找到节点，我们选择不覆盖配置，防止断网
        raise ValueError("未找到美国节点，操作中止以保护网络。")

    # 构建新的代理组
    new_group = {
        'name': target_group,
        'type': 'select',  # 手动选择，方便调试，也可改为 url-test
        'proxies': us_nodes
    }

    # 处理 proxy-groups
    groups = config.get('proxy-groups', [])
    # 移除同名的旧组
    config['proxy-groups'] = [g for g in groups if isinstance(g, dict) and g.get('name') != target_group]
    # 插入新组到第一位
    config['proxy-groups'].insert(0, new_group)

    # 处理 Rules
    rules = config.get('rules', [])
    # 移除所有 MATCH 或 FINAL 规则
    clean_rules = []
    for r in rules:
        r_str = str(r)
        if not (r_str.startswith('MATCH') or r_str.startswith('FINAL')):
            clean_rules.append(r)
    
    # 添加默认规则：所有流量走“仅美国节点”组
    clean_rules.append(f'MATCH,{target_group}')
    config['rules'] = clean_rules

    # 写入新配置
    with open(output_file, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False, default_flow_style=False)

    print(f"✅ 配置已成功生成: {output_file}")

except Exception as e:
    print(f"❌ Python 处理失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT

# 检查 Python 执行结果
if [ $? -ne 0 ]; then
    error_exit "Python 脚本执行失败"
fi

# 验证配置语法
log "🔍 验证配置语法..."
if [ -x "$WORK_DIR/mihomo" ]; then
    if ! "$WORK_DIR/mihomo" -t -f "$OUTPUT_FILE" > /dev/null 2>&1; then
        error_exit "生成的配置文件语法错误 (mihomo -t 验证失败)"
    fi
    log "✅ 语法验证通过"
else
    log "⚠️ 未找到 mihomo 二进制，跳过语法验证"
fi

# 重启服务
log "🔄 重启 Mihomo 服务..."
if sudo systemctl restart mihomo; then
    log "🎉 成功！服务已重启。"
    
    # 简单的 IP 验证
    sleep 2
    log "🔍 验证出口 IP..."
    IP_INFO=$(curl -x http://127.0.0.1:7890 -s --connect-timeout 5 https://ipinfo.io/json 2>/dev/null)
    if echo "$IP_INFO" | grep -q '"country": "US"'; then
        log "✅ 验证成功：当前出口为美国 (US)"
        echo "$IP_INFO" | grep -E '"ip"|"country"|"city"'
    else
        log "⚠️ 提示：IP 检测未显示 US。可能是节点延迟高、被墙或规则未生效。请手动检查。"
        echo "$IP_INFO" | head -n 5
    fi
else
    error_exit "systemctl restart mihomo 失败"
fi

log "🏁 流程结束"
