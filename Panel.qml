import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Stats.js" as Stats

Panel {
  id: root
  moduleName: "keybomy"
  ipcTarget: "keybomy"

  property var anchorItem: null
  property var hostWidget: null

  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/keybomy"

  property var stats: ({ days: {} })
  property var live: null
  // Bumped at midnight and on every reload so date-dependent bindings refresh.
  property int revision: 0
  property string tab: "stats"

  readonly property var days: { revision; return Stats.merge(stats, live) }
  readonly property int today: { revision; return Stats.keysOn(days, new Date()) }

  // keybomyd rewrites live.json at least once a minute while it runs.
  readonly property bool counting: live !== null && live.updated > 0
    && Date.now() / 1000 - live.updated < 150 && (live.devices || 0) > 0
  readonly property string problem: {
    revision
    if (live === null) return "keybomyd isn't running. Run install.sh in the keybomy folder."
    if (Date.now() / 1000 - live.updated >= 150) return "keybomyd stopped. Check: systemctl status keybomyd"
    if (!live.devices) return "No keyboard found. Plug one in and it's picked up within seconds."
    return ""
  }

  readonly property string label: {
    var count = setting("compact", true) ? Stats.compact(today) : Stats.formatNumber(today)
    var icon = setting("icon", "󰌌")
    return icon ? icon + " " + count : count
  }
  readonly property string tooltip: counting
    ? Stats.formatNumber(today) + " keys today · " + Stats.streak(days, new Date()) + "-day streak"
    : problem

  function reloadAll() {
    statsFile.reload()
    liveFile.reload()
  }

  function parse(text, fallback) {
    try { return JSON.parse(text) } catch (e) { return fallback }
  }

  function openFromHotkey() {
    root.tab = "stats"
    reloadAll()
    root.controller.show()
  }

  function toggle() {
    if (opened) close()
    else openFromHotkey()
  }

  function close() {
    root.controller.hide()
  }

  // keybomyd owns the stats file, so deleting goes through it: it erases
  // everything on its next device scan (within five seconds).
  function deleteAllData() {
    Quickshell.execDetached(["touch", root.dataDir + "/reset"])
    root.stats = { days: {} }
    root.live = null
    Qt.callLater(function() { resetSettle.restart() })
  }

  function showData() {
    Quickshell.execDetached(["xdg-open", root.dataDir])
  }

  FileView {
    id: statsFile
    path: root.dataDir + "/stats.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.stats = root.parse(text(), { days: {} }); root.revision++ }
    onLoadFailed: { root.stats = { days: {} }; root.revision++ }
  }

  FileView {
    id: liveFile
    path: root.dataDir + "/live.json"
    printErrors: false
    onLoaded: { root.live = root.parse(text(), null); root.revision++ }
    onLoadFailed: { root.live = null; root.revision++ }
  }

  // live.json is replaced atomically every couple of seconds while you type;
  // polling a tiny file is simpler and sturdier than following the renames.
  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: liveFile.reload()
  }

  Timer {
    id: resetSettle
    interval: 6000
    onTriggered: root.reloadAll()
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: fittedContentWidth(Style.space(360))
    contentHeight: fittedContentHeight(view.implicitHeight)

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar) root.bar.switchPanelFrom(root.hostWidget || root, direction)
      }
      onMoveRequested: function(dx, dy) {
        if (!dx) return
        var tabs = ["stats", "badges", "data"]
        var i = tabs.indexOf(root.tab) + dx
        root.tab = tabs[Math.max(0, Math.min(tabs.length - 1, i))]
      }
      onTextKey: function(text) {
        if (text === "1") root.tab = "stats"
        else if (text === "2") root.tab = "badges"
        else if (text === "3") root.tab = "data"
      }

      StatsView {
        id: view
        anchors.fill: parent
        model: root
      }
    }
  }
}
