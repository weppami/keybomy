import QtQuick
import qs.Commons
import "Stats.js" as Stats

Item {
  id: view

  property var model
  readonly property var root: model
  readonly property color muted: Util.alpha(Color.foreground, .62)
  readonly property color hairline: Util.alpha(Color.foreground, .12)
  readonly property bool twelveHour: /ap/i.test(Qt.locale().timeFormat(Locale.ShortFormat))

  // Recomputed whenever the panel reloads its files.
  readonly property date now: { root.revision; return new Date() }
  readonly property var last14: Stats.lastDays(root.days, 14, now)
  readonly property var allTime: Stats.summary(root.days)
  readonly property var badges: Stats.badgeStatuses(root.days, now)
  readonly property var next: Stats.nextBadge(root.days, now)
  property int hovered: -1
  property bool confirmingDelete: false

  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(16)

    // Tabs are keycaps; the active one takes the accent colour.
    Row {
      width: parent.width
      spacing: Style.space(8)

      Repeater {
        model: [["stats", "Stats"], ["badges", "Badges"], ["data", "Data"]]

        Keycap {
          id: tabCap
          required property var modelData
          width: (parent.width - Style.space(16)) / 3
          height: Style.space(32)
          active: root.tab === modelData[0]
          hovered: tabMouse.containsMouse

          Label {
            anchors.centerIn: parent
            text: modelData[1]
            color: tabCap.ink
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.Medium
          }
          MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.tab = modelData[0]; view.confirmingDelete = false }
          }
        }
      }
    }

    // Shown until keybomyd is counting.
    Rectangle {
      visible: root.problem !== ""
      width: parent.width
      height: notice.implicitHeight + Style.space(24)
      radius: Style.space(10)
      color: "transparent"
      border.color: Util.alpha(Color.urgent, .6)

      Column {
        id: notice
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(4)
        Label { text: "Not counting yet"; font.pixelSize: Style.font.title; font.weight: Font.Medium }
        Label {
          width: parent.width
          text: root.problem
          wrapMode: Text.Wrap
          color: view.muted
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ------------------------------------------------------------ stats
    Column {
      visible: root.tab === "stats"
      width: parent.width
      spacing: Style.space(16)

      Column {
        readonly property int index: view.hovered >= 0 ? view.hovered : 13
        Label {
          text: Stats.formatNumber(view.last14[parent.index].keys)
          font.pixelSize: Style.space(56)
          font.weight: Font.Light
          font.letterSpacing: -2
        }
        Label {
          text: parent.index === 13 ? "keys today"
            : "keys on " + Qt.formatDate(view.last14[parent.index].date, "dddd, MMMM d")
          color: view.muted
          font.pixelSize: Style.font.subtitle
        }
      }

      // Keys per day, last 14 days. Hover a bar for that day's count.
      Item {
        width: parent.width
        height: bars.implicitHeight

        Row {
          id: bars
          width: parent.width
          spacing: Style.space(4)
          readonly property int peak: Math.max(1, Math.max.apply(null, view.last14.map(function(d) { return d.keys })))
          readonly property int active: view.hovered >= 0 ? view.hovered : 13

          Repeater {
            model: view.last14

            Column {
              required property var modelData
              required property int index
              width: (bars.width - bars.spacing * 13) / 14
              spacing: Style.space(5)

              Rectangle {
                width: parent.width
                height: Style.space(52)
                radius: Style.space(4)
                color: Util.alpha(Color.foreground, .07)

                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  radius: parent.radius
                  height: modelData.keys === 0 ? 0 : Math.max(Style.space(4), parent.height * modelData.keys / bars.peak)
                  color: index === bars.active ? Color.accent : Util.alpha(Color.foreground, .3)
                }
              }
              Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(modelData.date, "ddd").charAt(0)
                color: index === bars.active ? Color.foreground : view.muted
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // One area over all bars, so moving between them never flickers back to today.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onPositionChanged: function(mouse) {
            view.hovered = Math.max(0, Math.min(13, Math.floor(mouse.x / (bars.width / 14))))
          }
          onExited: view.hovered = -1
        }
      }

      Grid {
        width: parent.width
        columns: 2
        spacing: Style.space(10)

        Repeater {
          model: [
            ["STREAK", "" + Stats.streak(root.days, view.now), "days"],
            ["BEST SPEED", view.allTime.bestWPM > 0 ? "" + Math.floor(view.allTime.bestWPM) : "–", "WPM"],
            ["BUSIEST HOUR", Stats.hourLabel(view.allTime.busiestHour, view.twelveHour), ""],
            ["HAMLETS TYPED", Stats.hamlets(view.allTime.textKeys).toFixed(2), ""]
          ]

          Keycap {
            required property var modelData
            width: (parent.width - Style.space(10)) / 2
            height: Style.space(64)
            radius: Style.space(10)

            Column {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.topMargin: Style.space(9)
              spacing: Style.space(2)
              Label {
                text: modelData[0]
                color: view.muted
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.weight: Font.Medium
              }
              Row {
                spacing: Style.space(4)
                Label { id: statValue; text: modelData[1]; font.pixelSize: Style.font.display; font.weight: Font.Light }
                Label {
                  anchors.baseline: statValue.baseline
                  text: modelData[2]
                  color: view.muted
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: view.hairline }

      Column {
        width: parent.width
        spacing: Style.space(8)

        Label {
          text: "FUN FACTS"
          color: view.muted
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
          font.weight: Font.Medium
        }
        Repeater {
          model: {
            var facts = [Stats.travelFact(Stats.travelMetres(view.allTime.keys))]
            var day = Stats.busiestDay(root.days)
            if (day) facts.push("Your busiest day was " + Qt.formatDate(day.date, "ddd, MMM d") + ", with " + Stats.formatNumber(day.keys) + " keys.")
            var words = Math.floor(view.allTime.textKeys / Stats.KEYS_PER_WORD)
            if (words >= 250) facts.push("You've typed about " + Stats.formatNumber(Stats.novelPages(words)) + " pages of a novel so far.")
            return facts
          }
          Label {
            required property string modelData
            width: parent.width
            text: modelData
            wrapMode: Text.Wrap
            color: view.muted
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // ------------------------------------------------------------ badges
    Column {
      id: badgesTab
      visible: root.tab === "badges"
      width: parent.width
      spacing: Style.space(14)

      readonly property int earned: view.badges.filter(function(b) { return b.earnedThisMonthOn }).length

      Column {
        Row {
          spacing: Style.space(8)
          Label { id: earnedLabel; text: "" + badgesTab.earned; font.pixelSize: Style.space(48); font.weight: Font.Light }
          Label {
            anchors.baseline: earnedLabel.baseline
            text: "of " + view.badges.length + " earned in " + Qt.formatDate(view.now, "MMMM")
            color: view.muted
            font.pixelSize: Style.font.subtitle
          }
        }
        Label {
          text: "Progress resets on the 1st. Your collection stays."
          color: view.muted
          font.pixelSize: Style.font.bodySmall
        }
      }

      Column {
        visible: view.next !== null
        width: parent.width
        spacing: Style.space(6)
        Row {
          width: parent.width
          Label { width: parent.width / 2; text: view.next ? "Next: " + view.next.badge.name : ""; font.weight: Font.Medium }
          Label {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: view.next ? Stats.formatNumber(view.next.words) + " / " + Stats.formatNumber(view.next.badge.words) + " words" : ""
            color: view.muted
          }
        }
        Rectangle {
          width: parent.width
          height: Style.space(6)
          radius: height / 2
          color: Util.alpha(Color.foreground, .08)
          Rectangle {
            width: parent.width * (view.next ? view.next.progress : 0)
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
        }
      }
      Label {
        visible: view.next === null
        text: "Every badge earned this month. See you on the 1st."
        color: view.muted
      }

      Rectangle { width: parent.width; height: 1; color: view.hairline }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: view.badges

          Row {
            id: badgeRow
            required property var modelData
            readonly property bool earnedNow: modelData.earnedThisMonthOn !== null
            width: parent.width
            spacing: Style.space(10)
            opacity: earnedNow || modelData.timesEarned > 0 ? 1 : .45

            Keycap {
              id: badgeCap
              width: Style.space(28)
              height: Style.space(28)
              active: badgeRow.earnedNow
              Label {
                anchors.centerIn: parent
                text: badgeRow.earnedNow ? "✓" : (badgeRow.modelData.timesEarned > 0 ? "" + badgeRow.modelData.timesEarned : "·")
                color: badgeCap.ink
                font.pixelSize: Style.font.bodySmall
              }
            }
            Column {
              width: parent.width - Style.space(38)
              Label {
                width: parent.width
                text: modelData.badge.name + "  ·  " + Stats.formatNumber(modelData.badge.words) + " words in a month"
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Medium
              }
              Label {
                width: parent.width
                text: modelData.badge.blurb
                  + (modelData.timesEarned > 0 ? "  Earned " + modelData.timesEarned + (modelData.timesEarned === 1 ? " month." : " months.") : "")
                color: view.muted
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------ data
    Column {
      visible: root.tab === "data"
      width: parent.width
      spacing: Style.space(14)

      Label {
        text: "YOUR DATA"
        color: view.muted
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        font.weight: Font.Medium
      }
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Only per-day counters are stored, in " + root.dataDir.replace(/^\/home\/[^/]+/, "~")
          + ", readable only by you. keybomyd counts presses, never what you type, and has no network access."
        color: view.muted
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        spacing: Style.space(10)

        Keycap {
          width: openLabel.implicitWidth + Style.space(24)
          height: Style.space(30)
          hovered: openMouse.containsMouse
          Label { id: openLabel; anchors.centerIn: parent; text: "Open folder"; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: openMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showData() }
        }
        Keycap {
          width: deleteLabel.implicitWidth + Style.space(24)
          height: Style.space(30)
          hovered: deleteMouse.containsMouse
          Label {
            id: deleteLabel
            anchors.centerIn: parent
            text: view.confirmingDelete ? "Click again to erase everything" : "Delete all data…"
            color: Color.urgent
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: deleteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!view.confirmingDelete) { view.confirmingDelete = true; return }
              view.confirmingDelete = false
              root.deleteAllData()
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: view.hairline }

      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.counting
          ? "keybomyd " + root.live.version + " is counting from " + root.live.devices + (root.live.devices === 1 ? " keyboard." : " keyboards.")
          : root.problem
        color: view.muted
        font.pixelSize: Style.font.bodySmall
      }
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Keybomy is a port of Shakespeare by andreasaez (MIT)."
        color: view.muted
        font.pixelSize: Style.font.caption
      }
    }
  }
}
