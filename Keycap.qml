import QtQuick
import qs.Commons

// A keycap: a top face sitting on a slightly darker side, as in Shakespeare's menu.
Item {
  id: cap

  property bool active: false
  property bool hovered: false
  property real radius: Style.space(8)
  default property alias content: face.data

  readonly property color faceColor: active ? Color.accent : Util.alpha(Color.foreground, hovered ? .12 : .07)
  readonly property color sideColor: active ? Util.alpha(Color.accent, .55) : Util.alpha(Color.foreground, .04)
  readonly property color ink: active ? Color.background : Color.foreground

  Rectangle {
    anchors.fill: parent
    radius: cap.radius
    color: cap.sideColor
  }

  Rectangle {
    id: face
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height - Style.space(3)
    radius: cap.radius
    color: cap.faceColor
  }
}
