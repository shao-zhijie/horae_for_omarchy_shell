import QtQuick
import Quickshell
import Quickshell.Io
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
  readonly property color textColor: {
    var c = setting("textColor", "")
    return c && String(c).trim() !== "" ? c : fg
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alwaysShow: Boolean(setting("alwaysShow", true))

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

  // Pomodoro Configuration state & helpers
  property bool showPomoSettings: false
  property int pomoWorkMins: 25
  property int pomoShortBreakMins: 5
  property int pomoLongBreakMins: 15
  property int pomoLongBreakInterval: 4

  function syncPomoConfigFromFile() {
    try {
      var raw = typeof pomoWatcher.text === "function" ? pomoWatcher.text() : String(pomoWatcher.text || "")
      if (raw && raw.trim() !== "") {
        var data = JSON.parse(raw)
        if (data && data.config) {
          if (data.config.work_mins) pomoWorkMins = Number(data.config.work_mins)
          if (data.config.short_break_mins) pomoShortBreakMins = Number(data.config.short_break_mins)
          if (data.config.long_break_mins) pomoLongBreakMins = Number(data.config.long_break_mins)
          if (data.config.long_break_interval) pomoLongBreakInterval = Number(data.config.long_break_interval)
        }
      }
    } catch (e) {}
  }

  function savePomoConfig(w, s, l, i) {
    pomoWorkMins = Math.max(1, Math.min(180, w))
    pomoShortBreakMins = Math.max(1, Math.min(60, s))
    pomoLongBreakMins = Math.max(1, Math.min(90, l))
    pomoLongBreakInterval = Math.max(1, Math.min(12, i))
    var dataFile = root.dataDir + "/pomo.json"
    var jqCmd = "jq --argjson w " + pomoWorkMins + " --argjson s " + pomoShortBreakMins + " --argjson l " + pomoLongBreakMins + " --argjson i " + pomoLongBreakInterval +
      " '.config = ((.config // {}) + {\"work_mins\": $w, \"short_break_mins\": $s, \"long_break_mins\": $l, \"long_break_interval\": $i})' " +
      shellArg(dataFile) + " > " + shellArg(dataFile + ".tmp") + " && mv " + shellArg(dataFile + ".tmp") + " " + shellArg(dataFile)
    if (bar) bar.run(jqCmd)
  }

  function displayPomoText() {
    if (!pomoRunning) return "🍅"
    var rawText = String(pomo.text || "🍅")
    if (!privacyMode || !pomo.title) return rawText
    var fullTitle = String(pomo.title)
    var masked = maskTitle(fullTitle)
    var replaced = rawText.replace(fullTitle, masked)
    if (replaced === rawText && fullTitle.length > 14) {
      replaced = rawText.replace(fullTitle.substring(0, 14) + "…", masked)
    }
    return replaced
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
  property var pomo: ({})
  property string selectedTaskId: ""
  property bool popupOpen: false

  readonly property bool pomoRunning: String(pomo.class || "idle") !== "idle"
  readonly property bool pomoWorking: String(pomo.class || "") === "work"
  readonly property string workingTaskId: String(pomo.id || "")
  readonly property var selectedTask: (function() {
    for (var i = 0; i < displayTasks.length; i++)
      if (String(displayTasks[i].id) === selectedTaskId) return displayTasks[i]
    return null
  })()

  readonly property int taskSlotWidth: displayTasks.length === 0 ? 0
    : Math.max(48, Math.floor((maxBarWidth - Style.space(90)) / displayTasks.length))

  visible: alwaysShow || displayTasks.length > 0 || pomoRunning
  implicitWidth: Math.min(row.implicitWidth, maxBarWidth) + Style.space(12)
  implicitHeight: barSize

  readonly property bool revealPrivacyBtn: widgetHover.hovered || (privacyBtnItem && privacyBtnItem.hovering) || (pomoItem && pomoItem.hovering) || root.popupOpen
  readonly property bool revealPomoItem: pomoRunning || displayTasks.length === 0 || widgetHover.hovered || (pomoItem && pomoItem.hovering) || (privacyBtnItem && privacyBtnItem.hovering) || root.popupOpen

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

  function timeFieldLabel(task) {
    if (!task) return ""
    var isStart = isStartTime(task)
    if (isChinese) {
      return (isStart ? "计划开始" : "截止") + (isStart ? "    " : "        ")
    }
    return (isStart ? "Start" : "Due") + (isStart ? "   " : "     ")
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

  function pad2(value) { return (value < 10 ? "0" : "") + value }

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

  function applyPomo(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      pomo = parsed && typeof parsed === "object" ? parsed : {}
    } catch (error) {
      pomo = {}
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
    if (!focused && pomo.title) {
      focused = candidates.filter(function(task) { return String(task.title) === String(pomo.title) })[0]
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

  function runTaskAction(args) {
    if (bar) bar.run(command(args).map(shellArg).join(" "))
    popupOpen = false
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
    if (selectedTask) runTaskAction(["pomo", "start", String(selectedTask.id)])
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

  onVisibleChanged: if (!visible) popupOpen = false

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // Privacy Mode Toggle Button on Bar (revealed on hover)
    Item {
      id: privacyBtnItem
      readonly property bool hovering: privacyMouse.containsMouse
      readonly property real targetWidth: privacyBtnText.implicitWidth + Style.space(8)
      implicitWidth: root.revealPrivacyBtn ? targetWidth : 0
      width: implicitWidth
      implicitHeight: root.barSize
      visible: width > 0.5
      clip: true
      opacity: root.revealPrivacyBtn ? 1.0 : 0.0

      Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 160 }
      }

      Text {
        id: privacyBtnText
        anchors.centerIn: parent
        text: root.privacyMode ? "󰈉" : "󰈈"
        color: privacyMouse.containsMouse ? root.accent : root.textColor
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
        onEntered: if (root.bar) root.bar.showTooltip(root, root.privacyMode ?
          root.i18n("状态栏隐私模式: 开启 (点击关闭)", "Privacy Mode: ON (Click to turn off)") :
          root.i18n("状态栏隐私模式: 关闭 (点击开启)", "Privacy Mode: OFF (Click to turn on)"))
        onExited: if (root.bar) root.bar.hideTooltip(root)
      }
    }

    Repeater {
      model: root.displayTasks
      delegate: taskDelegate
    }

    Item {
      id: pomoSepItem
      visible: root.displayTasks.length > 0 && width > 0.5
      readonly property real targetWidth: pomoSepText.implicitWidth
      implicitWidth: (root.displayTasks.length > 0 && root.revealPomoItem) ? targetWidth : 0
      width: implicitWidth
      implicitHeight: root.barSize
      clip: true
      opacity: (root.displayTasks.length > 0 && root.revealPomoItem) ? 0.3 : 0.0

      Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 160 }
      }

      Text {
        id: pomoSepText
        anchors.centerIn: parent
        text: "│"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: pomoItem
      readonly property bool hovering: pomoMouse.containsMouse
      readonly property real targetWidth: pomoText.implicitWidth + Style.space(8)
      implicitWidth: root.revealPomoItem ? targetWidth : 0
      width: implicitWidth
      implicitHeight: root.barSize
      visible: width > 0.5
      clip: true
      opacity: root.revealPomoItem ? 1.0 : 0.0

      Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 160 }
      }

      Text {
        id: pomoText
        anchors.centerIn: parent
        text: root.displayPomoText()
        color: root.pomoRunning ? (root.pomoWorking ? root.urgent : root.accent) : root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
        Behavior on color {
          ColorAnimation { duration: 200 }
        }

        SequentialAnimation on opacity {
          running: root.pomoWorking
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.5; duration: 800 }
          NumberAnimation { from: 0.5; to: 1.0; duration: 800 }
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
        onEntered: if (root.bar) {
          var pTooltip = String(root.pomo.tooltip || "")
          if (root.privacyMode && root.pomo.title) {
            pTooltip = pTooltip.replace(String(root.pomo.title), root.maskTitle(root.pomo.title))
          }
          var pActionHint = root.i18n("左击快速录入，右击打开 TUI，双击停止", "Left-click: Quick capture, Right-click: TUI, Double-click: Stop")
          root.bar.showTooltip(root, pTooltip !== "" ? (pTooltip + "\n" + pActionHint) : root.i18n("番茄钟 (左击快速录入，右击打开 TUI，双击停止)", "Pomodoro (Left-click for quick capture, Right-click for TUI, Double-click to stop)"))
        }
        onExited: if (root.bar) root.bar.hideTooltip(root)
      }
    }
  }

  Component {
    id: taskDelegate
    Item {
      id: taskItem
      property var task: modelData
      property bool hovering: false
      readonly property bool urgentTask: root.isUrgent(task)
      readonly property bool overdueTask: root.isOverdue(task)
      readonly property bool working: root.workingTaskId !== "" && String(task.id) === root.workingTaskId
      readonly property string timeStr: root.formatDueTime(root.taskTime(task))
      readonly property string label: root.taskIcon(task) + (timeStr !== "" ? " " + timeStr : "") + " " + (root.privacyMode ? root.maskTitle(task.title) : String(task.title || "(untitled)"))
      readonly property real clipWidth: Math.min(taskText.implicitWidth, root.taskSlotWidth)
      implicitWidth: clipWidth + Style.space(8)
      implicitHeight: root.barSize

      Item {
        id: taskClip
        anchors.centerIn: parent
        width: taskItem.clipWidth
        height: root.barSize
        clip: true

        Text {
          id: taskText
          anchors.verticalCenter: parent.verticalCenter
          text: taskItem.label
          width: implicitWidth
          color: taskItem.working ? root.accent : (taskItem.urgentTask ? root.urgent : root.textColor)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: taskItem.working
          readonly property real endX: Math.min(0, taskClip.width - implicitWidth)
          readonly property bool needsScroll: endX < 0

          SequentialAnimation on x {
            running: taskText.needsScroll && !root.popupOpen && taskItem.hovering
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: taskText.endX; duration: 6000 }
            PauseAnimation { duration: 1400 }
            NumberAnimation { from: taskText.endX; to: 0; duration: 6000 }
            PauseAnimation { duration: 1400 }
            onRunningChanged: if (!running) taskText.x = 0
          }
        }
      }

      SequentialAnimation on opacity {
        running: taskItem.urgentTask
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.4; duration: taskItem.overdueTask ? 350 : 600 }
        NumberAnimation { from: 0.4; to: 1.0; duration: taskItem.overdueTask ? 350 : 600 }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) root.openPopupFor(taskItem.task)
        }
        onEntered: {
          taskItem.hovering = true
          if (root.bar) {
            var lbl = root.timeLabel(taskItem.task)
            var tTitle = root.privacyMode ? root.maskTitle(taskItem.task.title) : String(taskItem.task.title || "(untitled)")
            root.bar.showTooltip(root, tTitle + "\n" + lbl + ": " + root.formatDue(root.taskTime(taskItem.task)))
          }
        }
        onExited: {
          taskItem.hovering = false
          if (root.bar) root.bar.hideTooltip(root)
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

      // --- Pomodoro & Plugin Settings Section ---
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.showPomoSettings

        // Settings Header Row
        Row {
          width: parent.width
          height: Math.max(settingsTitleText.implicitHeight, backBtn.implicitHeight)

          Text {
            id: settingsTitleText
            width: parent.width - backBtn.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "🍅 " + root.i18n("番茄钟与插件设置", "Pomodoro & Settings")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Button {
            id: backBtn
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("返回 ✕", "Back ✕")
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            bordered: true
            onClicked: root.showPomoSettings = false
          }
        }

        PanelSeparator { foreground: root.fg }

        // Parameter 1: Work Duration
        Row {
          width: parent.width
          height: Style.space(26)

          Text {
            width: Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("专注工作", "Work Time")
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "-"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins - 5, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval)
            }

            Text {
              width: Style.space(56)
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: root.pomoWorkMins + " " + root.i18n("分", "m")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "+"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins + 5, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval)
            }
          }

          Item { width: Style.space(8); height: 1 }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: [15, 25, 45, 50]
              delegate: Button {
                width: Style.space(34)
                height: Style.space(22)
                text: String(modelData)
                fontSize: Style.font.caption
                horizontalPadding: 0
                bordered: true
                selected: root.pomoWorkMins === modelData
                accent: root.pomoWorkMins === modelData ? root.accent : root.fg
                onClicked: root.savePomoConfig(modelData, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval)
              }
            }
          }
        }

        // Parameter 2: Short Break
        Row {
          width: parent.width
          height: Style.space(26)

          Text {
            width: Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("短休时间", "Short Break")
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "-"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins - 1, root.pomoLongBreakMins, root.pomoLongBreakInterval)
            }

            Text {
              width: Style.space(56)
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: root.pomoShortBreakMins + " " + root.i18n("分", "m")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "+"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins + 1, root.pomoLongBreakMins, root.pomoLongBreakInterval)
            }
          }

          Item { width: Style.space(8); height: 1 }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: [3, 5, 10, 15]
              delegate: Button {
                width: Style.space(34)
                height: Style.space(22)
                text: String(modelData)
                fontSize: Style.font.caption
                horizontalPadding: 0
                bordered: true
                selected: root.pomoShortBreakMins === modelData
                accent: root.pomoShortBreakMins === modelData ? root.accent : root.fg
                onClicked: root.savePomoConfig(root.pomoWorkMins, modelData, root.pomoLongBreakMins, root.pomoLongBreakInterval)
              }
            }
          }
        }

        // Parameter 3: Long Break
        Row {
          width: parent.width
          height: Style.space(26)

          Text {
            width: Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("长休时间", "Long Break")
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "-"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins - 5, root.pomoLongBreakInterval)
            }

            Text {
              width: Style.space(56)
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: root.pomoLongBreakMins + " " + root.i18n("分", "m")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "+"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins + 5, root.pomoLongBreakInterval)
            }
          }

          Item { width: Style.space(8); height: 1 }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: [10, 15, 20, 30]
              delegate: Button {
                width: Style.space(34)
                height: Style.space(22)
                text: String(modelData)
                fontSize: Style.font.caption
                horizontalPadding: 0
                bordered: true
                selected: root.pomoLongBreakMins === modelData
                accent: root.pomoLongBreakMins === modelData ? root.accent : root.fg
                onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, modelData, root.pomoLongBreakInterval)
              }
            }
          }
        }

        // Parameter 4: Long Break Interval
        Row {
          width: parent.width
          height: Style.space(26)

          Text {
            width: Style.space(80)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("长休轮数", "Interval")
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "-"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval - 1)
            }

            Text {
              width: Style.space(56)
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: root.pomoLongBreakInterval + " " + root.i18n("轮", "cyc")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Button {
              width: Style.space(24)
              height: Style.space(24)
              text: "+"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, root.pomoLongBreakInterval + 1)
            }
          }

          Item { width: Style.space(8); height: 1 }

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: [2, 3, 4, 5]
              delegate: Button {
                width: Style.space(34)
                height: Style.space(22)
                text: String(modelData)
                fontSize: Style.font.caption
                horizontalPadding: 0
                bordered: true
                selected: root.pomoLongBreakInterval === modelData
                accent: root.pomoLongBreakInterval === modelData ? root.accent : root.fg
                onClicked: root.savePomoConfig(root.pomoWorkMins, root.pomoShortBreakMins, root.pomoLongBreakMins, modelData)
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // Privacy Mode Switch
        Row {
          width: parent.width
          Text {
            width: parent.width - privacyModeToggle.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("状态栏隐私模式 (仅暴露首字/词)", "Status Bar Privacy (First char/word only)")
            color: root.fg
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ToggleSwitch {
            id: privacyModeToggle
            checked: root.privacyMode
            trackHeight: 18
            accent: root.accent
            foreground: root.fg
            cursorRing: false
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.togglePrivacyMode()
          }
        }

        // Language Switch
        Row {
          width: parent.width
          Text {
            width: parent.width - langSettingsToggle.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("界面语言 (中文 / English)", "Interface Language (ZH / EN)")
            color: root.fg
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ToggleSwitch {
            id: langSettingsToggle
            checked: root.isChinese
            trackHeight: 18
            accent: root.accent
            foreground: root.fg
            cursorRing: false
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.toggleLanguage()
          }
        }

        Button {
          width: parent.width
          text: root.i18n("返回任务列表", "Back to Tasks")
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: root.showPomoSettings = false
        }
      }

      // --- Selected Task Details Section ---
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: !root.showPomoSettings && root.selectedTask !== null

        // Header Row: Task Title on left, Privacy + Settings + Language on top-right
        Row {
          width: parent.width
          height: Math.max(taskTitleText.implicitHeight, headerControlsRow.implicitHeight)

          Text {
            id: taskTitleText
            width: parent.width - headerControlsRow.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.selectedTask ? root.taskIcon(root.selectedTask) + "  " + (root.privacyMode ? root.maskTitle(root.selectedTask.title) : root.selectedTask.title) : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Row {
            id: headerControlsRow
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            // Quick Privacy Toggle
            Button {
              width: Style.space(26)
              height: Style.space(22)
              text: root.privacyMode ? "󰈉" : "󰈈"
              fontSize: Style.font.bodySmall
              horizontalPadding: 0
              bordered: true
              accent: root.privacyMode ? root.accent : root.fg
              opacity: root.privacyMode ? 1.0 : 0.6
              tooltipText: root.privacyMode ?
                root.i18n("关闭隐私模式", "Turn off Privacy Mode") :
                root.i18n("开启隐私模式", "Turn on Privacy Mode")
              onClicked: root.togglePrivacyMode()
            }

            // Pomodoro Settings Toggle
            Button {
              width: Style.space(26)
              height: Style.space(22)
              text: "⚙"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              opacity: 0.75
              onClicked: root.showPomoSettings = true
            }

            // Language Toggle Switch
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

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
                trackHeight: 18
                accent: root.accent
                foreground: root.fg
                cursorRing: false
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.toggleLanguage()
              }
            }
          }
        }

        // Key-Value Grid: fixed label width for rock-solid visual baseline in both ZH and EN
        Column {
          width: parent.width
          spacing: Style.space(6)

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              width: Style.space(72)
              text: root.i18n("状态", "Status")
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              text: root.selectedTask ? root.taskStatus(root.selectedTask) : ""
              color: root.isUrgent(root.selectedTask) ? root.urgent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: root.isUrgent(root.selectedTask)
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              width: Style.space(72)
              text: root.selectedTask ? root.timeLabel(root.selectedTask) : root.i18n("时间", "Time")
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              text: root.selectedTask ? root.formatDue(root.taskTime(root.selectedTask)) : "-"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(12)
            Text {
              width: Style.space(72)
              text: root.i18n("标签", "Tags")
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width - Style.space(84)
              text: root.selectedTask ? String(root.selectedTask.tags || "-") : "-"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        // Action Buttons: equal width distribution across the panel width
        Row {
          width: parent.width
          spacing: Style.space(8)
          readonly property real btnW: Math.floor((width - 3 * spacing) / 4)

          Button {
            width: parent.btnW
            text: root.i18n("开启番茄钟", "Pomodoro")
            foreground: root.fg
            accent: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(4)
            bordered: true
            onClicked: root.startSelected()
          }
          Button {
            width: parent.btnW
            text: root.i18n("延迟 1h", "+1h Delay")
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(4)
            bordered: true
            onClicked: root.deferSelected()
          }
          Button {
            width: parent.btnW
            text: root.i18n("完成", "Done")
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(4)
            bordered: true
            onClicked: root.completeSelected()
          }
          Button {
            width: parent.btnW
            text: root.i18n("归档", "Archive")
            foreground: root.fg
            accent: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(4)
            bordered: true
            onClicked: root.archiveSelected()
          }
        }
      }

      // If no task is selected, show Upcoming Tasks list
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: !root.showPomoSettings && root.selectedTask === null && root.displayTasks.length > 0

        // Header with list title and top-right tools
        Row {
          width: parent.width
          height: Math.max(listTitleText.implicitHeight, emptyHeaderControlsRow.implicitHeight)

          Text {
            id: listTitleText
            width: parent.width - emptyHeaderControlsRow.width - Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i18n("近期排程 / 待办任务:", "Upcoming Tasks:")
            color: root.textColor
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Row {
            id: emptyHeaderControlsRow
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            // Quick Privacy Toggle
            Button {
              width: Style.space(26)
              height: Style.space(22)
              text: root.privacyMode ? "󰈉" : "󰈈"
              fontSize: Style.font.bodySmall
              horizontalPadding: 0
              bordered: true
              accent: root.privacyMode ? root.accent : root.fg
              opacity: root.privacyMode ? 1.0 : 0.6
              tooltipText: root.privacyMode ?
                root.i18n("关闭隐私模式", "Turn off Privacy Mode") :
                root.i18n("开启隐私模式", "Turn on Privacy Mode")
              onClicked: root.togglePrivacyMode()
            }

            // Pomodoro Settings Toggle
            Button {
              width: Style.space(26)
              height: Style.space(22)
              text: "⚙"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              opacity: 0.75
              onClicked: root.showPomoSettings = true
            }

            // Language Toggle Switch
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

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
                trackHeight: 18
                accent: root.accent
                foreground: root.fg
                cursorRing: false
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.toggleLanguage()
              }
            }
          }
        }

        Repeater {
          model: root.displayTasks
          delegate: Item {
            property var taskData: modelData
            width: popupContent.width
            implicitHeight: Style.space(26)

            Row {
              anchors.fill: parent
              spacing: Style.space(8)
              Text {
                text: root.taskIcon(taskData)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: String(root.privacyMode ? root.maskTitle(taskData.title) : (taskData.title || ""))
                color: root.isUrgent(taskData) ? root.urgent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width - Style.space(120)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: root.formatDueTime(root.taskTime(taskData))
                color: root.textColor
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openPopupFor(taskData)
            }
          }
        }
      }

      PanelSeparator {
        foreground: root.fg
        visible: !root.showPomoSettings
      }

      // --- Bottom Quick Actions Row (3 buttons) ---
      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: !root.showPomoSettings
        readonly property real bBtnW: Math.floor((width - 2 * spacing) / 3)

        Button {
          width: parent.bBtnW
          text: root.i18n("+ 闪念录入", "+ Flash capture")
          foreground: root.fg
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          bordered: true
          onClicked: root.launchFlashCapture()
        }

        Button {
          width: parent.bBtnW
          text: root.i18n("⚙ 番茄设置", "⚙ Settings")
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          bordered: true
          onClicked: root.showPomoSettings = true
        }

        Button {
          width: parent.bBtnW
          text: root.i18n("打开 TUI", "Open TUI")
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          bordered: true
          onClicked: root.openTui()
        }
      }
    }
  }

  function refreshTasks() {
    if (tasksProc.running) tasksProc.running = false
    tasksProc.running = true
  }

  function refreshPomo() {
    if (pomoProc.running) pomoProc.running = false
    pomoProc.running = true
  }

  Component.onCompleted: {
    root.syncPomoConfigFromFile()
    root.refreshTasks()
    root.refreshPomo()
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
  FileView {
    id: pomoWatcher
    path: root.dataDir + "/pomo.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.syncPomoConfigFromFile(); root.refreshPomo() }
    onLoadFailed: root.refreshPomo()
    onFileChanged: { root.syncPomoConfigFromFile(); root.refreshPomo() }
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

  Timer {
    id: pomoTickTimer
    interval: 1000
    running: root.pomoRunning
    repeat: true
    onTriggered: root.refreshPomo()
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
}
