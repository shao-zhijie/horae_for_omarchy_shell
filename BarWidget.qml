import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.zhaohang1205.horae-tasks"

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string defaultDataDir: (Quickshell.env("XDG_CONFIG_HOME") || (homeDir + "/.config")) + "/horae"
  readonly property string dataDir: setting("dataDir", defaultDataDir)

  readonly property string cargoHoraeBin: homeDir !== "" ? (homeDir + "/.cargo/bin/horae") : ""
  readonly property string horaeBin: {
    var custom = String(setting("horaeBin", "")).trim()
    if (custom !== "") return custom
    return cargoHoraeBin !== "" ? cargoHoraeBin : "horae"
  }

  readonly property string profile: String(setting("profile", "")).trim()
  readonly property int alarmLimit: Math.max(1, Math.min(20, Number(setting("limit", 10))))
  readonly property int displayMax: Math.max(1, Math.min(5, Number(setting("displayMax", 2))))
  readonly property int windowBackMs: 10 * 3600 * 1000
  readonly property int windowFwdMs: 24 * 3600 * 1000
  readonly property int maxBarWidth: Math.max(160, Math.round(Style.space(Number(setting("maxWidth", 420)))))
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color textColor: {
    var c = setting("textColor", "")
    return c && String(c).trim() !== "" ? c : fg
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alwaysShow: Boolean(setting("alwaysShow", true))
  readonly property int autoDismissSecs: Math.max(0, Number(setting("autoDismiss", 15)))

  // Language management with toggle support and persistence
  property string currentLang: {
    var l = String(setting("lang", "")).toLowerCase().trim()
    if (l.indexOf("zh") === 0) return "zh"
    if (l.indexOf("en") === 0) return "en"
    var horaeLang = (Quickshell.env("HORAE_LANG") || "").toLowerCase().trim()
    if (horaeLang === "en") return "en"
    if (horaeLang === "zh") return "zh"
    var env = (Quickshell.env("LANG") || "").toLowerCase()
    if (env.indexOf("zh") === 0) return "zh"
    return "zh"
  }

  readonly property bool isChinese: currentLang === "zh"

  function toggleLanguage() {
    var next = currentLang === "zh" ? "en" : "zh"
    currentLang = next
    var sql = "INSERT INTO settings (key, val) VALUES ('lang', '" + next + "') ON CONFLICT(key) DO UPDATE SET val='" + next + "';"
    var cmd = "sqlite3 " + shellArg(root.dataDir + "/horae.db") + " " + shellArg(sql)
    if (bar) bar.run(cmd)
    refreshTimer.restart()
  }

  // Privacy Mode: only expose first character (CJK) or first word (English)
  property bool privacyMode: Boolean(setting("privacyMode", false))

  function togglePrivacyMode() {
    privacyMode = !privacyMode
    var val = privacyMode ? "1" : "0"
    var sql = "INSERT INTO settings (key, val) VALUES ('privacy_mode', '" + val + "') ON CONFLICT(key) DO UPDATE SET val='" + val + "';"
    var cmd = "sqlite3 " + shellArg(root.dataDir + "/horae.db") + " " + shellArg(sql)
    if (bar) bar.run(cmd)
  }

  function maskTitle(title) {
    if (!title) return ""
    var s = String(title).trim()
    if (s.length === 0) return ""
    var cjkMatch = s.match(/^([\u4e00-\u9fa5\u3400-\u4dbf\uf900-\ufaff])/);
    if (cjkMatch) {
      return s.length > 1 ? cjkMatch[1] + "…" : cjkMatch[1];
    }
    var prefixMatch = s.match(/^([^\w\s\u4e00-\u9fa5]+)?([\u4e00-\u9fa5]|\w+)/);
    if (prefixMatch) {
      var prefix = prefixMatch[1] || "";
      var core = prefixMatch[2] || "";
      var exposed = prefix + core;
      return s.length > exposed.length ? exposed + "…" : exposed;
    }
    var wordMatch = s.match(/^(\S+)/);
    if (wordMatch) {
      var w = wordMatch[1];
      return s.length > w.length ? w + "…" : w;
    }
    return s.charAt(0) + "…";
  }

  // ---------------------------------------------------------------------------
  // Pomodoro session state — synced from ~/.config/horae/pomo.json (written by
  // the horae pomo daemon). Countdown/progress are derived locally every tick,
  // so no per-second process spawn is needed.
  // ---------------------------------------------------------------------------
  property string pomoPhase: "idle" // idle | work | short_break | long_break
  property string pomoTaskId: ""
  property string pomoTaskTitle: ""
  property double pomoStartTs: 0
  property double pomoEndTs: 0
  property int pomoCycle: 0
  property int pomoTotalCount: 0
  property int pomoTodayCount: 0
  property int pomoStreak: 0

  // Live countdown, refreshed by pomoTickTimer (pure local math)
  property int pomoRemainingSecs: 0
  property real pomoRemainingFraction: 0 // 1 → phase just started, 0 → phase over

  readonly property bool pomoRunning: pomoPhase !== "idle"
  readonly property bool pomoWorking: pomoPhase === "work"
  readonly property bool pomoBreaking: pomoRunning && !pomoWorking
  readonly property string workingTaskId: pomoTaskId

  // Instrument colors: focus = urgent, breaks = accent, idle = plain
  readonly property color phaseColor: !pomoRunning ? textColor : pomoWorking ? urgent : accent

  // Pomodoro configuration (synced to pomo.json config block)
  property bool showPomoSettings: false
  property int pomoWorkMins: 25
  property int pomoShortBreakMins: 5
  property int pomoLongBreakMins: 15
  property int pomoLongBreakInterval: 4

  property bool _savingPomoConfig: false
  Timer {
    id: savingPomoTimer
    interval: 1000
    onTriggered: root._savingPomoConfig = false
  }

  function updatePomoTick() {
    if (!pomoRunning || pomoEndTs <= 0) {
      pomoRemainingSecs = 0
      pomoRemainingFraction = 0
      return
    }
    var now = Date.now()
    var total = pomoEndTs - pomoStartTs
    pomoRemainingSecs = Math.max(0, Math.ceil((pomoEndTs - now) / 1000))
    pomoRemainingFraction = total > 0 ? Math.max(0, Math.min(1, (pomoEndTs - now) / total)) : 0
  }

  // Canonical phase names: idle | work | short_break | long_break.
  // pomo.json (serde rename_all="lowercase") spells breaks "shortbreak" /
  // "longbreak", while `pomo waybar` uses "short_break" / "long_break".
  function normalizePhase(raw) {
    var p = String(raw || "idle").toLowerCase().replace(/[_\s-]/g, "")
    if (p === "work" || p === "working") return "work"
    if (p === "shortbreak") return "short_break"
    if (p === "longbreak") return "long_break"
    return "idle"
  }

  function applyPomoState(state) {
    if (!state || typeof state !== "object") return
    pomoPhase = normalizePhase(state.phase)
    pomoTaskId = String(state.task_id || "")
    pomoTaskTitle = String(state.task_title || "")
    pomoStartTs = Number(state.start_ts || 0)
    pomoEndTs = Number(state.end_ts || 0)
    pomoCycle = Number(state.cycle || 0)
    pomoTotalCount = Number(state.total_count || 0)
    pomoTodayCount = Number(state.today_count || 0)
    pomoStreak = Number(state.streak || 0)
    updatePomoTick()
    buildDisplayTasks()
  }

  function applyPomoFile(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || typeof data !== "object") return
      applyPomoState(data)
      if (!_savingPomoConfig && data.config) {
        if (data.config.work_mins) pomoWorkMins = Number(data.config.work_mins)
        if (data.config.short_break_mins) pomoShortBreakMins = Number(data.config.short_break_mins)
        if (data.config.long_break_mins) pomoLongBreakMins = Number(data.config.long_break_mins)
        if (data.config.long_break_interval) pomoLongBreakInterval = Number(data.config.long_break_interval)
      }
    } catch (e) {}
  }

  // Fallback parser for `horae pomo waybar` output (used only when pomo.json
  // is unavailable); maps its class/text payload back onto the session state.
  function applyPomo(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (!parsed || typeof parsed !== "object") return
      pomoPhase = normalizePhase(parsed.class)
      pomoTaskId = String(parsed.id || "")
      pomoTaskTitle = String(parsed.title || "")
      var m = String(parsed.text || "").match(/(\d+):(\d+)\s*$/)
      if (m && pomoPhase !== "idle") {
        var secs = Number(m[1]) * 60 + Number(m[2])
        pomoEndTs = Date.now() + secs * 1000
        pomoStartTs = pomoEndTs - Math.max(1, secs) * 1000
      } else {
        pomoStartTs = 0
        pomoEndTs = 0
      }
      updatePomoTick()
      buildDisplayTasks()
    } catch (error) {}
  }

  function savePomoConfig(w, s, l, i) {
    _savingPomoConfig = true
    savingPomoTimer.restart()
    pomoWorkMins = Math.max(1, Math.min(180, w))
    pomoShortBreakMins = Math.max(1, Math.min(60, s))
    pomoLongBreakMins = Math.max(1, Math.min(90, l))
    pomoLongBreakInterval = Math.max(1, Math.min(12, i))
    var dataFile = root.dataDir + "/pomo.json"
    var jqCmd = "[ -f " + shellArg(dataFile) + " ] || echo '{}' > " + shellArg(dataFile) + " ; " +
      "jq --argjson w " + pomoWorkMins + " --argjson s " + pomoShortBreakMins + " --argjson l " + pomoLongBreakMins + " --argjson i " + pomoLongBreakInterval +
      " '.config = ((.config // {}) + {\"work_mins\": $w, \"short_break_mins\": $s, \"long_break_mins\": $l, \"long_break_interval\": $i})' " +
      shellArg(dataFile) + " > " + shellArg(dataFile + ".tmp") + " && cat " + shellArg(dataFile + ".tmp") + " > " + shellArg(dataFile) + " && rm -f " + shellArg(dataFile + ".tmp")
    if (bar && typeof bar.run === "function") {
      bar.run(jqCmd)
    } else {
      Quickshell.execDetached(["bash", "-c", jqCmd])
    }
  }

  function resetPomoConfigToDefault() {
    savePomoConfig(25, 5, 15, 4)
  }

  // ---------------------------------------------------------------------------
  // Pomodoro presentation helpers
  // ---------------------------------------------------------------------------
  function pad2(value) { return (value < 10 ? "0" : "") + value }

  function formatCountdown(secs) {
    var s = Math.max(0, Math.round(secs))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    return h > 0 ? (h + ":" + pad2(m) + ":" + pad2(sec)) : (pad2(m) + ":" + pad2(sec))
  }

  function phaseLabel() {
    if (pomoPhase === "work") return i18n("专注中", "Focus")
    if (pomoPhase === "short_break") return i18n("短休", "Short break")
    if (pomoPhase === "long_break") return i18n("长休", "Long break")
    return i18n("空闲", "Idle")
  }

  // Dots toward the next long break: `cycle` completed pomodoros since the last
  // long rest (horae resets it on stop / across days).
  readonly property int cycleDotsFilled: {
    var interval = Math.max(1, pomoLongBreakInterval)
    if (pomoCycle <= 0) return 0
    return pomoCycle % interval === 0 ? interval : pomoCycle % interval
  }

  function displayPomoText() {
    if (!pomoRunning) return "🍅"
    var t = formatCountdown(pomoRemainingSecs)
    if (privacyMode) return t
    var title = String(pomoTaskTitle || "")
    if (title === "") return t
    if (title.length > 14) title = title.substring(0, 14) + "…"
    return t + " " + title
  }

  function pomoTooltipText() {
    var lines = []
    var title = String(pomoTaskTitle || "")
    if (title !== "") lines.push(title)
    var head = phaseLabel()
    if (pomoRunning) head += " · " + formatCountdown(pomoRemainingSecs)
    lines.push(head)
    lines.push(i18n("今日 " + pomoTodayCount + " · 连续 " + pomoStreak + " · 累计 " + pomoTotalCount,
                    "Today " + pomoTodayCount + " · Streak " + pomoStreak + " · Total " + pomoTotalCount))
    lines.push(i18n("左击快速录入，右击打开 TUI，双击停止",
                    "Left-click: Quick capture, Right-click: TUI, Double-click: Stop"))
    return lines.join("\n")
  }

  function i18n(zh, en) {
    return isChinese ? zh : en
  }

  // Shell panel lifecycle contract (Quattro standard)
  readonly property bool opened: popupOpen
  readonly property bool popoutSwitchClosing: false

  function open() {
    popupOpen = true
    if (displayTasks.length > 0 && selectedTaskId === "") {
      selectedTaskId = String(displayTasks[0].id)
    }
  }

  function close() {
    popupOpen = false
    showPomoSettings = false
  }

  function toggle() {
    if (popupOpen) close()
    else open()
  }

  function closeForPopoutSwitch() {
    close()
  }

  // Launch Horae in flash capture mode (horae --flash) inside a floating terminal
  function launchFlashCapture() {
    if (!bar) return
    var fullCmd = ["omarchy-launch-tui", "--app-id=org.omarchy.horae-flash"].concat(command(["--flash"]))
    bar.run(fullCmd.map(shellArg).join(" "))
    popupOpen = false
  }

  // Launch or focus full Horae TUI
  function openTui() {
    if (!bar) return
    bar.run("omarchy-launch-or-focus-tui horae")
    popupOpen = false
  }

  property var tasks: []
  property var displayTasks: []
  property string selectedTaskId: ""
  property bool popupOpen: false

  readonly property var selectedTask: (function() {
    for (var i = 0; i < displayTasks.length; i++)
      if (String(displayTasks[i].id) === selectedTaskId) return displayTasks[i]
    return null
  })()

  readonly property real capsuleHeight: Math.max(22, root.barSize - Style.space(6))
  readonly property int taskSlotWidth: displayTasks.length === 0 ? 0
    : Math.max(48, Math.floor((maxBarWidth - Style.space(90)) / displayTasks.length))

  visible: alwaysShow || displayTasks.length > 0 || pomoRunning
  implicitWidth: capsuleContainer.width + Style.space(4)
  implicitHeight: barSize

  readonly property bool revealPrivacyBtn: widgetHover.hovered || capsuleHover.hovered || (privacyBtnItem && privacyBtnItem.hovering) || (pomoItem && pomoItem.hovering) || root.popupOpen
  readonly property bool revealPomoItem: pomoRunning || displayTasks.length === 0 || widgetHover.hovered || capsuleHover.hovered || (pomoItem && pomoItem.hovering) || (privacyBtnItem && privacyBtnItem.hovering) || root.popupOpen
  readonly property bool tooltipHovered: widgetHover.hovered || capsuleHover.hovered

  HoverHandler {
    id: widgetHover
  }

  function command(args) {
    var result = [horaeBin]
    if (profile !== "") result.push("--profile", profile)
    return result.concat(args)
  }

  function taskTime(task) {
    if (!task) return 0
    return Number(task.due || task.due_at || task.scheduled_start_at || 0)
  }

  function isPending(task) {
    if (!task) return false
    var status = String(task.status || "").toLowerCase()
    return status !== "done" && status !== "archived"
  }

  function taskClass(task) {
    if (!task) return "alarm-none"
    if (task.class) return String(task.class)
    var due = taskTime(task)
    if (due <= 0) return "alarm-none"
    var now = Date.now()
    if (due < now) return "alarm-overdue"
    if (due <= now + 5 * 60 * 1000) return "alarm-now"
    return "alarm-none"
  }

  function inWindow(task) {
    if (!isPending(task)) return false
    var due = taskTime(task)
    var now = Date.now()
    return due > 0 && due >= now - windowBackMs && due <= now + windowFwdMs
  }

  function isOverdue(task) {
    if (!task) return false
    return taskClass(task) === "alarm-overdue"
  }

  function isUrgent(task) {
    if (!task) return false
    var c = taskClass(task)
    return c === "alarm-now" || c === "alarm-overdue"
  }

  function taskIcon(task) {
    if (!task) return "⏰"
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return "🍅"
    return taskClass(task) === "alarm-now" ? "🔔" : "⏰"
  }

  function isStartTime(task) {
    if (!task) return false
    if (task.time_type === "start" || task.is_start === true) return true
    if (task.time_type === "due" || task.is_start === false) return false
    if (task.scheduled_start_at && !task.due_at) return true
    if (String(task.status || "").toLowerCase() === "scheduled") return true
    return false
  }

  function timeLabel(task) {
    return isStartTime(task) ? i18n("计划开始", "Start") : i18n("截止", "Due")
  }

  function taskStatus(task) {
    if (!task) return ""
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return i18n("专注中", "Focusing")
    var c = taskClass(task)
    var isStart = isStartTime(task)
    if (c === "alarm-overdue") return isStart ? i18n("已到时间", "Past start") : i18n("已逾期", "Overdue")
    if (c === "alarm-now") return isStart ? i18n("即将开始", "Starting soon") : i18n("即将到期", "Due soon")
    if (String(task.status || "").toLowerCase() === "scheduled") return i18n("已排程", "Scheduled")
    return i18n("待办", "Todo")
  }

  function statusColor(task) {
    if (!task) return root.dim
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return root.accent
    return isUrgent(task) ? root.urgent : root.dim
  }

  function formatDue(ms) {
    if (!ms) return "-"
    var date = new Date(Number(ms))
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" +
      pad2(date.getDate()) + " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  }

  function formatDueTime(ms) {
    if (!ms) return ""
    var date = new Date(Number(ms))
    if (isNaN(date.getTime())) return ""
    return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  }

  function formatTimeArg(ms) {
    return formatDue(ms)
  }

  function applyTasks(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      tasks = Array.isArray(parsed) ? parsed : []
      tasks = tasks.filter(function(t) { return t && t.class && t.class !== "alarm-none" })
    } catch (error) {
      tasks = []
    }
    buildDisplayTasks()
  }

  function displayKey(task) {
    return String(task.id) + "|" + taskTime(task) + "|" +
      (isUrgent(task) ? 1 : 0) + "|" +
      (isOverdue(task) ? 1 : 0) + "|" +
      (workingTaskId !== "" && String(task.id) === workingTaskId ? 1 : 0)
  }

  function buildDisplayTasks() {
    var candidates = tasks.filter(inWindow).slice()
    candidates.sort(function(a, b) { return taskTime(a) - taskTime(b) })
    var focused = null
    if (workingTaskId !== "") {
      focused = candidates.filter(function(task) { return String(task.id) === workingTaskId })[0]
    }
    if (!focused && pomoTaskTitle) {
      focused = candidates.filter(function(task) { return String(task.title) === String(pomoTaskTitle) })[0]
    }
    if (focused) {
      candidates = candidates.filter(function(task) { return task !== focused })
      candidates.unshift(focused)
    }
    var next = candidates.slice(0, displayMax)
    if (next.length === displayTasks.length) {
      var same = true
      for (var i = 0; i < next.length; i++) {
        if (displayKey(next[i]) !== displayKey(displayTasks[i])) { same = false; break }
      }
      if (same) return
    }
    displayTasks = next
  }

  function openPopupFor(task) {
    if (!task) return
    var id = String(task.id)
    if (popupOpen && selectedTaskId === id) {
      close()
      return
    }
    selectedTaskId = id
    showPomoSettings = false
    popupOpen = true
  }

  function runTaskAction(args, keepOpen) {
    if (bar) bar.run(command(args).map(shellArg).join(" "))
    if (!keepOpen) popupOpen = false
    refreshTimer.restart()
    pomoRefreshTimer.restart()
  }

  function stopWorkingPomoIfSelected() {
    if (workingTaskId !== "" && selectedTask && String(selectedTask.id) === workingTaskId) {
      if (bar) bar.run(command(["pomo", "stop"]).map(shellArg).join(" "))
      pomoRefreshTimer.restart()
    }
  }

  function shellArg(value) {
    var text = String(value)
    return "'" + text.replace(/'/g, "'\\''") + "'"
  }

  function startSelected() {
    var task = selectedTask
    if (!task && displayTasks.length > 0) task = displayTasks[0]
    if (!task) return
    // Keep the popup open so the gauge lights up immediately
    runTaskAction(["pomo", "start", String(task.id)], true)
  }

  function deferSelected() {
    if (!selectedTask) return
    var due = taskTime(selectedTask)
    var target = due >= Date.now() ? due + 3600000 : Date.now() + 3600000
    if (isStartTime(selectedTask)) {
      runTaskAction(["schedule", String(selectedTask.id), "--start", formatTimeArg(target)])
    } else {
      runTaskAction(["modify", String(selectedTask.id), "--due", formatTimeArg(target)])
    }
  }

  function completeSelected() {
    if (selectedTask) {
      stopWorkingPomoIfSelected()
      runTaskAction(["done", String(selectedTask.id)])
    }
  }

  function archiveSelected() {
    if (selectedTask) {
      stopWorkingPomoIfSelected()
      runTaskAction(["archive", String(selectedTask.id)])
    }
  }

  function stopPomo() {
    if (bar) bar.run(command(["pomo", "stop"]).map(shellArg).join(" "))
    pomoRefreshTimer.restart()
  }

  // Progress ring gauge (used in the bar and the popup session panel)
  component PomoRing: Shape {
    id: ringShape
    property real progress: 1 // 1 → full arc, 0 → empty (depleting gauge)
    property color ringColor: root.accent
    property color trackColor: Util.alpha(root.fg, 0.16)
    property real strokeW: Style.space(2)

    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    readonly property real ringRadius: Math.max(0, width / 2 - strokeW / 2)

    ShapePath {
      strokeWidth: ringShape.strokeW
      strokeColor: ringShape.trackColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: ringShape.width / 2
        centerY: ringShape.height / 2
        radiusX: ringShape.ringRadius
        radiusY: ringShape.ringRadius
        startAngle: -90
        sweepAngle: 360
      }
    }

    ShapePath {
      // ShapePath has no `visible`; hide the progress arc by making its
      // stroke transparent once the phase is (nearly) spent.
      strokeWidth: ringShape.strokeW
      strokeColor: ringShape.progress > 0.004 ? ringShape.ringColor : "transparent"
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      Behavior on strokeColor {
        ColorAnimation { duration: 250 }
      }
      PathAngleArc {
        centerX: ringShape.width / 2
        centerY: ringShape.height / 2
        radiusX: ringShape.ringRadius
        radiusY: ringShape.ringRadius
        startAngle: -90
        sweepAngle: Math.max(0.001, 360 * Math.max(0, Math.min(1, ringShape.progress)))
      }
    }
  }

  onVisibleChanged: if (!visible) popupOpen = false

  // Pill / Capsule shape container for the whole bar widget
  Rectangle {
    id: capsuleContainer
    anchors.centerIn: parent
    height: root.capsuleHeight
    width: Math.min(root.maxBarWidth, row.implicitWidth + Style.space(16))
    radius: height / 2
    color: root.pomoRunning ? Util.alpha(root.phaseColor, 0.10) : (capsuleHover.hovered ? Util.alpha(root.fg, 0.10) : Util.alpha(root.fg, 0.05))
    border.width: 1
    border.color: root.pomoRunning ? Util.alpha(root.phaseColor, 0.35) : (capsuleHover.hovered ? Util.alpha(root.fg, 0.22) : Util.alpha(root.fg, 0.10))
    clip: true

    Behavior on width {
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on color {
      ColorAnimation { duration: 180 }
    }
    Behavior on border.color {
      ColorAnimation { duration: 180 }
    }

    HoverHandler {
      id: capsuleHover
    }

    Row {
      id: row
      x: (capsuleContainer.width - width) / 2
      y: (capsuleContainer.height - height) / 2
      spacing: Style.space(4)

      // Privacy Mode Toggle Button on Bar (revealed on hover)
      Item {
        id: privacyBtnItem
        readonly property bool hovering: privacyMouse.containsMouse
        readonly property bool tooltipHovered: visible && opacity > 0 && privacyMouse.containsMouse
        readonly property real targetWidth: privacyBtnText.implicitWidth + Style.space(12)
        implicitWidth: root.revealPrivacyBtn ? targetWidth : 0
        width: implicitWidth
        implicitHeight: root.capsuleHeight
        visible: width > 0.5
        clip: true
        opacity: root.revealPrivacyBtn ? 1.0 : 0.0

        Behavior on implicitWidth {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 160 }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          radius: height / 2
          color: privacyBtnItem.hovering ? Util.alpha(root.accent, 0.18) : (root.privacyMode ? Util.alpha(root.accent, 0.10) : "transparent")
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
          id: privacyBtnText
          anchors.centerIn: parent
          text: root.privacyMode ? "󰈉" : "󰈈"
          color: privacyMouse.containsMouse ? root.accent : (root.privacyMode ? root.accent : root.textColor)
          opacity: root.privacyMode ? 1.0 : (privacyMouse.containsMouse ? 1.0 : 0.65)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: privacyMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePrivacyMode()
          onEntered: if (root.bar) root.bar.showTooltip(privacyBtnItem, root.privacyMode ?
            root.i18n("状态栏隐私模式: 开启 (点击关闭)", "Privacy Mode: ON (Click to turn off)") :
            root.i18n("状态栏隐私模式: 关闭 (点击开启)", "Privacy Mode: OFF (Click to turn on)"))
          onExited: if (root.bar) root.bar.hideTooltip(privacyBtnItem)
        }
      }

      Repeater {
        id: barRepeater
        model: root.displayTasks
        delegate: taskDelegate
      }

      // 无待办任务时的保底番茄钟/灵感录入入口（有待办任务时番茄钟已深度集成进各任务项自身）
      Item {
        id: pomoItem
        visible: root.displayTasks.length === 0 && width > 0.5
        readonly property bool hovering: pomoMouse.containsMouse
        readonly property bool tooltipHovered: visible && opacity > 0 && pomoMouse.containsMouse
        readonly property real targetWidth: pomoRow.implicitWidth + Style.space(12)
        implicitWidth: (root.displayTasks.length === 0 && root.revealPomoItem) ? targetWidth : 0
        width: implicitWidth
        implicitHeight: root.capsuleHeight
        clip: true
        opacity: (root.displayTasks.length === 0 && root.revealPomoItem) ? 1.0 : 0.0

        Behavior on implicitWidth {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 160 }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          radius: height / 2
          color: pomoItem.hovering ? Util.alpha(root.pomoRunning ? root.phaseColor : root.fg, 0.12) : (root.pomoRunning ? Util.alpha(root.phaseColor, 0.08) : "transparent")
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        Row {
          id: pomoRow
          x: (pomoItem.width - width) / 2
          y: (pomoItem.height - height) / 2
          spacing: Style.space(5)

          Item {
            id: barRing
            visible: root.pomoRunning
            width: visible ? Style.space(16) : 0
            height: width
            anchors.verticalCenter: parent.verticalCenter

            PomoRing {
              anchors.fill: parent
              progress: root.pomoRemainingFraction
              ringColor: root.phaseColor
              trackColor: Util.alpha(root.fg, 0.25)
              strokeW: Style.space(2)
            }
          }

          Text {
            id: pomoText
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayPomoText()
            color: root.pomoRunning ? root.phaseColor : root.textColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
            Behavior on color {
              ColorAnimation { duration: 200 }
            }
          }

          SequentialAnimation on opacity {
            running: root.pomoRunning
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.78; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.78; to: 1.0; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) pomoRow.opacity = 1.0
          }
        }

        MouseArea {
          id: pomoMouse
          property double lastDoubleClickTime: 0
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
              if (Date.now() - lastDoubleClickTime < 350) return
              pomoClickTimer.restart()
            } else if (mouse.button === Qt.RightButton) {
              pomoClickTimer.stop()
              root.openTui()
            }
          }
          onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
              lastDoubleClickTime = Date.now()
              pomoClickTimer.stop()
              root.stopPomo()
            }
          }
          onEntered: if (root.bar) root.bar.showTooltip(pomoItem, root.pomoTooltipText())
          onExited: if (root.bar) root.bar.hideTooltip(pomoItem)
        }
      }
    }
  }

  Component {
    id: taskDelegate
    Item {
      id: taskItem
      property var task: modelData
      property bool hovering: false
      readonly property bool tooltipHovered: visible && opacity > 0 && taskMouse.containsMouse
      readonly property bool urgentTask: root.isUrgent(task)
      readonly property bool overdueTask: root.isOverdue(task)
      readonly property bool working: root.workingTaskId !== "" && String(task.id) === root.workingTaskId
      readonly property string timeStr: working ? root.formatCountdown(root.pomoRemainingSecs) : root.formatDueTime(root.taskTime(task))

      // Content measurements
      readonly property real fixedW: taskIconSlot.width + (taskTimeText.visible ? taskTimeText.implicitWidth + taskContentRow.spacing : 0)
      readonly property real titleMaxW: root.privacyMode ? 0 : Math.max(0, root.taskSlotWidth - fixedW - Style.space(12))
      readonly property real clipTitleW: root.privacyMode ? 0 : Math.min(titleText.implicitWidth, titleMaxW)

      implicitWidth: fixedW + (root.privacyMode ? 0 : (clipTitleW > 0 ? clipTitleW + taskContentRow.spacing : 0)) + Style.space(12)
      implicitHeight: root.capsuleHeight

      Rectangle {
        anchors.fill: parent
        anchors.topMargin: Style.space(2)
        anchors.bottomMargin: Style.space(2)
        radius: height / 2
        color: taskItem.hovering ? Util.alpha(taskItem.working ? root.accent : root.fg, 0.12) : (taskItem.working ? Util.alpha(root.accent, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
      }

      Row {
        id: taskContentRow
        anchors.centerIn: parent
        spacing: Style.space(5)

        // 1. 图标区：正在专注时直接显示微型动态 PomoRing 环；否则显示任务静态图标
        Item {
          id: taskIconSlot
          width: taskItem.working ? Style.space(16) : taskIconText.implicitWidth
          height: taskItem.working ? Style.space(16) : taskIconText.implicitHeight
          anchors.verticalCenter: parent.verticalCenter

          // 微型动态进度圆环（仅在专注该任务时激活）
          Item {
            anchors.fill: parent
            visible: taskItem.working

            PomoRing {
              anchors.fill: parent
              progress: root.pomoRemainingFraction
              ringColor: root.phaseColor
              trackColor: Util.alpha(root.fg, 0.22)
              strokeW: Style.space(2)
            }

            SequentialAnimation on opacity {
              running: taskItem.working && root.pomoRunning
              loops: Animation.Infinite
              NumberAnimation { from: 1.0; to: 0.75; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.75; to: 1.0; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
              onRunningChanged: if (!running) opacity = 1.0
            }
          }

          // 常规图标（非专注时显示）
          Text {
            id: taskIconText
            visible: !taskItem.working
            anchors.centerIn: parent
            text: root.taskIcon(taskItem.task)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // 2. 时间/倒计时区：专注时显示实时倒计时，否则显示计划时间
        Text {
          id: taskTimeText
          visible: taskItem.timeStr !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: taskItem.timeStr
          color: taskItem.working ? root.phaseColor : (taskItem.urgentTask ? root.urgent : root.textColor)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: taskItem.working
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 200 } }
        }

        // 3. 标题文本（隐私模式下隐藏，超出时支持平滑跑马灯）
        Item {
          id: titleClip
          visible: !root.privacyMode && taskItem.clipTitleW > 0
          width: taskItem.clipTitleW
          height: root.capsuleHeight
          clip: true
          anchors.verticalCenter: parent.verticalCenter

          Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: String(taskItem.task.title || "(untitled)")
            color: taskItem.working ? root.accent : (taskItem.urgentTask ? root.urgent : root.textColor)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: taskItem.working
            readonly property real endX: Math.min(0, titleClip.width - implicitWidth)
            readonly property bool needsScroll: endX < 0

            SequentialAnimation on x {
              running: titleText.needsScroll && !root.popupOpen && taskItem.hovering
              loops: Animation.Infinite
              NumberAnimation { from: 0; to: titleText.endX; duration: 6000 }
              PauseAnimation { duration: 1400 }
              NumberAnimation { from: titleText.endX; to: 0; duration: 6000 }
              PauseAnimation { duration: 1400 }
              onRunningChanged: if (!running) titleText.x = 0
            }
          }
        }
      }

      SequentialAnimation on opacity {
        running: taskItem.urgentTask && !taskItem.working
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.65; duration: taskItem.overdueTask ? 600 : 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.65; to: 1.0; duration: taskItem.overdueTask ? 600 : 900; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) taskItem.opacity = 1.0
      }

      MouseArea {
        id: taskMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property double lastDoubleClickTime: 0
        onClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) {
            root.openPopupFor(taskItem.task)
          } else if (mouse.button === Qt.RightButton) {
            root.openTui()
          }
        }
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton && taskItem.working) {
            root.stopPomo()
          }
        }
        onEntered: {
          taskItem.hovering = true
          if (root.bar) {
            var tip = String(taskItem.task.title || "(untitled)")
            root.bar.showTooltip(taskItem, tip)
          }
        }
        onExited: {
          taskItem.hovering = false
          if (root.bar) root.bar.hideTooltip(taskItem)
        }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(410))
    contentHeight: popup.fittedContentHeight(popupContent.implicitHeight)

    Column {
      id: popupContent
      anchors.fill: parent
      spacing: Style.space(12)

      // --- Top Header Bar ---
      Item {
        width: parent.width
        height: Style.space(26)
        visible: !root.showPomoSettings

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)

          Text {
            text: "󰔛"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.i18n("Horae 任务专注", "Horae Tasks & Focus")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            visible: root.displayTasks.length > 0
            implicitWidth: taskCountText.implicitWidth + Style.space(10)
            implicitHeight: Style.space(16)
            radius: height / 2
            color: Util.alpha(root.fg, 0.08)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: taskCountText
              anchors.centerIn: parent
              text: String(root.displayTasks.length)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Button {
            width: Style.space(26)
            height: Style.space(24)
            horizontalPadding: 0
            verticalPadding: 0
            text: ""
            iconText: root.privacyMode ? "󰈉" : "󰈈"
            iconSize: Style.font.bodySmall
            foreground: root.privacyMode ? root.accent : root.textColor
            background: root.privacyMode ? Util.alpha(root.accent, 0.14) : Util.alpha(root.fg, 0.06)
            tooltipText: root.privacyMode ?
              root.i18n("状态栏隐私模式: 开启", "Privacy Mode: ON") :
              root.i18n("状态栏隐私模式: 关闭", "Privacy Mode: OFF")
            onClicked: root.togglePrivacyMode()
          }

          Button {
            width: Style.space(26)
            height: Style.space(24)
            horizontalPadding: 0
            verticalPadding: 0
            text: ""
            iconText: "󰒓"
            iconSize: Style.font.bodySmall
            foreground: root.textColor
            background: Util.alpha(root.fg, 0.06)
            tooltipText: root.i18n("番茄钟偏好设置", "Pomodoro Settings")
            onClicked: root.showPomoSettings = true
          }
        }
      }

      // --- Top Header Bar in Settings Mode ---
      Item {
        width: parent.width
        height: Style.space(26)
        visible: root.showPomoSettings

        Row {
          id: settingsTitleRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          PanelActionButton {
            iconText: "󰅁"
            tooltipText: root.i18n("返回", "Back")
            foreground: root.fg
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.showPomoSettings = false
          }

          Text {
            text: root.i18n("番茄钟设置", "Pomodoro Settings")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          id: settingsLangRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            text: root.isChinese ? "中" : "EN"
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          ToggleSwitch {
            checked: root.isChinese
            trackHeight: 14
            accent: root.accent
            foreground: root.fg
            cursorRing: false
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.toggleLanguage()
          }
        }
      }

      PanelSeparator {
        foreground: root.fg
      }

      // --- Pomodoro session instrument card (idle & running; hidden in settings) ---
      Rectangle {
        width: parent.width
        visible: !root.showPomoSettings
        implicitHeight: heroCardCol.implicitHeight + Style.space(20)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
        color: Util.alpha(root.fg, 0.04)
        border.width: 1
        border.color: Util.alpha(root.fg, 0.08)

        Column {
          id: heroCardCol
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(10)

          // Running mode: live countdown, phase pill, cycle dots and progress ring
          Row {
            width: parent.width
            spacing: Style.space(14)
            visible: root.pomoRunning

            Item {
              id: heroGauge
              readonly property int pulseDuration: root.pomoBreaking ? 1700 : 950
              width: Style.space(60)
              height: width
              anchors.verticalCenter: parent.verticalCenter

              PomoRing {
                anchors.fill: parent
                progress: root.pomoRemainingFraction
                ringColor: root.phaseColor
                trackColor: Util.alpha(root.fg, 0.12)
                strokeW: Style.space(4)
              }

              Text {
                anchors.centerIn: parent
                text: root.pomoBreaking ? "☕" : "🍅"
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                renderType: Text.NativeRendering
              }

              SequentialAnimation on opacity {
                running: root.pomoRunning
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.85; duration: heroGauge.pulseDuration; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.85; to: 1.0; duration: heroGauge.pulseDuration; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) heroGauge.opacity = 1.0
              }
            }

            Column {
              width: parent.width - heroGauge.width - parent.spacing
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Row {
                spacing: Style.space(8)
                anchors.left: parent.left
                anchors.right: parent.right

                Text {
                  text: root.formatCountdown(root.pomoRemainingSecs)
                  color: root.phaseColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                  renderType: Text.NativeRendering
                  anchors.verticalCenter: parent.verticalCenter
                  Behavior on color {
                    ColorAnimation { duration: 250 }
                  }
                }

                Rectangle {
                  implicitWidth: phasePillText.implicitWidth + Style.space(10)
                  implicitHeight: Style.space(20)
                  radius: height / 2
                  color: Util.alpha(root.phaseColor, 0.16)
                  border.width: 1
                  border.color: Util.alpha(root.phaseColor, 0.4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: phasePillText
                    anchors.centerIn: parent
                    text: root.phaseLabel()
                    color: root.phaseColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              // Long break cycle dots
              Row {
                id: heroCycleDots
                spacing: Style.space(5)

                Repeater {
                  model: Math.max(1, root.pomoLongBreakInterval)
                  delegate: Rectangle {
                    required property int index
                    width: Style.space(7)
                    height: Style.space(7)
                    radius: width / 2
                    color: index < root.cycleDotsFilled ? root.phaseColor : Util.alpha(root.fg, 0.2)
                    border.width: 1
                    border.color: index < root.cycleDotsFilled ? root.phaseColor : Util.alpha(root.fg, 0.3)
                    Behavior on color {
                      ColorAnimation { duration: 250 }
                    }
                  }
                }
              }

              // Running stats row
              Row {
                spacing: Style.space(6)
                anchors.left: parent.left
                anchors.right: parent.right

                Rectangle {
                  implicitWidth: runningStatToday.implicitWidth + Style.space(8)
                  implicitHeight: Style.space(18)
                  radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
                  color: Util.alpha(root.fg, 0.06)

                  Text {
                    id: runningStatToday
                    anchors.centerIn: parent
                    text: root.i18n("今日 " + root.pomoTodayCount, "Today " + root.pomoTodayCount)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle {
                  implicitWidth: runningStatStreak.implicitWidth + Style.space(8)
                  implicitHeight: Style.space(18)
                  radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
                  color: Util.alpha(root.fg, 0.06)

                  Text {
                    id: runningStatStreak
                    anchors.centerIn: parent
                    text: root.i18n("连续 " + root.pomoStreak, "Streak " + root.pomoStreak)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle {
                  implicitWidth: runningStatTotal.implicitWidth + Style.space(8)
                  implicitHeight: Style.space(18)
                  radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
                  color: Util.alpha(root.fg, 0.06)

                  Text {
                    id: runningStatTotal
                    anchors.centerIn: parent
                    text: root.i18n("累计 " + root.pomoTotalCount, "Total " + root.pomoTotalCount)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // Idle mode: compact status badges with essential metrics only
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.pomoRunning

            Text {
              text: "🍅"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              implicitWidth: idleStatToday.implicitWidth + Style.space(8)
              implicitHeight: Style.space(18)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
              color: Util.alpha(root.fg, 0.06)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: idleStatToday
                anchors.centerIn: parent
                text: root.i18n("今日 " + root.pomoTodayCount, "Today " + root.pomoTodayCount)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              implicitWidth: idleStatStreak.implicitWidth + Style.space(8)
              implicitHeight: Style.space(18)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
              color: Util.alpha(root.fg, 0.06)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: idleStatStreak
                anchors.centerIn: parent
                text: root.i18n("连续 " + root.pomoStreak, "Streak " + root.pomoStreak)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              implicitWidth: idleStatTotal.implicitWidth + Style.space(8)
              implicitHeight: Style.space(18)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
              color: Util.alpha(root.fg, 0.06)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: idleStatTotal
                anchors.centerIn: parent
                text: root.i18n("累计 " + root.pomoTotalCount, "Total " + root.pomoTotalCount)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
                  implicitHeight: Style.space(18)
                  radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
                  color: Util.alpha(root.fg, 0.06)

                  Text {
                    id: statTotal
                    anchors.centerIn: parent
                    text: root.i18n("累计 " + root.pomoTotalCount, "Total " + root.pomoTotalCount)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // Hero actions: primary session control + quick capture + TUI
          Row {
            width: parent.width
            spacing: Style.space(8)
            readonly property real heroBtnW: Math.floor((width - 2 * spacing) / 3)

            Button {
              width: parent.heroBtnW
              iconText: root.pomoRunning ? "󰙦" : "󰐊"
              text: root.pomoRunning ? root.i18n("停止", "Stop") : root.i18n("开始专注", "Start")
              foreground: root.pomoRunning ? root.urgent : root.accent
              background: Util.alpha(root.pomoRunning ? root.urgent : root.accent, 0.16)
              bordered: true
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              tooltipText: root.pomoRunning
                ? root.i18n("停止当前专注", "Stop focus session")
                : (root.selectedTask
                   ? root.i18n("开启选中任务专注", "Focus on selected task")
                   : root.i18n("开始专注", "Start focus session"))
              enabled: root.pomoRunning || root.selectedTask !== null || root.displayTasks.length > 0
              onClicked: {
                if (root.pomoRunning) root.stopPomo()
                else root.startSelected()
              }
            }

            Button {
              width: parent.heroBtnW
              iconText: "󰏪"
              text: root.i18n("闪念录入", "Capture")
              foreground: root.fg
              accent: root.accent
              background: Util.alpha(root.fg, 0.06)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.launchFlashCapture()
            }

            Button {
              width: parent.heroBtnW
              iconText: "󰞷"
              text: root.i18n("TUI 终端", "TUI")
              foreground: root.fg
              background: Util.alpha(root.fg, 0.06)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.openTui()
            }
          }
        }
      }

      // --- Pomodoro settings (2x2 NumberField grid) ---
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.showPomoSettings

        Text {
          text: root.i18n("微调专注与休息周期参数，自动同步到本地配置：", "Tune focus and break cycles, synced locally:")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          NumberField {
            width: Math.floor((parent.width - parent.spacing) / 2)
            label: root.i18n("专注时长 · 分钟", "Focus · min")
            from: 1
            to: 180
            stepSize: 5
            value: root.pomoWorkMins
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            onModified: function(v) { root.savePomoConfig(v, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval) }
          }

          NumberField {
            width: Math.floor((parent.width - parent.spacing) / 2)
            label: root.i18n("短休 · 分钟", "Short break · min")
            from: 1
            to: 60
            stepSize: 1
            value: root.pomoShortBreakMins
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            onModified: function(v) { root.savePomoConfig(root.pomoWorkMins, v, root.pomoLongBreakMins, root.pomoLongBreakInterval) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          NumberField {
            width: Math.floor((parent.width - parent.spacing) / 2)
            label: root.i18n("长休 · 分钟", "Long break · min")
            from: 1
            to: 90
            stepSize: 5
            value: root.pomoLongBreakMins
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            onModified: function(v) { root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, v, root.pomoLongBreakInterval) }
          }

          NumberField {
            width: Math.floor((parent.width - parent.spacing) / 2)
            label: root.i18n("长休轮数", "Long break interval")
            from: 1
            to: 12
            stepSize: 1
            value: root.pomoLongBreakInterval
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            onModified: function(v) { root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, v) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(10)
          readonly property real settingsBtnW: Math.floor((width - spacing) / 2)

          Button {
            width: parent.settingsBtnW
            iconText: "󰑐"
            text: root.i18n("恢复默认 (25/5/15/4)", "Reset Default")
            foreground: root.fg
            background: Util.alpha(root.fg, 0.06)
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            onClicked: root.resetPomoConfigToDefault()
          }

          Button {
            width: parent.settingsBtnW
            iconText: "󰄬"
            text: root.i18n("保存设置", "Save Settings")
            foreground: root.accent
            background: Util.alpha(root.accent, 0.16)
            bordered: true
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval)
          }
        }
      }

      // --- Selected task details card ---
      Rectangle {
        id: selectedTaskCard
        width: parent.width
        visible: !root.showPomoSettings && root.selectedTask !== null
        implicitHeight: selectedCol.implicitHeight + Style.space(18)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
        readonly property bool isWorkingOnThis: root.workingTaskId !== "" && root.selectedTask !== null && String(root.selectedTask.id) === root.workingTaskId
        color: isWorkingOnThis ? Util.alpha(root.urgent, 0.06) : Util.alpha(root.accent, 0.04)
        border.width: 1
        border.color: isWorkingOnThis ? Util.alpha(root.urgent, 0.36) : Util.alpha(root.accent, 0.24)

        Column {
          id: selectedCol
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: root.selectedTask ? root.taskIcon(root.selectedTask) : ""
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              width: parent.width - Style.space(26) - heroStatusPill.width - closeSelectBtn.width - parent.spacing * 3
              text: root.selectedTask ? String(root.selectedTask.title || "") : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: heroStatusPill
              width: heroStatusText.implicitWidth + Style.space(10)
              height: Style.space(18)
              radius: height / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Util.alpha(root.statusColor(root.selectedTask), 0.15)
              border.width: 1
              border.color: Util.alpha(root.statusColor(root.selectedTask), 0.4)

              Text {
                id: heroStatusText
                anchors.centerIn: parent
                text: root.selectedTask ? root.taskStatus(root.selectedTask) : ""
                color: root.statusColor(root.selectedTask)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                renderType: Text.NativeRendering
              }
            }

            Button {
              id: closeSelectBtn
              width: Style.space(22)
              height: Style.space(22)
              horizontalPadding: 0
              verticalPadding: 0
              text: ""
              iconText: "󰅖"
              iconSize: Style.font.caption
              foreground: root.dim
              background: "transparent"
              tooltipText: root.i18n("返回任务列表", "Back to tasks list")
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.selectedTaskId = ""
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)
            anchors.leftMargin: Style.space(2)

            Text {
              text: "󰃰"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.selectedTask ? (root.timeLabel(root.selectedTask) + ": " + root.formatDue(root.taskTime(root.selectedTask))) : "-"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Task Actions: Complete, Defer 1h, Archive
          Row {
            width: parent.width
            spacing: Style.space(8)
            readonly property real taskBtnW: Math.floor((width - 2 * spacing) / 3)

            Button {
              width: parent.taskBtnW
              iconText: "󰄬"
              text: root.i18n("标记完成", "Mark Done")
              foreground: root.accent
              background: Util.alpha(root.accent, 0.16)
              bordered: true
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.completeSelected()
            }

            Button {
              width: parent.taskBtnW
              iconText: "󰔛"
              text: root.i18n("延迟 1h", "+1 Hour")
              foreground: root.fg
              background: Util.alpha(root.fg, 0.06)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.deferSelected()
            }

            Button {
              width: parent.taskBtnW
              iconText: "󰆴"
              text: root.i18n("归档任务", "Archive")
              foreground: root.dim
              background: Util.alpha(root.fg, 0.04)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.archiveSelected()
            }
          }
        }
      }

      // --- Upcoming tasks list (when no task is selected) ---
      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: !root.showPomoSettings && root.selectedTask === null

        Item {
          width: parent.width
          height: Style.space(20)
          visible: root.displayTasks.length > 0

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("近期排程 / 待办任务", "Upcoming tasks")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        // Empty state when no tasks are queued
        Item {
          width: parent.width
          height: Style.space(48)
          visible: root.displayTasks.length === 0

          Row {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Text {
              text: "󰄬"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.i18n("暂无临近待办，享受心流", "No upcoming tasks, stay in flow")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Repeater {
          model: root.displayTasks
          delegate: Item {
            id: taskRow
            property var taskData: modelData
            width: popupContent.width
            height: Style.space(34)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
              color: rowMouse.containsMouse ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
              border.width: 1
              border.color: rowMouse.containsMouse ? Util.alpha(root.accent, 0.25) : "transparent"
              Behavior on color {
                ColorAnimation { duration: 120 }
              }
              Behavior on border.color {
                ColorAnimation { duration: 120 }
              }
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: rowMouse.containsMouse ? Style.space(10) : Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)
              Behavior on anchors.leftMargin {
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
              }

              Rectangle {
                width: Style.space(22)
                height: Style.space(22)
                radius: 4
                color: Util.alpha(root.statusColor(taskRow.taskData), 0.12)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: root.taskIcon(taskRow.taskData)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width - Style.space(30) - taskRowTimePill.width - parent.spacing * 2
                text: String(taskRow.taskData.title || "")
                color: root.isUrgent(taskRow.taskData) ? root.urgent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: root.workingTaskId !== "" && String(taskRow.taskData.id) === root.workingTaskId
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                id: taskRowTimePill
                implicitWidth: taskRowTime.implicitWidth + Style.space(10)
                implicitHeight: Style.space(18)
                radius: height / 2
                color: Util.alpha(root.fg, 0.06)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: taskRowTime
                  anchors.centerIn: parent
                  text: root.formatDueTime(root.taskTime(taskRow.taskData))
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openPopupFor(taskRow.taskData)
            }
          }
        }
      }
    }
  }

  function refreshTasks() {
    if (tasksProc.running) tasksProc.running = false
    tasksProc.running = true
  }

  // Re-parse pomo.json (kept warm in pomoWatcher); fall back to the horae
  // process only when the file is missing.
  function refreshPomo() {
    var raw = typeof pomoWatcher.text === "function" ? pomoWatcher.text() : String(pomoWatcher.text || "")
    if (raw && raw.trim() !== "") {
      applyPomoFile(raw)
      return
    }
    if (pomoProc.running) pomoProc.running = false
    pomoProc.running = true
  }

  Component.onCompleted: {
    root.refreshPomo()
    root.refreshTasks()
  }

  Process {
    id: tasksProc
    command: root.command(["alarm", "waybar", "--all", "--limit", String(root.alarmLimit)])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTasks(text)
    }
  }

  Process {
    id: pomoProc
    command: root.command(["pomo", "waybar"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPomo(text)
    }
  }

  // Event-driven refresh: watch the files horae itself writes.
  // FileView does not refresh `text` on its own — shell code always calls
  // reload() from onFileChanged, which then re-fires onLoaded.
  FileView {
    id: pomoWatcher
    path: root.dataDir + "/pomo.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.refreshPomo()
    onLoadFailed: root.refreshPomo()
    onFileChanged: reload()
  }

  FileView {
    id: tasksWatcher
    path: root.dataDir + "/horae.db"
    watchChanges: true
    printErrors: false
    onLoaded: root.refreshTasks()
    onLoadFailed: root.refreshTasks()
    onFileChanged: root.refreshTasks()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshTasks()
      if (!root.pomoRunning) root.refreshPomo()
    }
  }

  // Local countdown tick: pure math on pomo.json timestamps, no process spawn.
  Timer {
    id: pomoTickTimer
    interval: 1000
    running: root.pomoRunning
    repeat: true
    onTriggered: root.updatePomoTick()
  }

  Timer {
    id: refreshTimer
    interval: 250
    onTriggered: root.refreshTasks()
  }

  Timer {
    id: pomoRefreshTimer
    interval: 250
    onTriggered: root.refreshPomo()
  }

  Timer {
    id: pomoClickTimer
    interval: 250
    repeat: false
    onTriggered: root.launchFlashCapture()
  }

  // Auto-dismiss popup when inactive or mouse leaves
  Timer {
    id: autoDismissTimer
    interval: root.autoDismissSecs * 1000
    repeat: false
    running: root.popupOpen && root.autoDismissSecs > 0 && !root.showPomoSettings && !popup.containsMouse
    onTriggered: {
      if (root.popupOpen && !popup.containsMouse && !root.showPomoSettings) {
        root.close()
      }
    }
  }

  // Dismiss popup on workspace switch so it does not strand across screens/workspaces
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      if (root.popupOpen) root.close()
    }
  }
}
