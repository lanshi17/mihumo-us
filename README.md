# mihumo-us

> 一个自动筛选 Mihomo 配置中美国节点的工具脚本，让你的代理流量始终走美国出口。

## 简介

`mihumo-us` 通过解析你现有的 Mihomo（原 Clash Meta）YAML 配置文件，智能识别并筛选出所有美国节点，生成一个只包含美国节点代理组的新配置文件，并自动重启 Mihomo 服务使配置生效。

## 功能特性

- 🇺🇸 **智能识别美国节点**：支持严格匹配（国旗 🇺🇸、"美国"、"US-"、"United States"）和宽松匹配（"US"、城市名如 Los Angeles、New York、Dallas 等）
- 🔍 **自动排除非美国地区**：宽松匹配时，自动排除含 HK、JP、SG、TW、KR 等非美地区标签的节点
- 💾 **自动备份**：每次运行前自动备份当前配置，出错时自动恢复旧配置，保障服务不中断
- ✅ **语法验证**：利用 Mihomo 二进制的 `-t` 参数验证生成的配置文件语法正确性
- 🔄 **自动重启服务**：处理完成后通过 `systemctl` 自动重启 Mihomo 服务
- 📡 **出口 IP 验证**：重启后通过 `ipinfo.io` 验证当前出口 IP 是否为美国

## 文件结构

```
mihumo-us/
├── process_us_only.sh   # 主处理脚本
├── mihomo               # Mihomo 代理核心二进制文件
└── README.md
```

## 前置要求

- Linux 系统，并已将 Mihomo 配置为 systemd 服务（`systemctl restart mihomo`）
- Python 3，并安装 `pyyaml` 库：
  ```bash
  pip3 install pyyaml
  ```
- `curl`（用于出口 IP 验证）
- 已有 Mihomo 原始配置文件（含 `proxies` 字段）

## 快速开始

### 1. 上传原始配置文件

将你的 Mihomo 订阅配置文件上传或保存到：

```
~/mihomo/config_source.yaml
```

### 2. 运行脚本

```bash
chmod +x process_us_only.sh
./process_us_only.sh
```

### 3. 查看结果

脚本运行后会输出类似以下内容：

```
[2026-03-07 12:00:00] 🚀 开始处理本地文件...
[2026-03-07 12:00:00] 🧠 正在智能筛选美国节点...
[统计] 总节点: 200, 找到美国节点: 45 (严格:20, 宽松:25)
[2026-03-07 12:00:01] ✅ 语法验证通过
[2026-03-07 12:00:01] 🔄 重启 Mihomo 服务...
[2026-03-07 12:00:03] ✅ 验证成功：当前出口为美国 (US)
```

## 配置说明

脚本顶部的"用户配置区域"可根据实际情况修改：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `INPUT_FILE` | `~/mihomo/config_source.yaml` | 原始订阅配置文件路径 |
| `OUTPUT_FILE` | `~/.config/mihomo/config.yaml` | 输出（生效）配置文件路径 |
| `TARGET_GROUP_NAME` | `仅美国节点` | 生成的代理组名称 |
| `WORK_DIR` | `~/mihomo` | 工作目录（含 mihomo 二进制） |
| `BACKUP_DIR` | `~/.config/mihomo/backups` | 配置备份目录 |
| `LOG_FILE` | `~/mihomo/process_us_only.log` | 脚本运行日志路径 |

## 节点匹配规则

### 严格匹配（优先）

节点名称中包含以下任意关键词即视为美国节点：

- `🇺🇸`（美国国旗 Emoji）
- `美国`
- `US-`
- `United States`

### 宽松匹配

节点名称（不区分大小写）中包含以下任意关键词，且**不含**非美地区标签时，视为美国节点：

**城市/地区关键词：** `US`、`America`、`Los Angeles`、`New York`、`Dallas`、`Chicago`、`Silicon Valley`、`San Jose`、`Seattle`、`Phoenix`、`Miami`、`Denver`

**自动排除标签：** `HK`、`JP`、`SG`、`TW`、`KR`、`TH`、`VN`、`IN`、`UK`、`GB`、`DE`、`FR`、`CA`、`AU`、`NL`

## 生成的配置说明

脚本会在原配置基础上：

1. 新建一个名为 `仅美国节点`（可自定义）的 `select` 类型代理组，包含所有筛选出的美国节点
2. 将此代理组插入到 `proxy-groups` 列表首位
3. 移除原有的 `MATCH` / `FINAL` 规则，添加 `MATCH,仅美国节点` 作为最终规则，使所有流量走美国节点

## 错误恢复

若脚本在任何步骤失败（Python 处理出错、配置语法验证失败、服务重启失败），会自动：

1. 将 `~/.config/mihomo/backups/latest_backup.yaml` 恢复为当前配置
2. 重启 Mihomo 服务，保证网络连接不中断

## 日志

运行日志保存在 `~/mihomo/process_us_only.log`，可随时查看：

```bash
tail -f ~/mihomo/process_us_only.log
```

## 注意事项

- 若原始配置中使用旧版 Clash 的键名（`Proxy`、`Proxy Group`、`Rule`），脚本会自动兼容转换
- 若未找到任何美国节点，脚本会**中止操作**并保留原有配置，防止因配置为空而断网
- Mihomo 服务需通过 `systemd` 管理，脚本使用 `sudo systemctl restart mihomo` 重启服务

## License

MIT
