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
  readonly property string localHoraeBin: homeDir !== "" ? (homeDir + "/.local/bin/horae") : ""
  property string resolvedHoraeBin: ""
  readonly property string horaeBin: {
    var custom = String(setting("horaeBin", "")).trim()
    if (custom !== "") return custom
    if (resolvedHoraeBin !== "") return resolvedHoraeBin
    return cargoHoraeBin !== "" ? cargoHoraeBin : (localHoraeBin !== "" ? localHoraeBin : "horae")
  }

  property bool horaeInstalled: false
  property string horaeVersion: ""
  property int probeIndex: 0
  property bool commandCopied: false

  readonly property string profile: String(setting("profile", "")).trim()
  readonly property int alarmLimit: Math.max(1, Math.min(20, Number(setting("limit", 10))))
  readonly property int displayMax: Math.max(1, Math.min(5, Number(setting("displayMax", 2))))
  readonly property int windowBackHours: Number(setting("windowBackHours", 10))
  readonly property int windowFwdHours: Number(setting("windowFwdHours", 24))
  readonly property int windowBackMs: windowBackHours * 3600 * 1000
  readonly property int windowFwdMs: windowFwdHours * 3600 * 1000
  readonly property string windowScopeText: root.i18n(
    "过去 " + windowBackHours + "h ~ 未来 " + windowFwdHours + "h",
    "-" + windowBackHours + "h ~ +" + windowFwdHours + "h"
  )
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
    if (bar) {
      bar.run(cmd)
      bar.run("omarchy-shell shell setBarWidget " + shellArg(root.moduleName) + " 'lang' " + shellArg(next) + " '{}'")
    }
    refreshTimer.restart()
  }

  // Privacy Mode: only expose first character (CJK) or first word (English)
  property bool privacyMode: Boolean(setting("privacyMode", false))

  function togglePrivacyMode() {
    privacyMode = !privacyMode
    var val = privacyMode ? "1" : "0"
    var sql = "INSERT INTO settings (key, val) VALUES ('privacy_mode', '" + val + "') ON CONFLICT(key) DO UPDATE SET val='" + val + "';"
    var cmd = "sqlite3 " + shellArg(root.dataDir + "/horae.db") + " " + shellArg(sql)
    if (bar) {
      bar.run(cmd)
      bar.run("omarchy-shell shell setBarWidget " + shellArg(root.moduleName) + " 'privacyMode' " + shellArg(privacyMode ? "true" : "false") + " '{}'")
    }
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
  readonly property string workingTaskId: pomoRunning ? pomoTaskId : ""

  // Instrument colors: focus/breaks = accent, idle = plain
  readonly property color phaseColor: !pomoRunning ? textColor : accent

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

  property bool settingsSavedNotice: false
  Timer {
    id: saveNoticeTimer
    interval: 1800
    repeat: false
    onTriggered: root.settingsSavedNotice = false
  }

  property string actionFeedbackText: ""
  property color actionFeedbackColor: root.accent
  Timer {
    id: actionFeedbackTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionFeedbackText = ""
  }

  function showActionFeedback(msg, col) {
    actionFeedbackText = String(msg || "")
    actionFeedbackColor = col || root.accent
    actionFeedbackTimer.restart()
  }

  // Neutralize markup-shaped characters before handing dynamic strings to shared shell tooltips
  function safePlainText(val) {
    if (val === undefined || val === null) return ""
    return String(val).replace(/</g, "‹").replace(/>/g, "›")
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
    if (pomoRemainingSecs <= 0) {
      root.refreshPomo()
    }
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
    pomoTaskId = pomoPhase !== "idle" ? String(state.task_id || "") : ""
    pomoTaskTitle = pomoPhase !== "idle" ? String(state.task_title || "") : ""
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
    if (!raw || String(raw).trim() === "") return
    try {
      var parsed = JSON.parse(String(raw))
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
    settingsSavedNotice = true
    saveNoticeTimer.restart()
    pomoWorkMins = Math.max(1, Math.min(180, w))
    pomoShortBreakMins = Math.max(1, Math.min(60, s))
    pomoLongBreakMins = Math.max(1, Math.min(90, l))
    pomoLongBreakInterval = Math.max(1, Math.min(12, i))
    var dataFile = root.dataDir + "/pomo.json"
    var tmpFile = dataFile + ".tmp." + Date.now()
    var jqCmd = "[ -f " + shellArg(dataFile) + " ] || (touch " + shellArg(dataFile) + " && chmod 600 " + shellArg(dataFile) + " && echo '{}' > " + shellArg(dataFile) + ") ; " +
      "chmod 600 " + shellArg(dataFile) + " 2>/dev/null || true ; " +
      "jq --argjson w " + pomoWorkMins + " --argjson s " + pomoShortBreakMins + " --argjson l " + pomoLongBreakMins + " --argjson i " + pomoLongBreakInterval +
      " '.config = ((.config // {}) + {\"work_mins\": $w, \"short_break_mins\": $s, \"long_break_mins\": $l, \"long_break_interval\": $i})' " +
      shellArg(dataFile) + " > " + shellArg(tmpFile) + " && chmod 600 " + shellArg(tmpFile) + " && mv -f " + shellArg(tmpFile) + " " + shellArg(dataFile)
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
    if (!pomoRunning) return "󰔛"
    var t = formatCountdown(pomoRemainingSecs)
    var prefix = pomoBreaking ? "󰛄 " : ""
    if (privacyMode) return prefix + t
    var title = String(pomoTaskTitle || "")
    if (title === "") return prefix + t
    if (title.length > 14) title = title.substring(0, 14) + "…"
    return prefix + t + " " + title
  }

  function pomoTooltipText() {
    if (pomoRunning) {
      var phase = phaseLabel() + " · " + formatCountdown(pomoRemainingSecs)
      var title = String(pomoTaskTitle || "").trim()
      if (title !== "") {
        var cleanTitle = safePlainText(title)
        return (pomoBreaking ? "󰛄 " : "󰔛 ") + phase + "\n" + cleanTitle
      }
      return (pomoBreaking ? "󰛄 " : "󰔛 ") + phase
    }
    return "󰔛 " + i18n("番茄钟就绪 · " + pomoWorkMins + " 分钟", "Focus Ready · " + pomoWorkMins + "m")
  }

  function taskTooltipText(task, isWorking) {
    if (!task) return ""
    var rawTitle = String(task.title || i18n("(未命名任务)", "(untitled)"))
    var title = safePlainText(rawTitle)

    if (isWorking) {
      var pomoInfo = pomoRunning ? (" · " + i18n("剩余 ", "left ") + formatCountdown(pomoRemainingSecs)) : ""
      return title + "\n󰔛 " + i18n("正在专注", "Focusing") + pomoInfo
    }

    var t = taskTime(task)
    if (t > 0) {
      var dueStr = formatDueTime(t)
      var relStr = formatRelativeTime(t)
      var label = timeLabel(task)
      var timePart = label + " " + dueStr + (relStr ? " · " + relStr : "")
      var urgentIcon = isUrgent(task) ? "󰥔 " : "󰃰 "
      return title + "\n" + urgentIcon + timePart
    }

    return title
  }

  function i18n(zh, en) {
    return isChinese ? zh : en
  }

  // Shell panel lifecycle contract (Quattro standard)
  readonly property bool opened: popupOpen
  readonly property bool popoutSwitchClosing: false

  function open() {
    popupOpen = true
    if (workingTaskId !== "" && findSelectedTask(windowTasks, workingTaskId)) {
      selectedTaskId = workingTaskId
    } else if (selectedTaskId !== "" && !findSelectedTask(windowTasks, selectedTaskId)) {
      selectedTaskId = windowTasks.length > 0 ? String(windowTasks[0].id) : ""
    } else if (selectedTaskId === "" && windowTasks.length > 0) {
      selectedTaskId = String(windowTasks[0].id)
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
  property var windowTasks: []
  property string selectedTaskId: ""
  property bool popupOpen: false

  function findSelectedTask(tasksList, id) {
    if (!id || !tasksList) return null
    for (var i = 0; i < tasksList.length; i++) {
      if (String(tasksList[i].id) === id) return tasksList[i]
    }
    return null
  }

  readonly property var selectedTask: {
    var found = findSelectedTask(windowTasks, selectedTaskId)
    if (found) return found
    return findSelectedTask(displayTasks, selectedTaskId)
  }

  function advanceSelectionAfterAction(actedId) {
    if (!windowTasks || windowTasks.length <= 1) {
      selectedTaskId = ""
      return
    }
    for (var i = 0; i < windowTasks.length; i++) {
      if (String(windowTasks[i].id) === String(actedId)) {
        var nextIdx = (i + 1 < windowTasks.length) ? (i + 1) : (i - 1)
        selectedTaskId = nextIdx >= 0 ? String(windowTasks[nextIdx].id) : ""
        return
      }
    }
  }

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
    if (!task) return "󰥔"
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return "󰔛"
    return taskClass(task) === "alarm-now" ? "󰂚" : "󰥔"
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
    if (c === "alarm-overdue") return isStart ? i18n("超时未开始", "Past start") : i18n("已逾期", "Overdue")
    if (c === "alarm-now") return isStart ? i18n("即将开始", "Starting soon") : i18n("即将到期", "Due soon")
    if (String(task.status || "").toLowerCase() === "scheduled") return i18n("已排程", "Scheduled")
    return i18n("待办", "Todo")
  }

  function statusColor(task) {
    if (!task) return root.dim
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return root.accent
    if (isUrgent(task)) return root.urgent
    if (isStartTime(task)) return root.accent
    return root.dim
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

  function formatRelativeTime(ms) {
    if (!ms) return ""
    var diffMins = Math.round((Number(ms) - Date.now()) / 60000)
    if (Math.abs(diffMins) < 1) return i18n("就是现在", "Right now")
    if (diffMins > 0) {
      if (diffMins < 60) return i18n(diffMins + " 分钟后", "in " + diffMins + "m")
      var h = Math.floor(diffMins / 60)
      var m = diffMins % 60
      return m > 0 ? i18n(h + "h " + m + "m 后", "in " + h + "h " + m + "m") : i18n(h + " 小时后", "in " + h + "h")
    } else {
      var past = Math.abs(diffMins)
      if (past < 60) return i18n("已超 " + past + " 分钟", past + "m ago")
      var ph = Math.floor(past / 60)
      var pm = past % 60
      return pm > 0 ? i18n("已超 " + ph + "h " + pm + "m", ph + "h " + pm + "m ago") : i18n("已超 " + ph + " 小时", ph + "h ago")
    }
  }

  function formatTimeArg(ms) {
    return formatDue(ms)
  }

  function applyTasks(raw) {
    if (!raw || String(raw).trim() === "") return
    try {
      var parsed = JSON.parse(String(raw))
      if (!Array.isArray(parsed)) return
      var list = parsed.filter(function(t) { return t && t.class && t.class !== "alarm-none" })
      tasks = list
      buildDisplayTasks()
    } catch (error) {
      // Preserve existing tasks on parse/stream error to avoid visual flicker
    }
  }

  function displayKey(task) {
    if (!task) return ""
    return String(task.id || "") + "|" + String(task.title || "") + "|" + taskTime(task) + "|" +
      (isUrgent(task) ? 1 : 0) + "|" +
      (isOverdue(task) ? 1 : 0) + "|" +
      (workingTaskId !== "" && String(task.id) === workingTaskId ? 1 : 0)
  }

  function buildDisplayTasks() {
    var candidates = tasks.filter(inWindow).slice()
    candidates.sort(function(a, b) {
      var diff = taskTime(a) - taskTime(b)
      if (diff !== 0) return diff
      return String(a.id || "").localeCompare(String(b.id || ""))
    })
    var fullList = candidates.slice(0, alarmLimit)
    var barSlice = candidates.slice(0, displayMax)

    var fullSame = (fullList.length === windowTasks.length)
    if (fullSame) {
      for (var j = 0; j < fullList.length; j++) {
        if (displayKey(fullList[j]) !== displayKey(windowTasks[j])) { fullSame = false; break }
      }
    }
    if (!fullSame) windowTasks = fullList

    var barSame = (barSlice.length === displayTasks.length)
    if (barSame) {
      for (var i = 0; i < barSlice.length; i++) {
        if (displayKey(barSlice[i]) !== displayKey(displayTasks[i])) { barSame = false; break }
      }
    }
    if (!barSame) displayTasks = barSlice
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

  function stopWorkingPomoIfTask(task) {
    if (workingTaskId !== "" && task && String(task.id) === workingTaskId) {
      if (bar) bar.run(command(["pomo", "stop"]).map(shellArg).join(" "))
      pomoRefreshTimer.restart()
    }
  }

  function stopWorkingPomoIfSelected() {
    stopWorkingPomoIfTask(selectedTask)
  }

  function shellArg(value) {
    var text = String(value)
    return "'" + text.replace(/'/g, "'\\''") + "'"
  }

  function startTaskFocus(task) {
    if (!task) return
    var id = String(task.id)
    selectedTaskId = id
    runTaskAction(["pomo", "start", id], true)
    showActionFeedback(i18n("󰐊 已开启专注", "󰐊 Focus started"), root.accent)
  }

  function startSelected() {
    var task = selectedTask
    if (!task && windowTasks.length > 0) task = windowTasks[0]
    if (!task) return
    startTaskFocus(task)
  }

  function deferSelected() {
    if (!selectedTask) return
    var id = String(selectedTask.id)
    var due = taskTime(selectedTask)
    var target = due >= Date.now() ? due + 3600000 : Date.now() + 3600000
    if (isStartTime(selectedTask)) {
      runTaskAction(["schedule", id, "--start", formatTimeArg(target)], true)
    } else {
      runTaskAction(["modify", id, "--due", formatTimeArg(target)], true)
    }
    showActionFeedback(i18n("󰔛 已顺延 1 小时", "󰔛 Deferred +1h"), root.accent)
  }

  function completeTaskDirect(task) {
    if (!task) return
    var id = String(task.id)
    stopWorkingPomoIfTask(task)
    if (selectedTaskId === id) advanceSelectionAfterAction(id)
    runTaskAction(["done", id], true)
    showActionFeedback(i18n("󰄬 已标记完成", "󰄬 Marked done"), root.accent)
  }

  function completeSelected() {
    if (selectedTask) completeTaskDirect(selectedTask)
  }

  function archiveSelected() {
    if (selectedTask) {
      var id = String(selectedTask.id)
      stopWorkingPomoIfSelected()
      advanceSelectionAfterAction(id)
      runTaskAction(["archive", id], true)
      showActionFeedback(i18n("󰆴 已归档任务", "󰆴 Task archived"), root.dim)
    }
  }

  function stopPomo() {
    if (bar) bar.run(command(["pomo", "stop"]).map(shellArg).join(" "))
    pomoRefreshTimer.restart()
    showActionFeedback(i18n("󰙦 专注已停止", "󰙦 Focus stopped"), root.urgent)
  }

  // ---------------------------------------------------------------------------
  // Reusable Design System UI Primitives (UI/UX Pro Max + Omarchy Shell)
  // ---------------------------------------------------------------------------
  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  component TabularText: PlainText {
    font.features: ({ "tnum": 1 })
  }

  component StatBadge: Rectangle {
    id: statBadgeRoot
    property string iconText: ""
    property string text: ""
    property color badgeColor: root.fg
    property bool highlight: false

    implicitWidth: statBadgeRow.implicitWidth + Style.space(12)
    implicitHeight: Style.space(20)
    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 5) : 4
    color: highlight ? Util.alpha(badgeColor, 0.12) : Util.alpha(root.fg, 0.05)
    border.width: 1
    border.color: highlight ? Util.alpha(badgeColor, 0.28) : Util.alpha(root.fg, 0.08)

    Row {
      id: statBadgeRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      PlainText {
        visible: statBadgeRoot.iconText !== ""
        text: statBadgeRoot.iconText
        color: statBadgeRoot.highlight ? statBadgeRoot.badgeColor : root.accent
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      TabularText {
        text: statBadgeRoot.text
        color: statBadgeRoot.highlight ? statBadgeRoot.badgeColor : root.dim
        font.pixelSize: Style.font.caption
        font.bold: statBadgeRoot.highlight
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  component StatusPill: Rectangle {
    id: statusPillRoot
    property string text: ""
    property color pillColor: root.accent

    implicitWidth: statusPillLabel.implicitWidth + Style.space(12)
    implicitHeight: Style.space(19)
    radius: height / 2
    color: Util.alpha(pillColor, 0.15)
    border.width: 1
    border.color: Util.alpha(pillColor, 0.4)

    PlainText {
      id: statusPillLabel
      anchors.centerIn: parent
      text: statusPillRoot.text
      color: statusPillRoot.pillColor
      font.pixelSize: Style.font.caption
      font.bold: true
    }
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
        ColorAnimation { duration: Style.duration(250) }
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
    color: capsuleHover.hovered ? Util.alpha(root.fg, 0.10) : Util.alpha(root.fg, 0.05)
    border.width: root.popupOpen ? 1 : 0
    border.color: root.popupOpen ? Util.alpha(root.accent, 0.35) : "transparent"
    clip: true

    Behavior on width {
      NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
    }
    Behavior on color {
      ColorAnimation { duration: Style.duration(180) }
    }

    HoverHandler {
      id: capsuleHover
    }

    Row {
      id: row
      x: (capsuleContainer.width - width) / 2
      y: (capsuleContainer.height - height) / 2
      spacing: Style.space(4)

      // Setup guide indicator on bar when Horae CLI is not yet installed
      Item {
        id: setupIndicatorItem
        visible: !root.horaeInstalled
        readonly property bool hovering: setupMouse.containsMouse
        readonly property real targetWidth: setupRow.implicitWidth + Style.space(12)
        implicitWidth: targetWidth
        width: implicitWidth
        implicitHeight: root.capsuleHeight
        clip: true

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          radius: height / 2
          color: setupMouse.containsMouse ? Util.alpha(root.accent, 0.22) : Util.alpha(root.accent, 0.12)
          Behavior on color { ColorAnimation { duration: Style.duration(150) } }
        }

        Row {
          id: setupRow
          anchors.centerIn: parent
          spacing: Style.space(5)

          PlainText {
            text: "󰋼"
            color: root.accent
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          PlainText {
            text: root.i18n("Horae (需初始化)", "Horae (Setup)")
            color: root.textColor
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: setupMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePopup()
          onEntered: if (root.bar) root.bar.showTooltip(setupIndicatorItem, root.i18n("未检测到 Horae CLI 后端，点击打开设置向导", "Horae CLI not detected. Click to open setup wizard"))
          onExited: if (root.bar) root.bar.hideTooltip(setupIndicatorItem)
        }
      }

      // Privacy Mode Toggle Button on Bar (revealed on hover)
      Item {
        id: privacyBtnItem
        readonly property bool hovering: privacyMouse.containsMouse
        readonly property bool tooltipHovered: visible && opacity > 0 && privacyMouse.containsMouse
        readonly property real targetWidth: privacyBtnText.implicitWidth + Style.space(12)
        implicitWidth: (root.horaeInstalled && root.revealPrivacyBtn) ? targetWidth : 0
        width: implicitWidth
        implicitHeight: root.capsuleHeight
        visible: root.horaeInstalled && width > 0.5
        clip: true
        opacity: (root.horaeInstalled && root.revealPrivacyBtn) ? 1.0 : 0.0

        Behavior on implicitWidth {
          NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: Style.duration(160) }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          radius: height / 2
          color: privacyBtnItem.hovering ? Util.alpha(root.accent, 0.18) : (root.privacyMode ? Util.alpha(root.accent, 0.10) : "transparent")
          Behavior on color { ColorAnimation { duration: Style.duration(150) } }
        }

        PlainText {
          id: privacyBtnText
          anchors.centerIn: parent
          text: root.privacyMode ? "󰈉" : "󰈈"
          color: privacyMouse.containsMouse ? root.accent : (root.privacyMode ? root.accent : root.textColor)
          opacity: root.privacyMode ? 1.0 : (privacyMouse.containsMouse ? 1.0 : 0.65)
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: privacyMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePrivacyMode()
          onEntered: if (root.bar) root.bar.showTooltip(privacyBtnItem, root.privacyMode
            ? root.i18n("隐私模式：已开启", "Privacy Mode: On")
            : root.i18n("隐私模式：已关闭", "Privacy Mode: Off"))
          onExited: if (root.bar) root.bar.hideTooltip(privacyBtnItem)
        }
      }

      Repeater {
        id: barRepeater
        model: root.horaeInstalled ? root.displayTasks : []
        delegate: taskDelegate
      }

      // 无待办任务时的保底番茄钟/灵感录入入口（有待办任务时番茄钟已深度集成进各任务项自身）
      Item {
        id: pomoItem
        visible: root.horaeInstalled && root.displayTasks.length === 0 && width > 0.5
        readonly property bool hovering: pomoMouse.containsMouse
        readonly property bool tooltipHovered: visible && opacity > 0 && pomoMouse.containsMouse
        readonly property real targetWidth: pomoRow.implicitWidth + Style.space(12)
        implicitWidth: (root.horaeInstalled && root.displayTasks.length === 0 && root.revealPomoItem) ? targetWidth : 0
        width: implicitWidth
        implicitHeight: root.capsuleHeight
        clip: true
        opacity: (root.horaeInstalled && root.displayTasks.length === 0 && root.revealPomoItem) ? 1.0 : 0.0

        Behavior on implicitWidth {
          NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: Style.duration(160) }
        }

        Rectangle {
          anchors.fill: parent
          anchors.topMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          radius: height / 2
          color: pomoItem.hovering ? Util.alpha(root.pomoRunning ? root.phaseColor : root.fg, 0.12) : (root.pomoRunning ? Util.alpha(root.phaseColor, 0.08) : "transparent")
          Behavior on color { ColorAnimation { duration: Style.duration(150) } }
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

          TabularText {
            id: pomoText
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayPomoText()
            color: root.pomoRunning ? root.phaseColor : root.textColor
            font.pixelSize: Style.font.caption
            Behavior on color {
              ColorAnimation { duration: Style.duration(200) }
            }
          }

          SequentialAnimation on opacity {
            running: root.pomoRunning && !Style.reduceMotion
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
      readonly property string timeStr: working ? ((root.pomoBreaking ? "󰛄 " : "") + root.formatCountdown(root.pomoRemainingSecs)) : root.formatDueTime(root.taskTime(task))

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
        color: taskItem.hovering ? Util.alpha(root.fg, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: Style.duration(150) } }
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
              running: taskItem.working && root.pomoRunning && !Style.reduceMotion
              loops: Animation.Infinite
              NumberAnimation { from: 1.0; to: 0.75; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.75; to: 1.0; duration: root.pomoBreaking ? 1600 : 900; easing.type: Easing.InOutSine }
              onRunningChanged: if (!running) opacity = 1.0
            }
          }

          // 常规图标（非专注时显示）
          PlainText {
            id: taskIconText
            visible: !taskItem.working
            anchors.centerIn: parent
            text: root.taskIcon(taskItem.task)
            color: taskItem.urgentTask ? root.urgent : root.textColor
            font.pixelSize: Style.font.caption
          }
        }

        // 2. 时间/倒计时区：专注时显示实时倒计时，否则显示计划时间（颜色严格基于是否到期判断）
        TabularText {
          id: taskTimeText
          visible: taskItem.timeStr !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: taskItem.timeStr
          color: taskItem.urgentTask ? root.urgent : (taskItem.working ? root.phaseColor : root.textColor)
          font.pixelSize: Style.font.caption
          font.bold: taskItem.working
          Behavior on color { ColorAnimation { duration: Style.duration(200) } }
        }

        // 3. 标题文本（隐私模式下隐藏，超出时支持平滑跑马灯，颜色严格基于是否到期判断）
        Item {
          id: titleClip
          visible: !root.privacyMode && taskItem.clipTitleW > 0
          width: taskItem.clipTitleW
          height: root.capsuleHeight
          clip: true
          anchors.verticalCenter: parent.verticalCenter

          PlainText {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: String(taskItem.task.title || "(untitled)")
            color: taskItem.urgentTask ? root.urgent : root.textColor
            font.pixelSize: Style.font.caption
            font.bold: taskItem.working
            readonly property real endX: Math.min(0, titleClip.width - implicitWidth)
            readonly property bool needsScroll: endX < 0

            SequentialAnimation on x {
              running: titleText.needsScroll && !root.popupOpen && taskItem.hovering && !Style.reduceMotion
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
        running: taskItem.urgentTask && !taskItem.working && !Style.reduceMotion
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
            root.bar.showTooltip(taskItem, root.taskTooltipText(taskItem.task, taskItem.working))
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
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(popupContent.implicitHeight)

    Column {
      id: popupContent
      anchors.fill: parent
      spacing: Style.space(12)
      focus: true

      Keys.onEscapePressed: function(event) {
        if (root.showPomoSettings) {
          root.showPomoSettings = false
          event.accepted = true
        } else if (root.selectedTaskId !== "") {
          root.selectedTaskId = ""
          event.accepted = true
        } else {
          root.close()
          event.accepted = true
        }
      }

        // =====================================================================
        // First-run Setup Wizard (Shown when Horae CLI is not yet installed)
        // =====================================================================
        Column {
          id: setupWizardCol
          width: parent.width
          spacing: Style.space(12)
          visible: !root.horaeInstalled

          // Wizard Header Bar
          Item {
            width: parent.width
            height: Style.space(26)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(7)

              PlainText {
                text: "󰋼"
                color: root.accent
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                text: root.i18n("Horae 后端初始化向导", "Horae Setup Wizard")
                color: root.fg
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: root.currentLang === "zh" ? "EN" : "中"
                foreground: root.textColor
                background: Util.alpha(root.fg, 0.06)
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                tooltipText: root.i18n("切换语言 / Switch Language", "Switch Language / 切换语言")
                onClicked: root.toggleLanguage()
              }

              Button {
                iconText: "󰅖"
                foreground: root.textColor
                background: Util.alpha(root.fg, 0.06)
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                tooltipText: root.i18n("关闭", "Close")
                onClicked: root.close()
              }
            }
          }

          // Welcome & Intro Banner Card
          Rectangle {
            width: parent.width
            implicitHeight: setupHeroCol.implicitHeight + Style.space(20)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
            color: Util.alpha(root.accent, 0.08)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.25)

            Column {
              id: setupHeroCol
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              PlainText {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.i18n(
                  "欢迎使用 Horae 任务与专注插件！本插件依托纯本地 Rust 核心服务管理 SQLite 任务队列与番茄钟节律，极速轻量且隐私安全。当前系统未检测到 horae 命令行工具，请选择以下任一方式完成安装：",
                  "Welcome to Horae Tasks & Focus! This widget relies on a local Rust CLI to manage SQLite GTD tasks and Pomodoro focus sessions. The horae CLI was not detected. Please install it using one of the options below:"
                )
                color: root.dim
                font.pixelSize: Style.font.caption
                lineHeight: 1.35
              }
            }
          }

          // Option 1: Automatic Terminal Install Button
          Rectangle {
            width: parent.width
            implicitHeight: opt1Col.implicitHeight + Style.space(18)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
            color: Util.alpha(root.fg, 0.03)
            border.width: 1
            border.color: Util.alpha(root.fg, 0.08)

            Column {
              id: opt1Col
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              PlainText {
                text: root.i18n("途径一：在终端中一键自动安装（推荐）", "Option 1: One-click Terminal Install (Recommended)")
                color: root.fg
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Button {
                width: parent.width
                iconText: "󰞷"
                text: root.i18n("打开终端自动执行安装", "Launch Terminal & Install")
                foreground: root.accent
                background: Util.alpha(root.accent, 0.12)
                bordered: true
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(8)
                tooltipText: root.i18n("调用 Omarchy 默认终端执行 cargo install", "Open Omarchy terminal and run cargo install")
                onClicked: {
                  if (root.bar) {
                    var script = "echo '==> Installing Horae CLI via Cargo...'; cargo install --git https://github.com/zhaohang1205/horae.git --rev 805dd02f72654d36d6a21d5f2a5a94b475665d8b && echo -e '\\n✅ Horae installed successfully! Press Enter to close this window.' || (echo -e '\\n❌ Installation failed. Please check your Rust environment.'; read -n 1 -s -r -p 'Press any key to close...'); read dummy"
                    var fullCmd = "omarchy-launch-tui bash -c " + shellArg(script)
                    root.bar.run(fullCmd)
                  }
                }
              }
            }
          }

          // Option 2: Copy Cargo Command
          Rectangle {
            width: parent.width
            implicitHeight: opt2Col.implicitHeight + Style.space(18)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
            color: Util.alpha(root.fg, 0.03)
            border.width: 1
            border.color: Util.alpha(root.fg, 0.08)

            Column {
              id: opt2Col
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              PlainText {
                text: root.i18n("途径二：手动复制 Cargo 安装命令", "Option 2: Copy Cargo Command Manually")
                color: root.fg
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Rectangle {
                width: parent.width
                height: Style.space(34)
                radius: 6
                color: Util.alpha(root.bg, 0.6)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.12)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(6)

                  PlainText {
                    width: parent.width - copyBtn.width - Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "cargo install --git https://github.com/zhaohang1205/horae.git --rev 805dd02f72654d36d6a21d5f2a5a94b475665d8b"
                    color: root.dim
                    font.pixelSize: Style.font.caption
                    font.family: root.fontFamily
                    elide: Text.ElideMiddle
                  }

                  Button {
                    id: copyBtn
                    iconText: root.commandCopied ? "󰄬" : "󰆏"
                    text: root.commandCopied ? root.i18n("已复制", "Copied") : root.i18n("复制", "Copy")
                    foreground: root.commandCopied ? root.urgent : root.fg
                    background: Util.alpha(root.fg, 0.08)
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(6)
                    onClicked: {
                      Quickshell.execDetached(["wl-copy", "cargo install --git https://github.com/zhaohang1205/horae.git --rev 805dd02f72654d36d6a21d5f2a5a94b475665d8b"])
                      root.commandCopied = true
                      copyFeedbackTimer.restart()
                    }
                  }
                }
              }
            }
          }

          // Bottom Action Row
          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - Style.space(8)) / 2
              iconText: "󰑐"
              text: root.i18n("重新检测后端", "Check Again")
              foreground: root.fg
              background: Util.alpha(root.fg, 0.08)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(6)
              tooltipText: root.i18n("刷新并重新检测 horae CLI 是否就绪", "Probe again for horae CLI binary")
              onClicked: root.startProbe()
            }

            Button {
              width: (parent.width - Style.space(8)) / 2
              iconText: "󰖟"
              text: root.i18n("查看详细文档", "View Docs")
              foreground: root.dim
              background: Util.alpha(root.fg, 0.04)
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(6)
              tooltipText: root.i18n("在浏览器中打开 GitHub 仓库", "Open GitHub repository in browser")
              onClicked: {
                if (root.bar) {
                  root.bar.run("xdg-open https://github.com/zhaohang1205/horae_for_omarchy_shell")
                }
              }
            }
          }
        }

        // --- Top Header Bar ---
        Item {
          width: parent.width
          height: Style.space(26)
          visible: root.horaeInstalled && !root.showPomoSettings

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            PlainText {
              text: "󰔛"
              color: root.accent
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            PlainText {
              text: root.i18n("Horae 任务专注", "Horae Tasks & Focus")
              color: root.fg
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              visible: root.windowTasks.length > 0
              implicitWidth: taskCountText.implicitWidth + Style.space(10)
              implicitHeight: Style.space(16)
              radius: height / 2
              color: Util.alpha(root.fg, 0.08)
              anchors.verticalCenter: parent.verticalCenter

              TabularText {
                id: taskCountText
                anchors.centerIn: parent
                text: String(root.windowTasks.length)
                color: root.dim
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            // Transient Action Feedback Toast Pill
            Rectangle {
              id: feedbackPill
              visible: opacity > 0.01
              opacity: root.actionFeedbackText !== "" ? 1.0 : 0.0
              implicitWidth: feedbackText.implicitWidth + Style.space(10)
              implicitHeight: Style.space(18)
              radius: height / 2
              color: Util.alpha(root.actionFeedbackColor, 0.16)
              border.width: 1
              border.color: Util.alpha(root.actionFeedbackColor, 0.35)
              anchors.verticalCenter: parent.verticalCenter
              Behavior on opacity {
                NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
              }

              PlainText {
                id: feedbackText
                anchors.centerIn: parent
                text: root.actionFeedbackText
                color: root.actionFeedbackColor
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
              tooltipText: root.privacyMode
                ? root.i18n("隐私模式：已开启", "Privacy Mode: On")
                : root.i18n("隐私模式：已关闭", "Privacy Mode: Off")
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
          visible: root.horaeInstalled && root.showPomoSettings

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

            PlainText {
              text: root.i18n("番茄钟设置", "Pomodoro Settings")
              color: root.fg
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

            PlainText {
              text: root.isChinese ? "中" : "EN"
              color: root.fg
              opacity: 0.75
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
          visible: root.horaeInstalled && !root.showPomoSettings
          implicitHeight: heroCardCol.implicitHeight + Style.space(20)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
          color: Util.alpha(root.fg, 0.04)
          border.width: 1
          border.color: root.pomoRunning ? Util.alpha(root.phaseColor, 0.25) : Util.alpha(root.fg, 0.08)
          Behavior on border.color {
            ColorAnimation { duration: Style.duration(220) }
          }

          Column {
            id: heroCardCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            // Running mode: live countdown, phase pill, active task subtitle, cycle dots and progress ring
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

                PlainText {
                  anchors.centerIn: parent
                  text: root.pomoBreaking ? "󰛄" : "󰔛"
                  color: root.phaseColor
                  font.pixelSize: Style.font.title
                }

                SequentialAnimation on opacity {
                  running: root.pomoRunning && !Style.reduceMotion
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
                  width: parent.width

                  TabularText {
                    text: root.formatCountdown(root.pomoRemainingSecs)
                    color: root.phaseColor
                    font.pixelSize: Style.font.displayLarge
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color {
                      ColorAnimation { duration: Style.duration(250) }
                    }
                  }

                  StatusPill {
                    text: root.phaseLabel()
                    pillColor: root.phaseColor
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  // Long break cycle dots aligned right of phase pill
                  Row {
                    id: heroCycleDots
                    spacing: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                      model: Math.max(1, root.pomoLongBreakInterval)
                      delegate: Rectangle {
                        required property int index
                        width: Style.space(6)
                        height: Style.space(6)
                        radius: width / 2
                        color: index < root.cycleDotsFilled ? root.phaseColor : Util.alpha(root.fg, 0.18)
                        border.width: 1
                        border.color: index < root.cycleDotsFilled ? root.phaseColor : Util.alpha(root.fg, 0.3)
                        Behavior on color {
                          ColorAnimation { duration: Style.duration(250) }
                        }
                      }
                    }
                  }
                }

                // Active task subtitle during focus session
                Row {
                  width: parent.width
                  spacing: Style.space(5)
                  visible: root.pomoTaskTitle !== ""

                  PlainText {
                    text: "󰓾"
                    color: root.phaseColor
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PlainText {
                    width: parent.width - Style.space(18)
                    text: root.privacyMode ? "••••••" : root.pomoTaskTitle
                    color: root.fg
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                // Running stats row using reusable StatBadge
                Row {
                  spacing: Style.space(6)
                  width: parent.width

                  StatBadge {
                    text: root.i18n("今日 " + root.pomoTodayCount, "Today " + root.pomoTodayCount)
                  }

                  StatBadge {
                    text: root.i18n("连续 " + root.pomoStreak, "Streak " + root.pomoStreak)
                  }

                  StatBadge {
                    text: root.i18n("累计 " + root.pomoTotalCount, "Total " + root.pomoTotalCount)
                  }
                }
              }
            }

            // Idle mode: status header row + metrics row
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: !root.pomoRunning

              Item {
                width: parent.width
                height: Style.space(22)

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  PlainText {
                    text: "󰔛"
                    color: root.accent
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PlainText {
                    text: root.selectedTask
                      ? root.i18n("准备专注选中任务", "Ready to Focus on Task")
                      : root.i18n("心流就绪", "Ready to Focus")
                    color: root.fg
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                // Clickable preset badge that opens Pomodoro Settings
                Rectangle {
                  id: idlePresetPill
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: idlePresetText.implicitWidth + Style.space(10)
                  implicitHeight: Style.space(18)
                  radius: height / 2
                  color: presetMouse.containsMouse ? Util.alpha(root.accent, 0.22) : Util.alpha(root.accent, 0.12)
                  border.width: 1
                  border.color: Util.alpha(root.accent, 0.35)
                  Behavior on color {
                    ColorAnimation { duration: Style.duration(120) }
                  }

                  TabularText {
                    id: idlePresetText
                    anchors.centerIn: parent
                    text: root.pomoWorkMins + "m · " + root.pomoShortBreakMins + "m"
                    color: root.accent
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showPomoSettings = true
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                StatBadge {
                  text: root.i18n("今日 " + root.pomoTodayCount, "Today " + root.pomoTodayCount)
                  anchors.verticalCenter: parent.verticalCenter
                }

                StatBadge {
                  text: root.i18n("连续 " + root.pomoStreak, "Streak " + root.pomoStreak)
                  anchors.verticalCenter: parent.verticalCenter
                }

                StatBadge {
                  text: root.i18n("累计 " + root.pomoTotalCount, "Total " + root.pomoTotalCount)
                  anchors.verticalCenter: parent.verticalCenter
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
                     ? root.i18n("专注选中任务", "Focus on selected task")
                     : root.i18n("开始专注", "Start focus session"))
                enabled: root.pomoRunning || root.selectedTask !== null || root.windowTasks.length > 0
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
                tooltipText: root.i18n("启动闪念录入窗口", "Launch Quick Capture")
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
                tooltipText: root.i18n("打开 Horae 终端界面", "Open Horae TUI")
                onClicked: root.openTui()
              }
            }
          }
        }

        // --- Pomodoro settings (One-click Rhythm Presets + 2x2 NumberField grid) ---
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.horaeInstalled && root.showPomoSettings

          PlainText {
            text: root.i18n("快捷专注节律预设：", "Quick Focus Rhythm Presets:")
            color: root.dim
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            readonly property real presetBtnW: Math.floor((width - 2 * spacing) / 3)

            Button {
              width: parent.presetBtnW
              readonly property bool isCurrent: root.pomoWorkMins === 25 && root.pomoShortBreakMins === 5 && root.pomoLongBreakMins === 15
              iconText: "󰔛"
              text: root.i18n("经典 25/5", "Classic 25/5")
              foreground: isCurrent ? root.accent : root.fg
              background: isCurrent ? Util.alpha(root.accent, 0.16) : Util.alpha(root.fg, 0.06)
              bordered: isCurrent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(4)
              onClicked: root.savePomoConfig(25, 5, 15, 4)
            }

            Button {
              width: parent.presetBtnW
              readonly property bool isCurrent: root.pomoWorkMins === 50 && root.pomoShortBreakMins === 10 && root.pomoLongBreakMins === 20
              iconText: "󰓅"
              text: root.i18n("深度 50/10", "Deep 50/10")
              foreground: isCurrent ? root.accent : root.fg
              background: isCurrent ? Util.alpha(root.accent, 0.16) : Util.alpha(root.fg, 0.06)
              bordered: isCurrent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(4)
              onClicked: root.savePomoConfig(50, 10, 20, 3)
            }

            Button {
              width: parent.presetBtnW
              readonly property bool isCurrent: root.pomoWorkMins === 15 && root.pomoShortBreakMins === 3 && root.pomoLongBreakMins === 10
              iconText: "󱐋"
              text: root.i18n("冲刺 15/3", "Sprint 15/3")
              foreground: isCurrent ? root.accent : root.fg
              background: isCurrent ? Util.alpha(root.accent, 0.16) : Util.alpha(root.fg, 0.06)
              bordered: isCurrent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(4)
              onClicked: root.savePomoConfig(15, 3, 10, 4)
            }
          }

          PlainText {
            text: root.i18n("微调专注与休息周期参数，自动同步到本地配置：", "Tune focus and break cycles, synced locally:")
            color: root.dim
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.space(12)
            readonly property real colW: Math.floor((width - spacing) / 2)

            NumberField {
              width: parent.colW
              fieldWidth: width
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
              width: parent.colW
              fieldWidth: width
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
            readonly property real colW: Math.floor((width - spacing) / 2)

            NumberField {
              width: parent.colW
              fieldWidth: width
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
              width: parent.colW
              fieldWidth: width
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
              text: root.settingsSavedNotice ? root.i18n("已保存设置 ✓", "Saved ✓") : root.i18n("保存设置", "Save Settings")
              foreground: root.accent
              background: root.settingsSavedNotice ? Util.alpha(root.accent, 0.28) : Util.alpha(root.accent, 0.16)
              bordered: true
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(4)
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval)
            }
          }
        }

        // --- Selected task details card (Master-Detail Header Card) ---
        Rectangle {
          id: selectedTaskCard
          width: parent.width
          visible: root.horaeInstalled && !root.showPomoSettings && root.selectedTask !== null
          implicitHeight: selectedCol.implicitHeight + Style.space(18)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
          readonly property bool isUrgentSelected: root.selectedTask !== null && root.isUrgent(root.selectedTask)
          color: isUrgentSelected ? Util.alpha(root.urgent, 0.06) : Util.alpha(root.accent, 0.04)
          border.width: 1
          border.color: isUrgentSelected ? Util.alpha(root.urgent, 0.36) : Util.alpha(root.accent, 0.24)
          Behavior on color {
            ColorAnimation { duration: Style.duration(180) }
          }
          Behavior on border.color {
            ColorAnimation { duration: Style.duration(180) }
          }

          Column {
            id: selectedCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              PlainText {
                id: selectedTaskIcon
                text: root.selectedTask ? root.taskIcon(root.selectedTask) : ""
                color: root.statusColor(root.selectedTask)
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                width: Math.max(Style.space(80), parent.width - selectedTaskIcon.width - heroStatusPill.width - closeSelectBtn.width - parent.spacing * 3)
                text: root.selectedTask ? String(root.selectedTask.title || "") : ""
                color: root.fg
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              StatusPill {
                id: heroStatusPill
                text: root.selectedTask ? root.taskStatus(root.selectedTask) : ""
                pillColor: root.statusColor(root.selectedTask)
                anchors.verticalCenter: parent.verticalCenter
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
                tooltipText: root.i18n("取消选中", "Clear selection")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.selectedTaskId = ""
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              PlainText {
                text: "󰃰"
                color: root.dim
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              TabularText {
                text: root.selectedTask
                  ? (root.timeLabel(root.selectedTask) + ": " + root.formatDue(root.taskTime(root.selectedTask)))
                  : "-"
                color: root.dim
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                visible: root.selectedTask !== null && root.taskTime(root.selectedTask) > 0
                implicitWidth: relTimeText.implicitWidth + Style.space(8)
                implicitHeight: Style.space(16)
                radius: height / 2
                color: Util.alpha(root.statusColor(root.selectedTask), 0.12)
                anchors.verticalCenter: parent.verticalCenter

                TabularText {
                  id: relTimeText
                  anchors.centerIn: parent
                  text: root.selectedTask ? root.formatRelativeTime(root.taskTime(root.selectedTask)) : ""
                  color: root.statusColor(root.selectedTask)
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
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
                tooltipText: root.i18n("标记完成", "Mark Done")
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
                tooltipText: root.i18n("延迟 1 小时", "+1 Hour")
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
                tooltipText: root.i18n("归档此任务", "Archive task")
                onClicked: root.archiveSelected()
              }
            }
          }
        }

        // --- Always-visible Upcoming Tasks Queue (Master List) ---
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.horaeInstalled && !root.showPomoSettings

          Item {
            width: parent.width
            height: Style.space(22)
            visible: root.windowTasks.length > 0

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              PlainText {
                text: root.i18n("近期排程 / 待办队列", "Upcoming Tasks Queue")
                color: root.fg
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                id: windowScopePill
                implicitWidth: windowScopeRow.implicitWidth + Style.space(8)
                implicitHeight: Style.space(16)
                radius: height / 2
                color: Util.alpha(root.fg, 0.06)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.12)
                anchors.verticalCenter: parent.verticalCenter

                Row {
                  id: windowScopeRow
                  anchors.centerIn: parent
                  spacing: Style.space(3)

                  PlainText {
                    text: "󰃰"
                    color: root.accent
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PlainText {
                    text: root.windowScopeText
                    color: root.dim
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            TabularText {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.i18n(
                "共 " + root.windowTasks.length + " 项",
                root.windowTasks.length + (root.windowTasks.length === 1 ? " task" : " tasks")
              )
              color: root.dim
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // Empty state when no tasks are queued in active window
          Item {
            width: parent.width
            height: Style.space(64)
            visible: root.windowTasks.length === 0

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
              color: Util.alpha(root.fg, 0.03)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.06)
            }

            Row {
              anchors.centerIn: parent
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(26)
                height: Style.space(26)
                radius: width / 2
                color: Util.alpha(root.accent, 0.14)
                anchors.verticalCenter: parent.verticalCenter

                PlainText {
                  anchors.centerIn: parent
                  text: "󰃰"
                  color: root.accent
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                PlainText {
                  text: root.i18n(
                    "时间窗口（" + root.windowScopeText + "）内无待办",
                    "No tasks in active window (" + root.windowScopeText + ")"
                  )
                  color: root.fg
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                PlainText {
                  text: root.i18n(
                    "仅展示过去 " + root.windowBackHours + "h 逾期与未来 " + root.windowFwdHours + "h 排程 · 更多请打开 TUI",
                    "Showing past " + root.windowBackHours + "h overdue to next " + root.windowFwdHours + "h scheduled · Open TUI for all"
                  )
                  color: root.dim
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // Bounded scrollable list of windowTasks
          Flickable {
            id: tasksListFlick
            width: parent.width
            visible: root.windowTasks.length > 0
            readonly property real maxListHeight: root.selectedTask !== null ? Style.space(146) : Style.space(220)
            height: Math.min(tasksListColumn.implicitHeight, maxListHeight)
            contentWidth: width
            contentHeight: tasksListColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: tasksListColumn
              width: parent.width
              spacing: Style.space(3)

              Repeater {
                model: root.windowTasks
                delegate: Item {
                  id: taskRow
                  required property var modelData
                  required property int index
                  property var taskData: modelData
                  readonly property bool isRowSelected: root.selectedTaskId !== "" && String(taskData.id) === root.selectedTaskId
                  readonly property bool isRowWorking: root.workingTaskId !== "" && String(taskData.id) === root.workingTaskId
                  readonly property color rowStatusCol: root.statusColor(taskData)
                  readonly property bool isRowHovered: rowHover.hovered
                  width: tasksListColumn.width
                  height: Style.space(34)

                  HoverHandler {
                    id: rowHover
                  }

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                    color: taskRow.isRowSelected
                      ? Util.alpha(root.accent, 0.13)
                      : (taskRow.isRowHovered ? Style.hoverFillFor(root.fg, root.accent) : Util.alpha(root.fg, 0.02))
                    border.width: 1
                    border.color: taskRow.isRowSelected
                      ? Util.alpha(root.accent, 0.42)
                      : (taskRow.isRowHovered ? Util.alpha(root.accent, 0.25) : "transparent")
                    Behavior on color {
                      ColorAnimation { duration: Style.duration(120) }
                    }
                    Behavior on border.color {
                      ColorAnimation { duration: Style.duration(120) }
                    }
                  }

                  // Left active accent bar for selected/working task
                  Rectangle {
                    visible: taskRow.isRowSelected || taskRow.isRowWorking
                    width: Style.space(3)
                    height: Style.space(18)
                    radius: width / 2
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    color: taskRow.isRowWorking ? root.phaseColor : root.accent
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.selectedTaskId = String(taskRow.taskData.id)
                    }
                    onDoubleClicked: {
                      root.startTaskFocus(taskRow.taskData)
                    }
                  }

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: (taskRow.isRowSelected || taskRow.isRowWorking) ? Style.space(10) : Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Rectangle {
                      id: rowIconBox
                      width: Style.space(22)
                      height: Style.space(22)
                      radius: 4
                      color: Util.alpha(taskRow.rowStatusCol, 0.14)
                      anchors.verticalCenter: parent.verticalCenter

                      PlainText {
                        anchors.centerIn: parent
                        text: root.taskIcon(taskRow.taskData)
                        color: taskRow.rowStatusCol
                        font.pixelSize: Style.font.caption
                      }
                    }

                    PlainText {
                      width: Math.max(
                        Style.space(60),
                        parent.width - rowIconBox.width - rowRightCluster.width - parent.spacing * 2
                      )
                      text: String(taskRow.taskData.title || "")
                      color: root.isUrgent(taskRow.taskData) ? root.urgent : root.fg
                      font.pixelSize: Style.font.bodySmall
                      font.bold: taskRow.isRowSelected || taskRow.isRowWorking
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                      id: rowRightCluster
                      readonly property real actionsWidth: rowQuickActions.implicitWidth
                      readonly property real timeWidth: taskRowTimePill.implicitWidth
                      width: taskRow.isRowHovered ? Math.max(actionsWidth, timeWidth) : (root.taskTime(taskRow.taskData) > 0 ? timeWidth : 0)
                      height: parent.height
                      anchors.verticalCenter: parent.verticalCenter

                      // Due time & relative time pill (default state)
                      Rectangle {
                        id: taskRowTimePill
                        visible: !taskRow.isRowHovered && root.taskTime(taskRow.taskData) > 0
                        implicitWidth: taskRowTime.implicitWidth + Style.space(10)
                        implicitHeight: Style.space(18)
                        radius: height / 2
                        color: Util.alpha(taskRow.rowStatusCol, root.isUrgent(taskRow.taskData) ? 0.15 : 0.08)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        TabularText {
                          id: taskRowTime
                          anchors.centerIn: parent
                          text: root.formatDueTime(root.taskTime(taskRow.taskData))
                            + (root.taskTime(taskRow.taskData) > 0 ? " · " + root.formatRelativeTime(root.taskTime(taskRow.taskData)) : "")
                          color: root.isUrgent(taskRow.taskData) ? root.urgent : root.dim
                          font.pixelSize: Style.font.caption
                          font.bold: root.isUrgent(taskRow.taskData)
                        }
                      }

                      // Hover inline quick-actions: Start Focus + Complete
                      Row {
                        id: rowQuickActions
                        visible: taskRow.isRowHovered
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        Button {
                          width: Style.space(24)
                          height: Style.space(22)
                          horizontalPadding: 0
                          verticalPadding: 0
                          text: ""
                          iconText: "󰐊"
                          iconSize: Style.font.caption
                          foreground: root.accent
                          background: Util.alpha(root.accent, 0.16)
                          tooltipText: root.i18n("专注此任务", "Focus on this task")
                          onClicked: root.startTaskFocus(taskRow.taskData)
                        }

                        Button {
                          width: Style.space(24)
                          height: Style.space(22)
                          horizontalPadding: 0
                          verticalPadding: 0
                          text: ""
                          iconText: "󰄬"
                          iconSize: Style.font.caption
                          foreground: root.fg
                          background: Util.alpha(root.fg, 0.1)
                          tooltipText: root.i18n("直接标记完成", "Mark done")
                          onClicked: root.completeTaskDirect(taskRow.taskData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Subtle footer indicating active time window rules
          Item {
            width: parent.width
            height: Style.space(16)
            visible: root.windowTasks.length > 0

            Row {
              anchors.centerIn: parent
              spacing: Style.space(4)
              opacity: 0.65

              PlainText {
                text: "󰋽"
                color: root.dim
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                text: root.i18n(
                  "活跃窗口: " + root.windowScopeText + "（仅展示过去 " + root.windowBackHours + "h 逾期与未来 " + root.windowFwdHours + "h 排程）",
                  "Window: " + root.windowScopeText + " (overdue within " + root.windowBackHours + "h ~ upcoming in " + root.windowFwdHours + "h)"
                )
                color: root.dim
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }
  }

  Timer {
    id: copyFeedbackTimer
    interval: 2000
    onTriggered: root.commandCopied = false
  }

  readonly property var candidateBins: [
    String(setting("horaeBin", "")).trim(),
    "horae",
    cargoHoraeBin,
    localHoraeBin,
    "/usr/local/bin/horae",
    "/usr/bin/horae"
  ].filter(function(b) { return b && b !== "" })

  function startProbe() {
    probeIndex = 0
    testNextCandidate()
  }

  function testNextCandidate() {
    if (probeIndex >= candidateBins.length) {
      root.horaeInstalled = false
      root.horaeVersion = ""
      return
    }
    var bin = candidateBins[probeIndex]
    var cmd = [bin]
    if (profile !== "") cmd.push("--profile", profile)
    cmd.push("--version")
    probeHoraeProc.command = cmd
    probeHoraeProc.running = true
  }

  Process {
    id: probeHoraeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var trimmed = text.trim()
        if (trimmed.indexOf("horae") !== -1) {
          root.horaeInstalled = true
          root.horaeVersion = trimmed
          root.resolvedHoraeBin = candidateBins[root.probeIndex]
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.horaeInstalled = true
        root.resolvedHoraeBin = candidateBins[root.probeIndex]
        root.refreshPomo()
        root.refreshTasks()
      } else {
        root.probeIndex++
        root.testNextCandidate()
      }
    }
  }

  property bool tasksRefreshPending: false
  property bool pomoRefreshPending: false

  function refreshTasks() {
    if (!root.horaeInstalled) return
    if (tasksProc.running) {
      tasksRefreshPending = true
      return
    }
    tasksRefreshPending = false
    tasksProc.running = true
  }

  // Re-parse pomo.json (kept warm in pomoWatcher); fall back to the horae
  // process only when the file is missing.
  function refreshPomo() {
    if (!root.horaeInstalled) return
    var raw = typeof pomoWatcher.text === "function" ? pomoWatcher.text() : String(pomoWatcher.text || "")
    if (raw && raw.trim() !== "") {
      applyPomoFile(raw)
      return
    }
    if (pomoProc.running) {
      pomoRefreshPending = true
      return
    }
    pomoRefreshPending = false
    pomoProc.running = true
  }

  Component.onCompleted: {
    root.startProbe()
  }

  Process {
    id: tasksProc
    command: root.command(["alarm", "waybar", "--all", "--limit", String(root.alarmLimit)])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTasks(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 127) {
        root.horaeInstalled = false
      }
      if (root.tasksRefreshPending) {
        root.tasksRefreshPending = false
        refreshTimer.restart()
      }
    }
  }

  Process {
    id: pomoProc
    command: root.command(["pomo", "waybar"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPomo(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 127) {
        root.horaeInstalled = false
      }
      if (root.pomoRefreshPending) {
        root.pomoRefreshPending = false
        pomoRefreshTimer.restart()
      }
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
    onLoaded: pomoRefreshTimer.restart()
    onFileChanged: reload()
  }

  FileView {
    id: tasksWatcher
    path: root.dataDir + "/horae.db"
    watchChanges: true
    printErrors: false
    onLoaded: refreshTimer.restart()
    onFileChanged: refreshTimer.restart()
  }

  // SQLite WAL mode writes transactions into horae.db-wal
  FileView {
    id: tasksWalWatcher
    path: root.dataDir + "/horae.db-wal"
    watchChanges: true
    printErrors: false
    onLoaded: refreshTimer.restart()
    onFileChanged: refreshTimer.restart()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: false
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
