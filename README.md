# luci-app-clawpanel

**OpenWrt / iStoreOS LuCI 管理插件 — ClawPanel 可视化面板**

通过 LuCI 网页后台，在 OpenWrt / iStoreOS 路由器上一键安装、启停、升级和卸载 ClawPanel（OpenClaw AI 助手管理面板）。

---

## 功能特性

| 功能 | 说明 |
|---|---|
| 📦 **一键安装** | 自动从 GitHub 下载 ClawPanel Pro 最新版 |
| ▶️ **启停管理** | 启动 / 停止 / 重启 ClawPanel 服务 |
| 🔄 **在线升级** | 检测 GitHub 最新版本，一键升级 |
| 🗑️ **完全卸载** | 清除程序、数据和 UCI 配置 |
| 📊 **状态监控** | 实时显示 PID、内存、运行时长、磁盘空间 |
| 🔒 **开机自启** | 注册系统服务，开机自动运行 |

---

## 系统要求

| 项目 | 要求 |
|---|---|
| 内存 | ≥ 256 MB |
| 磁盘空间 | ≥ 100 MB（**必须安装到外置存储**）|
| CPU 架构 | aarch64 / x86_64 / armv7l |
| 系统 | OpenWrt、iStoreOS、LEDE 及衍生固件 |

> ⚠️ **必须安装到外置存储**（如 `/mnt/sda1`、`/mnt/data`、`/storage`），禁止安装到系统分区（`/`、`/overlay`、`/opt` 等），否则数据会在重装后丢失。

---

## 安装前准备

**1. 挂载外置存储**

ClawPanel 必须安装在外置存储上。如果还没有挂载点：

```
LuCI → 系统 → 挂载点 → 挂载已连接的 USB 硬盘
```

**2. 下载 ipk 安装包**

从 GitHub Releases 页面下载对应架构的 ipk 文件：

👉 https://github.com/a10463981/luci-app-clawpanel/releases/latest

支持的架构：
- **aarch64**（ARM64）— 大部分现代路由器
- **x86_64**（Intel/AMD）— x86 软路由
- **armv7l**（ARM32）— 较老的 ARM 路由器

---

## 安装方式

### 方式一：OPKG 安装（推荐）

```bash
# 1. 将 ipk 文件上传到路由器（用 scp 或 U 盘）
scp luci-app-clawpanel_*.ipk root@192.168.1.1:/tmp/

# 2. SSH 登录路由器后执行安装
opkg install /tmp/luci-app-clawpanel_*.ipk

# 3. 重启 LuCI
/etc/init.d/luci reload
```

### 方式二：直接 git 克隆（无需编译）

适合路由器上有 git 的情况：

```bash
# SSH 登录路由器后执行
cd /tmp
git clone https://github.com/a10463981/luci-app-clawpanel.git
cd luci-app-clawpanel
chmod +x root/usr/bin/clawpanel-env
cp -r root/* /
/etc/init.d/luci reload
```

### 方式三：源码编译（开发者）

需要 OpenWrt SDK：

```bash
# 克隆到 SDK package 目录
git clone https://github.com/a10463981/luci-app-clawpanel.git \
  package/luci-app-clawpanel

# 编译
cd $SDK_DIR
make package/luci-app-clawpanel/compile V=s
```

---

## 使用方法

**1. 访问插件页面**

登录 LuCI → 顶部菜单 **服务** → **ClawPanel**

**2. 首次安装**

- 在「ClawPanel 安装路径」输入框填入外置存储挂载点，例如 `/mnt/sda1`
- 点击 **「安装 / 重装 ClawPanel」**
- 等待下载完成（视网络速度，通常 1-5 分钟）
- 安装成功后状态显示「**运行中**」

**3. 访问 ClawPanel 管理面板**

安装完成后，打开浏览器访问：

```
http://192.168.1.1:19527
```

默认管理员账号：**`admin`**  
默认管理员密码：**`clawpanel`**（建议首次登录后修改）

**4. 日常管理**

在 LuCI 的 ClawPanel 页面可以：
- **重启** — 重启 ClawPanel 服务（配置变更后需重启生效）
- **停止** — 停止 ClawPanel 服务
- **启动** — 启动 ClawPanel 服务
- **卸载** — 完全清除 ClawPanel 及所有数据

---

## 数据目录说明

| 目录 | 内容 |
|---|---|
| `{安装路径}/clawpanel/` | ClawPanel 程序二进制和版本文件 |
| `{安装路径}/clawpanel/data/` | 运行时数据（clawpanel.json 配置文件）|
| `{安装路径}/.openclaw/` | OpenClaw 引擎配置和插件数据 |

> 💡 重装 OpenWrt 系统后，只需重新安装本插件并指向同一挂载点，程序和数据会自动恢复。

---

## 目录结构

```
luci-app-clawpanel/
├── Makefile                         # OPKG 包定义
├── VERSION                          # 插件版本号
├── README.md                        # 中文说明
├── README_EN.md                     # English documentation
│
├── root/
│   ├── etc/
│   │   ├── config/clawpanel        # UCI 配置（enabled/port/install_path）
│   │   ├── init.d/clawpanel        # 系统服务启动脚本
│   │   └── uci-defaults/99-clawpanel  # 首次安装初始化
│   └── usr/bin/clawpanel-env       # 安装/升级/卸载核心脚本
│
└── luasrc/
    ├── controller/clawpanel.lua      # LuCI 路由 + 8个 API 端点
    ├── model/cbi/clawpanel/basic.lua  # CBI 表单入口
    └── view/clawpanel/             # HTML 模板
        ├── main.htm                 # 状态面板主页面
        ├── basic.htm                # CBI 渲染模板
        ├── status.htm               # 状态片段
        ├── basic_install.htm        # 安装对话框
        └── basic_uninstall.htm      # 卸载确认对话框
```

---

## 架构图

```
┌──────────────────────────────────────────────────────┐
│                   OpenWrt 路由器                       │
│                                                        │
│   ┌──────────────┐      ┌─────────────────────────┐ │
│   │ LuCI Web UI  │ ←──→ │ luci-app-clawpanel     │ │
│   │  (浏览器)     │ UCI  │  (Lua Controller)       │ │
│   └──────────────┘      └──────────┬──────────────┘ │
│                                    │                  │
│                      ┌─────────────▼──────────────┐  │
│                      │ clawpanel-env  (Shell)    │  │
│                      │  · 下载二进制              │  │
│                      │  · 写入配置               │  │
│                      │  · 启动服务               │  │
│                      └─────────────┬──────────────┘  │
│                                    │                  │
│   ┌────────────────────────────────▼────────────────┐│
│   │         ClawPanel  (:19527 + :19528)            ││
│   │  Go 单二进制，Web 面板 + REST API + React 前端   ││
│   │  数据目录: /mnt/sda1/clawpanel/data              ││
│   │  OpenClaw: /mnt/sda1/.openclaw                  ││
│   └─────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

---

## 相关链接

| 项目 | 地址 |
|---|---|
| **本插件 Releases** | https://github.com/a10463981/luci-app-clawpanel/releases |
| **ClawPanel 上游** | https://github.com/zhaoxinyi02/ClawPanel |
| **OpenClaw 引擎** | https://github.com/openclaw/openclaw |
| **问题反馈** | https://github.com/a10463981/luci-app-clawpanel/issues |

---

## 许可证

### 本插件
**CC BY-NC-SA 4.0**  
Copyright © 2025-2026 a10463981

- 署名 — 必须保留版权声明
- 非商业用途 — 禁止商业使用
- 相同方式共享 — 修改后须采用相同许可证

详细许可证：https://creativecommons.org/licenses/by-nc-sa/4.0/

### 上游项目

- **ClawPanel**：CC BY-NC-SA 4.0 — Copyright © zhaoxinyi02
- **OpenClaw**：自定义开源许可证 — Copyright © OpenClaw Authors

---

## 免责声明

本插件按原样提供，不提供任何明示或暗示的保证。使用本插件产生的任何风险由用户自行承担。

通过第三方客户端登录 QQ/微信 可能违反腾讯服务协议，存在封号风险，请使用小号测试。
