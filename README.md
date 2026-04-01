# luci-app-clawpanel

**OpenWrt / iStoreOS LuCI 插件 — ClawPanel 管理面板**

在 OpenWrt、iStoreOS 等基于 LuCI 的路由器系统上，通过网页后台直接管理 ClawPanel 的安装、升级、启停和卸载。

---

## 功能特性

- 📦 **一键安装** — 自动从 GitHub 下载 ClawPanel 最新版，支持指定版本
- 🔍 **安装前检测** — 自动检测内存（≥256MB）和磁盘空间（≥500MB）是否满足要求
- ▶️ **进程管理** — 启动 / 停止 / 重启 ClawPanel 服务
- 🔄 **在线升级** — 检测 GitHub 最新版本，一键升级
- 🗑️ **完全卸载** — 清除程序、数据和配置
- 📊 **状态面板** — 实时显示运行状态、PID、内存占用、运行时长、端口、磁盘空间
- 🔒 **开机自启** — 自动注册 procd 服务，开机自动运行

---

## 系统要求

| 项目 | 最低要求 |
|---|---|
| 内存 | ≥ 256 MB |
| 磁盘可用空间 | ≥ 500 MB（**必须安装到外置存储**） |
| CPU 架构 | x86_64 / aarch64 / armhf |
| 系统 | OpenWrt、iStoreOS、LEDE 及衍生固件 |

> ⚠️ **重要**：ClawPanel **必须安装到外置存储挂载点**（如 `/mnt/sda1`、`/mnt/data`、`/storage` 等），**不允许**安装到系统分区（`/`、`/overlay`、`/opt` 等）。系统分区空间有限，且重装 OpenWrt 后数据会全部丢失。

---

## 安装前提

> ⚠️ **安装前请先挂载外置存储**（USB 硬盘、SATA 盘等）。
> ClawPanel 将拒绝安装到系统分区（`/overlay`、`/opt` 等），以防止数据丢失。
>
> 如未挂载外部存储，请先在 **LuCI → 系统 → 挂载点** 中配置挂载。

## 安装方式

### 方式一：OPKG 安装（推荐）

```bash
# 下载 ipk 并上传到路由器
opkg install luci-app-clawpanel_*.ipk
```

### 方式二：源码编译（放入 OpenWrt SDK）

```bash
# 克隆到 SDK package 目录
git clone https://github.com/a10463981/luci-app-clawpanel.git \
  package/luci-app-clawpanel

# 编译
make package/luci-app-clawpanel/compile
```

### 方式三：直接克隆到 /overlay

```bash
git clone https://github.com/a10463981/luci-app-clawpanel.git /tmp/luci-app-clawpanel
cp -r /tmp/luci-app-clawpanel/luasrc /usr/lib/lua/luci/
cp -r /tmp/luci-app-clawpanel/root/* /
chmod +x /etc/init.d/clawpanel /usr/bin/clawpanel-env
/etc/init.d/clawpanel enable
```

---

## 使用方法

1. 登录 LuCI 管理后台（通常是 `http://192.168.1.1`）
2. 顶部菜单 → **服务** → **ClawPanel**
3. 首次使用：
   - 点击 **「安装/重装」** 按钮
   - 页面会自动检测已挂载的外置存储（USB 硬盘等）
   - **选择其中一个挂载点**（推荐第一个，即可用空间最大的）
   - ⚠️ **禁止**安装到 `/overlay`、`/opt` 等系统分区
4. 确认后等待安装完成
5. 安装完成后，访问 **http://路由器IP:19527** 进入 ClawPanel 管理面板
6. 默认账号：`admin`，默认密码：`clawpanel`

---

> 📌 **数据安全提示**：ClawPanel 程序和数据均存放在你选择的外置存储挂载点中。重装 OpenWrt 系统后只需重新安装本插件，程序和数据会自动保留在原位置（只要挂载点不变）。

---

## 界面预览

```
LuCI → 服务 → ClawPanel
├── 🐙 ClawPanel 服务状态          ← 实时状态面板（5s 刷新）
│   ├── 运行状态 / 进程 PID / 内存占用 / 运行时长
│   ├── ClawPanel 版本 / OpenClaw 版本 / 端口
│   └── 安装路径 / 剩余空间
│
├── [📦 安装/重装] [🔄 重启] [⏹ 停止] [▶ 启动] [🔍 检测升级] [🗑 卸载]
│
└── 💡 快捷入口
    └── 首次安装指引 / 访问地址提示
```

---

## 工作原理

```
┌──────────────────────────────────────────────────────┐
│                   OpenWrt 路由器                     │
│                                                       │
│  ┌────────────────┐      ┌──────────────────────┐   │
│  │  LuCI Web UI   │      │  luci-app-clawpanel  │   │
│  │  (浏览器用户)   │ ←──→ │  (Lua Controller)    │   │
│  └────────────────┘ UCI  └──────────┬───────────┘   │
│                                       │               │
│  ┌────────────────────────────────────▼────────────┐ │
│  │         ClawPanel (:19527)                      │ │
│  │  /api/status   /api/process/start|stop|restart  │ │
│  │  Go + React 单二进制，静态编译                    │ │
│  └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

LuCI App 本身只做 **UI 嫁接**：读取 UCI 配置、调用 `clawpanel-env` 脚本执行安装/卸载、通过 curl 调用 ClawPanel REST API 获取状态。所有复杂业务逻辑由 ClawPanel 自身处理。

---

## 目录结构

```
luci-app-clawpanel/
├── Makefile                          # OPKG 包编译入口
├── README.md                         # 本文件
├── VERSION                           # 插件版本号
│
├── root/
│   ├── etc/
│   │   ├── config/clawpanel         # UCI 配置（enabled/port/install_path）
│   │   ├── init.d/clawpanel         # procd 启动脚本
│   │   └── uci-defaults/99-clawpanel # 首次安装初始化
│   └── usr/bin/clawpanel-env        # 安装/升级/卸载脚本
│
└── luasrc/
    ├── controller/clawpanel.lua      # LuCI 路由 + 所有 API
    ├── model/cbi/clawpanel/basic.lua # CBI 表单 + 内嵌 JS 交互
    └── view/clawpanel/status.htm    # 状态面板模板
```

---

## 相关项目

| 项目 | 地址 |
|---|---|
| **ClawPanel 上游** | https://github.com/zhaoxinyi02/ClawPanel |
| OpenClaw 引擎 | https://github.com/openclaw/openclaw |

---

## 版权说明

### 本插件

**CC BY-NC-SA 4.0**  
Copyright © 2025-2026 a10463981  
允许在以下条件下自由使用、修改和分发：
- **署名**（必须保留上游版权声明）
- **非商业用途**（禁止商业使用）
- **相同方式共享**（若修改本作品，则必须采用相同的许可证发布）

详细许可证全文：https://creativecommons.org/licenses/by-nc-sa/4.0/

---

### 上游 ClawPanel 版权

本插件基于 [ClawPanel](https://github.com/zhaoxinyi02/ClawPanel) 开发，ClawPanel 同样采用 **CC BY-NC-SA 4.0** 许可证。

> ClawPanel is an OpenClaw intelligent management panel.  
> **Copyright © zhaoxinyi02** — All rights reserved.  
> Licensed under CC BY-NC-SA 4.0.

ClawPanel 免责声明：https://github.com/zhaoxinyi02/ClawPanel/blob/main/DISCLAIMER.md

---

### OpenClaw 版权

OpenClaw 为 ClawPanel 的核心引擎，Copyright © OpenClaw Authors。

---

## 免责声明

本插件按原样提供，不提供任何明示或暗示的保证。使用本插件产生的任何风险由用户自行承担。

本插件基于 OpenClaw / ClawPanel 上游项目构建，使用第三方客户端登录 QQ/微信 可能违反腾讯服务协议，存在封号风险，请使用小号测试。

---

## 提交问题

如有问题或建议，请前往 GitHub Issues：  
https://github.com/a10463981/luci-app-clawpanel/issues
