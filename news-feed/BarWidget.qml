import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var service: pluginApi && pluginApi.mainInstance
        ? pluginApi.mainInstance
        : (pluginApi && pluginApi.newsFeed ? pluginApi.newsFeed : null)
    readonly property int unreadCount: service ? service.unreadCount : 0
    readonly property bool loading: service ? service.loading : false
    readonly property bool hasError: service ? service.hasError : false

    readonly property string screenName: screen && screen.name ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen
        ? Settings.getBarPositionForScreen(screenName)
        : (Settings.data && Settings.data.bar ? Settings.data.bar.position : "top")
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen
        ? Style.getCapsuleHeightForScreen(screenName)
        : Style.capsuleHeight
    readonly property real barFontSize: Style.getBarFontSizeForScreen
        ? Style.getBarFontSizeForScreen(screenName)
        : Style.barFontSize
    readonly property real contentWidth: isBarVertical
        ? capsuleHeight
        : Math.max(capsuleHeight, contentRow.implicitWidth + Style.marginM * 2)
    readonly property real contentHeight: isBarVertical
        ? Math.max(capsuleHeight, contentRow.implicitHeight + Style.marginM * 2)
        : capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    function tooltipText() {
        if (!service) {
            return "News Feed starting";
        }

        return "News Feed - " + service.statusText();
    }

    function togglePanel() {
        if (!pluginApi) {
            return;
        }

        try {
            pluginApi.togglePanel(root.screen, root);
        } catch (e) {
            try {
                pluginApi.openPanel(root.screen, root);
            } catch (err) {
                Logger.w("NewsFeed", "Unable to toggle panel:", err);
            }
        }
    }

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusM
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: root.unreadCount > 0 ? Style.marginS : 0

            Item {
                Layout.preferredWidth: root.barFontSize + 6
                Layout.preferredHeight: root.barFontSize + 6

                NIcon {
                    anchors.centerIn: parent
                    icon: "newspaper"
                    pointSize: root.barFontSize
                    color: root.hasError ? Color.mError : (root.loading ? Color.mPrimary : Color.mOnSurface)

                    NumberAnimation on opacity {
                        running: root.loading
                        from: 0.35
                        to: 1.0
                        duration: 900
                        loops: Animation.Infinite
                        easing.type: Easing.InOutQuad
                    }
                }

                Rectangle {
                    visible: root.hasError
                    width: 6
                    height: 6
                    radius: 3
                    color: Color.mError
                    anchors.right: parent.right
                    anchors.top: parent.top
                }
            }

            Rectangle {
                visible: root.unreadCount > 0
                Layout.preferredWidth: badgeText.implicitWidth + 10
                Layout.preferredHeight: Math.max(18, badgeText.implicitHeight + 6)
                radius: height / 2
                color: Color.mPrimary

                NText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.unreadCount > 99 ? "99+" : root.unreadCount.toString()
                    pointSize: Math.max(8, root.barFontSize - 2)
                    color: Color.mOnPrimary
                    font.weight: Font.Bold
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePanel()
        onEntered: TooltipService.show(root, root.tooltipText(), BarService.getTooltipDirection())
        onExited: TooltipService.hide()
    }
}
