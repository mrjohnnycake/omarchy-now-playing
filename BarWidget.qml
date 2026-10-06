import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "omarchy.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  property bool popupOpen: false

  function close() { popupOpen = false }
  property real maxLabelWidth: 180

  readonly property bool hasProgress: activePlayer !== null && activePlayer.lengthSupported && activePlayer.length > 0
  readonly property real progressFraction: hasProgress
    ? Math.max(0, Math.min(1, activePlayer.position / activePlayer.length)) : 0

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0))
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var sec = total % 60
    var pad = function(n) { return n < 10 ? "0" + n : String(n) }
    return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
  }

  // MPRIS position is not pushed; poll it while playing for the bar underline and dropdown.
  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.hasProgress && root.activePlayer.isPlaying
    onTriggered: root.activePlayer.positionChanged()
  }

  function desktopEntryFor(player) {
    if (!player) return null
    var id = String(player.desktopEntry || "")
    var name = String(player.identity || "")
    var entry = (id && (DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)))
      || (name && DesktopEntries.heuristicLookup(name))
    if (entry || !name) return entry || null
    var values = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var lower = name.toLowerCase()
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name || "").toLowerCase() === lower) return values[i]
    }
    return null
  }

  function playerIconSource(player) {
    var entry = desktopEntryFor(player)
    var value = entry ? String(entry.icon || "") : ""
    if (bar && bar.shell && bar.shell.appLibrary) return bar.shell.appLibrary.iconSource(value)
    if (!value) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true) || Quickshell.iconPath("application-x-executable", true)
  }

  // --- Cava visualizer (drawn behind the scrolling title) ---
  readonly property int cavaBarCount: 16
  readonly property string cavaConfigPath: decodeURIComponent(String(Qt.resolvedUrl("cava.conf")).replace(/^file:\/\//, ""))
  readonly property bool cavaActive: hasMedia && activePlayer.isPlaying && !bar.vertical
  property var cavaLevels: []

  function updateCava(line) {
    var parts = String(line).split(";")
    var levels = []
    for (var i = 0; i < parts.length && levels.length < cavaBarCount; i++) {
      if (parts[i] === "") continue
      levels.push(Math.max(0, Math.min(1, Number(parts[i]) / 100)))
    }
    cavaLevels = levels
  }

  Process {
    id: cavaProcess
    command: ["cava", "-p", root.cavaConfigPath]
    running: root.cavaActive
    stdout: SplitParser { onRead: function(line) { root.updateCava(line) } }
    onRunningChanged: if (!running) root.cavaLevels = []
  }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // Declared before the Row so it renders behind the title text.
  Item {
    id: cavaLayer
    x: row.x + scrollClip.x
    width: scrollClip.width
    y: Style.space(2)
    height: row.y + scrollClip.y + scrollClip.height - y
    visible: scrollClip.visible && root.cavaLevels.length > 0
    opacity: 0.35

    Row {
      anchors.fill: parent
      spacing: 1

      Repeater {
        model: root.cavaBarCount

        Rectangle {
          required property int index
          width: (cavaLayer.width - (root.cavaBarCount - 1)) / root.cavaBarCount
          height: Math.max(1, cavaLayer.height * (root.cavaLevels[index] || 0))
          anchors.bottom: parent.bottom
          radius: 1
          color: Color.accent

          Behavior on height { NumberAnimation { duration: 60 } }
        }
      }
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    // Wrapper adds extra space between the app icon and the scrolling text.
    Item {
      width: barAppIcon.width + Style.space(4)
      height: barAppIcon.height
      anchors.verticalCenter: parent.verticalCenter
      visible: scrollClip.visible

      Image {
        id: barAppIcon
        width: Style.space(14)
        height: Style.space(14)
        source: root.activePlayer ? root.playerIconSource(root.activePlayer) : ""
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        // Every title scrolls, even ones that fit, as a visual cue that media is playing.
        NumberAnimation on x {
          id: scrollAnim
          running: labelText.text !== "" && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          // Constant speed (~15ms per px travelled) so short and long titles move alike.
          duration: (scrollClip.width + labelText.implicitWidth) * 15
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
          // A stopped animation leaves x mid-scroll; snap back so short titles show from the start.
          onRunningChanged: if (!running) labelText.x = 0
        }
      }
    }
  }

  Item {
    id: barProgress
    x: row.x + scrollClip.x
    y: row.y + scrollClip.y + scrollClip.height + 1
    width: scrollClip.width
    height: 2
    visible: scrollClip.visible && root.hasProgress

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.bar.barForeground
      opacity: 0.2
    }

    Rectangle {
      width: parent.width * root.progressFraction
      height: parent.height
      radius: height / 2
      color: Color.accent
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton

    onClicked: if (root.activePlayer) root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Column {
        id: progress
        width: parent.width
        spacing: Style.space(4)
        visible: root.hasProgress

        Item {
          width: parent.width
          height: Style.space(4)

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.bar.foreground
            opacity: 0.15
          }

          Rectangle {
            width: parent.width * root.progressFraction
            height: parent.height
            radius: height / 2
            color: Color.accent
          }
        }

        Item {
          width: parent.width
          height: elapsedText.implicitHeight

          Text {
            id: elapsedText
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.hasProgress ? root.formatTime(root.activePlayer.position) : ""
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.hasProgress ? root.formatTime(root.activePlayer.length) : ""
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Image {
                width: Style.space(20)
                height: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                source: root.playerIconSource(sourceRow.player)
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }

              Column {
                width: parent.width - Style.space(54)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

          }
        }
      }
    }
  }
}
