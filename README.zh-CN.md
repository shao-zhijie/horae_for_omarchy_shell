# Horae Tasks & Pomodoro

[English](README.md) | 简体中文

![Horae Tasks & Pomodoro](preview.png)

[Omarchy](https://omarchy.org/) Quattro 状态栏（bar）组件：将 [Horae](https://github.com/zhaohang1205/horae) 的即将到期 / 逾期 GTD 任务与番茄钟专注状态直接呈现在 bar 上，点击即可快捷操作，无需离开当前工作流或单独打开终端。

## 功能特性

- **闪念快速录入 (`+`)**：点击状态栏最左侧的 `+` 图标，立即在浮动终端中唤出 Horae 原生闪念录入窗口（`horae --flash`）。享受终端内完整的语法高亮、动态卡槽提示（`[*周期] [~时间] [!优先级] [@标签]`）与标签补全，敲击回车即可自动保存至收件箱并秒级退出！
- **即时任务流**：直接呈现由 Horae 引擎计算的即将到期与逾期任务窗口。
- **番茄钟专注指示**：正在番茄钟专注的任务会自动用 🍅 固定到最前，并带动态呼吸闪烁与秒级倒计时。
- **一键快捷操作面板**：点击状态栏任务项展开操作面板：
  - 🍅 **开启番茄钟**：直接在该任务上启动番茄钟。
  - ⏱️ **延迟 1h**：将任务日程顺延 1 小时。
  - ✅ **完成**：标记任务已完成（正在专注时自动停用番茄钟）。
  - 📦 **归档**：将任务软删除归档。
  - ⚡ **+ 闪念录入**：面板内快捷拉起 `horae --flash`。
  - 🖥️ **打开 TUI**：一键进入 Horae TUI 终端全功能面板。
- **悬停跑马灯**：标题超出宽度时，悬停鼠标自动平滑横向滚动，平时保持沉浸简洁。
- **TUI 深度联动**：右击番茄钟图标可直接唤出或聚焦 Horae TUI 终端窗口（`omarchy-launch-or-focus-tui horae`）；双击停止番茄钟。
- **原生双语支持**：自动跟随系统环境切换中英文界面，亦可在配置中强制指定。
- **事件驱动极低开销**：通过文件监听 `horae.db` 与 `pomo.json`，实现毫秒级即时同步与无轮询低能耗。

## 前置依赖

- Omarchy Quattro shell
- 已安装 [Horae](https://github.com/zhaohang1205/horae) CLI 工具：
  ```bash
  cargo install --git https://github.com/zhaohang1205/horae.git
  ```

## 安装

```bash
omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable
```

## 状态栏位置调整

将组件移动到状态栏的中部或右侧：

```bash
omarchy bar move io.github.zhaohang1205.horae-tasks --section center
```

或者在 `~/.config/omarchy/shell.json` 的 `bar.layout` 中进行配置：

```json
{
  "id": "io.github.zhaohang1205.horae-tasks",
  "maxWidth": 420
}
```

## 设置选项

可以在 `~/.config/omarchy/shell.json` 针对该组件项配置以下参数：

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `horaeBin` | string | `"~/.cargo/bin/horae"` | `horae` 可执行文件路径 |
| `dataDir` | string | `"~/.config/horae"` | 存放 `pomo.json` 与 `horae.db` 的数据目录 |
| `profile` | string | `""` | 指定 Horae profile 数据集 |
| `limit` | number | `10` | 查询候选任务数上限 |
| `displayMax` | number | `2` | 状态栏同时展示的任务数量 |
| `maxWidth` | number | `420` | 组件在状态栏上的最大逻辑像素宽度 |
| `alwaysShow` | boolean | `true` | 无待办任务时是否常驻显示 `+` 录入按钮 |
| `textColor` | string | `""` | 自定义文本颜色（默认继承状态栏前景色） |
| `lang` | string | `""` | 语言设置（`"zh"` 或 `"en"`，留空自动检测系统语言） |

## Quattro Shell 指令

支持通过 Omarchy Quattro shell 命令行唤出或收起面板：

```bash
omarchy-shell shell summon io.github.zhaohang1205.horae-tasks '{}'
omarchy-shell shell hide io.github.zhaohang1205.horae-tasks
```

## 卸载

```bash
omarchy plugin remove io.github.zhaohang1205.horae-tasks
```

## 开源许可

[MIT](LICENSE) © 2026 alex zhao
