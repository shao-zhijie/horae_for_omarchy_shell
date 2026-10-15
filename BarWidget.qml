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

  // Localization helper: auto-detect locale or override with setting("lang", "zh" | "en")
  readonly property bool isChinese: {
    var l = String(setting("lang", "")).toLowerCase().trim()
    if (l.indexOf("zh") === 0) return true
    if (l.indexOf("en") === 0) return false
    var env = (Quickshell.env("LANG") || "").toLowerCase()
    return env.indexOf("zh") === 0
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
    Qt.callLater(captureField.forceActiveFocus)
  }

  function close() {
    popupOpen = false
  }

  function toggle() {
    if (popupOpen) close()
    else open()
  }

  function closeForPopoutSwitch() {
    close()
  }

  property var tasks: []
  property var displayTasks: []
  property var pomo: ({})
  property string selectedTaskId: ""
  property bool popupOpen: false
  property string captureInputText: ""

  // Slot hints calculation: reacts live to what the user types in capture input
  readonly property var activeSlotHints: {
    var text = captureInputText || ""
    var words = text.trim().split(/\s+/)
    var hasTag = false
    var hasTime = false
    var hasRrule = false
    var hasPriority = false

    for (var i = 0; i < words.length; i++) {
      var w = words[i]
      if (w.length <= 1) continue
      var first = w.charAt(0)
      if (first === "@" || first === "＠") hasTag = true
      else if (first === "~" || first === "～" || first === "〜") hasTime = true
      else if (first === "*" || first === "＊" || first === "×") hasRrule = true
      else if (first === "!" || first === "！") hasPriority = true
      else if (/^\d{1,2}:\d{2}$/.test(w)) hasTime = true
    }

    var slots = []
    if (!hasRrule) slots.push({ key: "rrule", prefix: "*", label: isChinese ? "*周期" : "*rrule" })
    if (!hasTime) slots.push({ key: "time", prefix: "~", label: isChinese ? "~时间" : "~time" })
    if (!hasPriority) slots.push({ key: "priority", prefix: "!", label: isChinese ? "!优先级" : "!priority" })
    if (!hasTag) slots.push({ key: "tag", prefix: "@", label: isChinese ? "@标签" : "@tag" })
    return slots
  }

  function submitCapture() {
    var text = captureField.text.trim()
    if (text === "") return
    if (bar) bar.run(command(["capture", text]).map(shellArg).join(" "))
    captureField.text = ""
    captureInputText = ""
    refreshTimer.restart()
    pomoRefreshTimer.restart()
  }

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

  function command(args) {
    var result = [horaeBin]
    if (profile !== "") result.push("--profile", profile)
    return result.concat(args)
  }

  function taskTime(task) {
    return Number(task.due || task.due_at || task.scheduled_start_at || 0)
  }

  function isPending(task) {
    var status = String(task.status || "").toLowerCase()
    return status !== "done" && status !== "archived"
  }

  function taskClass(task) {
    if (task && task.class) return String(task.class)
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
    return taskClass(task) === "alarm-overdue"
  }

  function isUrgent(task) {
    var c = taskClass(task)
    return c === "alarm-now" || c === "alarm-overdue"
  }

  function taskIcon(task) {
    if (!task) return "⏰"
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return "🍅"
    return taskClass(task) === "alarm-now" ? "🔔" : "⏰"
  }

  function taskStatus(task) {
    if (!task) return ""
    if (workingTaskId !== "" && String(task.id) === workingTaskId) return i18n("专注中", "Focusing")
    var c = taskClass(task)
    if (c === "alarm-overdue") return i18n("已逾期", "Overdue")
    if (c === "alarm-now") return i18n("即将到期", "Due soon")
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
    runTaskAction(["schedule", String(selectedTask.id), "--start", formatTimeArg(target)])
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

    // Quick Capture Entry Button on Bar
    Item {
      id: addBtnItem
      implicitWidth: addBtnText.implicitWidth + Style.space(8)
      implicitHeight: root.barSize

      Text {
        id: addBtnText
        anchors.centerIn: parent
        text: "+"
        color: addMouse.containsMouse ? root.accent : root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      MouseArea {
        id: addMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.selectedTaskId = ""
          root.popupOpen = true
          Qt.callLater(captureField.forceActiveFocus)
        }
        onEntered: if (root.bar) root.bar.showTooltip(root, root.i18n("收集新待办 (+)", "Capture new task (+)"))
        onExited: if (root.bar) root.bar.hideTooltip(root)
      }
    }

    Repeater {
      model: root.displayTasks
      delegate: taskDelegate
    }

    Text {
      visible: root.displayTasks.length > 0
      text: "│"
      color: root.textColor
      opacity: 0.3
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }

    Item {
      id: pomoItem
      implicitWidth: pomoText.implicitWidth + Style.space(8)
      implicitHeight: root.barSize

      Text {
        id: pomoText
        anchors.centerIn: parent
        text: String(root.pomo.text || "🍅")
        color: root.pomoRunning ? (root.pomoWorking ? root.urgent : root.accent) : root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
        Behavior on color {
          ColorAnimation { duration: 200 }
        }
      }

      SequentialAnimation on opacity {
        running: root.pomoWorking
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.5; duration: 800 }
        NumberAnimation { from: 0.5; to: 1.0; duration: 800 }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton && root.bar)
            root.bar.run("omarchy-launch-or-focus-tui horae")
        }
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) root.stopPomo()
        }
        onEntered: if (root.bar) root.bar.showTooltip(root, String(root.pomo.tooltip || root.i18n("番茄钟 (右击打开 TUI，双击停止)", "Pomodoro (Right-click opens TUI, double-click stops)")))
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
      readonly property string label: root.taskIcon(task) + (timeStr !== "" ? " " + timeStr : "") + " " + String(task.title || "(untitled)")
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
          if (root.bar) root.bar.showTooltip(root, taskItem.label + "\n" + root.i18n("截止: ", "Due: ") + root.formatDue(root.taskTime(taskItem.task)))
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
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(popupContent.implicitHeight)

    Column {
      id: popupContent
      anchors.fill: parent
      spacing: Style.space(12)

      // --- Quick Capture Section with Live Slot Hints ---
      Column {
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: captureField
            width: parent.width - addBtn.width - Style.space(8)
            placeholderText: root.i18n("收集待办 (例如: 买菜 ~18:00 @生活 !high)...", "Capture task (e.g. Buy milk ~18:00 @home !high)...")
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            foreground: root.fg
            accent: root.accent
            onTextChanged: root.captureInputText = text
            onAccepted: root.submitCapture()
          }

          Button {
            id: addBtn
            text: root.i18n("收集", "Add")
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.submitCapture()
          }
        }

        // Live Slot Hints (卡槽提示)
        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: root.activeSlotHints.length > 0

          Text {
            text: root.i18n("卡槽提示:", "Slots:")
            color: root.textColor
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }

          Repeater {
            model: root.activeSlotHints
            delegate: Item {
              id: slotDelegate
              property var slot: modelData
              implicitWidth: slotLabel.implicitWidth + Style.space(12)
              implicitHeight: Style.space(22)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: slotMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                border.color: slotMouse.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
                border.width: 1
              }

              Text {
                id: slotLabel
                anchors.centerIn: parent
                text: slotDelegate.slot.label
                color: slotMouse.containsMouse ? root.accent : root.fg
                opacity: slotMouse.containsMouse ? 1.0 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: slotMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var cur = captureField.text
                  var sep = (cur.length > 0 && !cur.endsWith(" ")) ? " " : ""
                  captureField.text = cur + sep + slotDelegate.slot.prefix
                  captureField.cursorPosition = captureField.text.length
                  captureField.forceActiveFocus()
                }
              }
            }
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      // --- Selected Task Details Section ---
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.selectedTask !== null

        Text {
          width: parent.width
          text: root.selectedTask ? root.taskIcon(root.selectedTask) + "  " + root.selectedTask.title : ""
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap
          Text {
            text: root.selectedTask ? root.i18n("状态    ", "Status  ") + root.taskStatus(root.selectedTask) : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            text: root.selectedTask ? root.i18n("截止    ", "Due     ") + root.formatDue(root.taskTime(root.selectedTask)) : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            text: root.selectedTask ? root.i18n("标签    ", "Tags    ") + String(root.selectedTask.tags || "-") : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            text: root.i18n("开启番茄钟", "Pomodoro")
            foreground: root.fg
            accent: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.startSelected()
          }
          Button {
            text: root.i18n("延迟 1h", "+1h Delay")
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.deferSelected()
          }
          Button {
            text: root.i18n("完成", "Done")
            foreground: root.fg
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.completeSelected()
          }
          Button {
            text: root.i18n("归档", "Archive")
            foreground: root.fg
            accent: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.archiveSelected()
          }
        }
      }

      // If no task is selected (e.g. opened via + button), show Upcoming Tasks list
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.selectedTask === null && root.displayTasks.length > 0

        Text {
          text: root.i18n("即将到期 / 逾期任务:", "Upcoming / Overdue Tasks:")
          color: root.textColor
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
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
                text: String(taskData.title || "")
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
    onLoaded: root.refreshPomo()
    onLoadFailed: root.refreshPomo()
    onFileChanged: root.refreshPomo()
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
}
