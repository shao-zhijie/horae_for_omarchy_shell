# 🦀 Horae for Omarchy：给 Arch / Omarchy 用户的终极心流 Todo & 番茄钟工具

> **大家好！我是 Horae 及其 Omarchy Shell 插件的作者。**  
> 在 Omarchy 这套极致优雅的平铺桌面系统里，我一直想要一个“不打扰心流、极致轻量、随叫随到”的待办与专注工具。试过各种 GUI / Web 应用后，总觉得不够契合 Arch / Omarchy 的极客美学，于是我自己动手写了 **Horae** 和配套的 **状态栏组件**。
>
> 很多群友在找趁手的任务管理和番茄钟，今天正式向群里新老 Omarchy 玩家安利这个项目！

---

## 📱 微信群快速分享版（点击右上方直接复制文本）

如果你需要在微信群直接发消息，可以直接复制以下精简版：

```text
👋 Omarchy 群里的小伙伴们好！分享一个我为 Omarchy 量身打造的 Todo & 番茄钟开源项目：Horae

一直觉得在 Omarchy 里缺少一个趁手、轻巧又不打扰心流的 GTD 工具，于是用 Rust 搓了这个项目，群友们可以体验一下～几个戳中痛点的特性：

🦀 1. 极致轻量：纯 Rust 编写，毫秒级响应，本地 SQLite 存储，告别 Electron 臃肿。
🎨 2. 颜值爆表：自带现代 TUI 界面，内嵌 23 套主流主题，完美随 Omarchy 系统主题联动变色！
🎙️ 3. 语音速记：打通 Omarchy Dictation，双手不离键盘或灵感闪现时，动嘴直接成待办。
⚡ 4. 剪贴板杀手锏（hcc）：复制网页/代码中的任意内容，终端敲一下 `hcc` 瞬间无感收录，全屏任意应用都是你的记事本！
🍅 5. 原生状态栏组件：精致的呼吸倒计时番茄钟 + GTD 流 + 贴心防窥隐私模式。

🔗 状态栏插件与安装：https://github.com/zhaohang1205/horae_for_omarchy_shell
🔗 Rust 核心仓库：https://github.com/zhaohang1205/horae

新老朋友欢迎尝鲜，有任何想法、Bug 或新功能建议欢迎随时在群里 @我 交流！🚀
```

---

## 📸 图文详解：Omarchy 上的最佳 Todo 实践

### 1. 🎨 23 套专属 TUI 皮肤：与 Omarchy 主题浑然天成

原生全键盘操作的 TUI 界面，内置 **23 款精心配色**（Catppuccin、Nord、Gruvbox、Tokyo Night 等）。**随 Omarchy 系统主题切换自动换肤**，也支持随时自由锁定配色。

![Horae TUI 终端主界面（现代暗黑主题）](docs/screenshots/screenshot-2026-10-24_22-19-37.png)
*▲ 图 1：Horae 现代终端 TUI 视图（支持今日、明日、收件箱、等待、排程等完整 GTD 流）*

![Horae TUI 终端主界面（随系统变动的中文配色主题）](docs/screenshots/screenshot-2026-10-24_22-20-27.png)
*▲ 图 2：随 Omarchy 主题自动匹配的高对比度中文 TUI 视图*

---

### 2. 🎙️ 联动 Omarchy Dictation：动动嘴皮，语音一秒记待办

深度打通 Omarchy 原生听写机制。双手正在敲代码、改配置腾不开时，唤出语音直接说出脑海中的想法，实时转化为 Todo 保存至收件箱！

![Omarchy 语音听写录入状态](docs/screenshots/screenshot-2026-10-24_22-21-00.png)
*▲ 图 3：配合 Alt+V 语音听写，说出灵感即可秒存 Todo*

---

### 3. ⚡ 神奇的剪贴板捕获（`hcc`）与闪念录入：全屏皆是记录主场

在浏览器、聊天工具或编辑器看到一段待办或报错，只需 `Ctrl+C` 复制，在终端敲 `hcc`（即 `horae capture --clip`）即可**无感捕获进收件箱**！

如果想手动输入闪念灵感，轻点状态栏或输入 `horae --flash`，弹窗支持智能语法解析（`*重复`、`~时间`、`!优先级`、`@标签`）与补全提示：

![快速录入闪念窗口](docs/screenshots/screenshot-2026-10-24_22-17-14.png)
*▲ 图 4：秒开闪念录入窗口（`horae --flash`），支持语法提示与 F8/Alt+V 语音联动*

![智能补全与周期解析](docs/screenshots/screenshot-2026-10-24_22-18-02.png)
*▲ 图 5：智能语法补全，敲入 `*d ~00:17 @home` 自动生成日常排程与分类标签*

---

### 4. 🍅 状态栏深度一体化：番茄钟专注流 + 一键操作面板

告别笨重的外部番茄钟。状态栏组件将番茄钟进度直接嵌入当前任务中，不占额外空间：

![状态栏番茄钟运行状态](docs/screenshots/screenshot-2026-10-24_22-16-03.png)
*▲ 图 6：状态栏无缝内嵌递减进度环与秒级倒计时（24:55），保持绝对心流*

点击状态栏项，即可唤出精致的专注与 GTD 任务操作台：

![番茄钟会话与任务操作面板](docs/screenshots/screenshot-2026-10-24_22-16-17.png)
*▲ 图 7：番茄钟控制台与任务快捷操作（完成 / 顺延1小时 / 归档 / 打开TUI）*

![GTD 即将到期任务列表](docs/screenshots/screenshot-2026-10-24_22-15-42.png)
*▲ 图 8：状态栏一览即将到期的任务流，支持今日完成度与连续打卡天数统计*

---

### 5. ⚙️ 番茄钟参数可视化微调

无需翻配置文件，点击齿轮即可展开 2×2 数字微调面板，随心设置专注与休息节奏：

![番茄钟配置微调面板](docs/screenshots/screenshot-2026-10-24_22-16-53.png)
*▲ 图 9：内置“经典25/5”、“深度50/10”、“冲刺15/3”预设，支持一键重置与本地即时同步*

---

### 6. 🔒 贴心隐私模式：防窥视，极客细节拉满

在公共场合、工位或屏幕共享时，鼠标悬停最左侧点击眼球图标即可一键开启隐私模式：**隐藏具体待办标题，仅显示时间与状态**，悬停时浮窗才对本人展示完整内容。

![状态栏隐私模式](docs/screenshots/screenshot-2026-10-24_22-14-51.png)
*▲ 图 10：开启隐私模式（Privacy Mode: On），状态栏仅显示时间，保护私人日程*

---

## 🚀 30 秒上手指北

### 步骤一：安装 Horae Rust 核心引擎
```bash
cargo install --git https://github.com/zhaohang1205/horae.git --tag v0.2.5
```

### 步骤二：推荐在 Shell 配置中加入 Alias（`~/.bashrc` 或 `~/.zshrc`）
```bash
alias h='horae'
alias hcc='horae capture --clip'
```

### 步骤三：一键安装 Omarchy Quattro 状态栏组件
```bash
git clone https://github.com/zhaohang1205/horae_for_omarchy_shell.git
cd horae_for_omarchy_shell
./install.sh
```

*(也可以通过官方命令行安装：`omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable`)*

---

## 🤝 欢迎交流与 Feedback

- **状态栏组件 GitHub**：[zhaohang1205/horae_for_omarchy_shell](https://github.com/zhaohang1205/horae_for_omarchy_shell)
- **Rust 核心引擎 GitHub**：[zhaohang1205/horae](https://github.com/zhaohang1205/horae)

这是一个由 Omarchy 深度用户写给 Omarchy 社区的工具。欢迎各位群友体验试用、提出意见或者提 PR，让我们的桌面环境更趁手、更高效！🌟
