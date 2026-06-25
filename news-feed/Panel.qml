import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

import "lib/Utils.js" as Utils

Item {
    id: root

    property var pluginApi: null

    readonly property var geometryPlaceholder: panelContainer
    property real contentPreferredWidth: 760 * Style.uiScaleRatio
    property real contentPreferredHeight: 720 * Style.uiScaleRatio
    readonly property bool allowAttach: true

    readonly property var service: pluginApi && pluginApi.mainInstance
        ? pluginApi.mainInstance
        : (pluginApi && pluginApi.newsFeed ? pluginApi.newsFeed : null)

    property string searchText: ""
    property string activeFilter: "all"
    property string selectedCategoryId: service ? service.lastSelectedCategoryId : "all"
    property var displayItems: []
    property var filterItems: []

    anchors.fill: parent

    Component.onCompleted: refreshDisplay()
    onServiceChanged: {
        selectedCategoryId = service ? service.lastSelectedCategoryId : "all";
        refreshDisplay();
    }
    onSearchTextChanged: refreshDisplay()
    onActiveFilterChanged: refreshDisplay()
    onSelectedCategoryIdChanged: {
        if (service) {
            service.setSelectedCategory(selectedCategoryId);
        }
        refreshDisplay();
    }

    Connections {
        target: root.service
        ignoreUnknownSignals: true

        function onAllItemsChanged() { root.refreshDisplay(); }
        function onReadItemIdsChanged() { root.refreshDisplay(); }
        function onPinnedItemIdsChanged() { root.refreshDisplay(); }
        function onUnreadCountChanged() { root.refreshDisplay(); }
        function onHighlightedCountChanged() { root.refreshDisplay(); }
        function onFeedsChanged() { root.refreshDisplay(); }
        function onCategoriesChanged() { root.refreshDisplay(); }
        function onLoadingChanged() { root.refreshDisplay(); }
        function onHasErrorChanged() { root.refreshDisplay(); }
    }

    function refreshDisplay() {
        if (!service) {
            displayItems = [];
            filterItems = [];
            return;
        }

        displayItems = service.filteredItems(activeFilter, searchText, selectedCategoryId);
        filterItems = [
            { id: "all", label: "All", count: service.allItems.length },
            { id: "unread", label: "Unread", count: service.unreadCount },
            { id: "pinned", label: "Pinned", count: service.pinnedItemIds.length },
            { id: "highlighted", label: "Highlighted", count: service.highlightedCount }
        ];
    }

    function openSettings() {
        if (!pluginApi) {
            return;
        }

        var screen = pluginApi.panelOpenScreen;
        if (screen) {
            pluginApi.closePanel(screen);
            Qt.callLater(function() {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            });
        } else if (pluginApi.withCurrentScreen) {
            pluginApi.withCurrentScreen(function(currentScreen) {
                pluginApi.closePanel(currentScreen);
                Qt.callLater(function() {
                    BarService.openPluginSettings(currentScreen, pluginApi.manifest);
                });
            });
        }
    }

    function errorSummary() {
        if (!service || !service.hasError) {
            return "";
        }

        var failed = service.feeds.filter(function(feed) {
            return feed.lastStatus === "error";
        });

        if (failed.length === 0) {
            return "Some feeds failed to refresh";
        }

        return failed.length + " feed" + (failed.length === 1 ? "" : "s") + " failed: " + failed.map(function(feed) {
            return feed.name;
        }).join(", ");
    }

    function subtitleFor(item) {
        var category = service ? service.categoryById(item.categoryId) : null;
        var parts = [item.feedName || "Feed"];

        if (category && category.id !== "all") {
            parts.push(category.name);
        }
        if (item.publishedAt) {
            parts.push(Utils.relativeTime(item.publishedAt));
        }

        return parts.join(" - ");
    }

    function emptyText() {
        if (!service) {
            return "News Feed is starting";
        }
        if (service.feeds.length === 0) {
            return "No feeds configured";
        }
        if (service.loading) {
            return "Refreshing feeds";
        }
        if (searchText.length > 0) {
            return "No articles match the search";
        }
        return "No articles in this view";
    }

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    NText {
                        text: "News Feed"
                        pointSize: Style.fontSizeL
                        font.weight: Font.Bold
                        color: Color.mOnSurface
                    }

                    NText {
                        text: service ? service.statusText() : "Starting"
                        pointSize: Style.fontSizeS
                        color: Color.mSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    visible: service && service.unreadCount > 0
                    Layout.preferredWidth: unreadBadgeText.implicitWidth + 14
                    Layout.preferredHeight: unreadBadgeText.implicitHeight + 8
                    radius: height / 2
                    color: Color.mPrimary

                    NText {
                        id: unreadBadgeText
                        anchors.centerIn: parent
                        text: service ? service.unreadCount.toString() : "0"
                        pointSize: Style.fontSizeS
                        color: Color.mOnPrimary
                        font.weight: Font.Bold
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 6
                    color: refreshMouse.containsMouse ? Color.mHover : "transparent"

                    NIcon {
                        anchors.centerIn: parent
                        icon: "refresh"
                        pointSize: Style.fontSizeM
                        color: service && service.loading ? Color.mPrimary : Color.mOnSurface

                        RotationAnimation on rotation {
                            running: service && service.loading
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }

                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: service && !service.loading
                        onClicked: service.refresh()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 6
                    color: markAllMouse.containsMouse ? Color.mHover : "transparent"
                    opacity: service && service.unreadCount > 0 ? 1 : 0.45

                    NIcon {
                        anchors.centerIn: parent
                        icon: "checks"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurface
                    }

                    MouseArea {
                        id: markAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: service && service.unreadCount > 0
                        onClicked: service.markAllRead()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 6
                    color: settingsMouse.containsMouse ? Color.mHover : "transparent"

                    NIcon {
                        anchors.centerIn: parent
                        icon: "settings"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurface
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openSettings()
                    }
                }
            }

            NTextInput {
                Layout.fillWidth: true
                placeholderText: "Search title, summary, source, category"
                text: root.searchText
                onTextChanged: root.searchText = text
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: filterRow.implicitHeight
                contentWidth: filterRow.implicitWidth
                contentHeight: filterRow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: filterRow
                    spacing: Style.marginS

                    Repeater {
                        model: root.filterItems

                        delegate: Rectangle {
                            required property var modelData

                            Layout.preferredWidth: filterLabel.implicitWidth + 18
                            Layout.preferredHeight: filterLabel.implicitHeight + 8
                            radius: 6
                            color: root.activeFilter === modelData.id ? Color.mPrimary : Color.mSurfaceVariant
                            border.color: root.activeFilter === modelData.id ? Color.mPrimary : Style.capsuleBorderColor
                            border.width: 1

                            NText {
                                id: filterLabel
                                anchors.centerIn: parent
                                text: modelData.label + (modelData.count > 0 ? " " + modelData.count : "")
                                pointSize: Style.fontSizeS
                                color: root.activeFilter === modelData.id ? Color.mOnPrimary : Color.mOnSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeFilter = modelData.id
                            }
                        }
                    }

                    Repeater {
                        model: service ? service.categories : []

                        delegate: Rectangle {
                            required property var modelData

                            visible: modelData.id !== "all"
                            Layout.preferredWidth: visible ? categoryLabel.implicitWidth + 22 : 0
                            Layout.preferredHeight: visible ? categoryLabel.implicitHeight + 8 : 0
                            radius: 6
                            color: root.selectedCategoryId === modelData.id ? modelData.color : Color.mSurfaceVariant
                            border.color: modelData.color || Style.capsuleBorderColor
                            border.width: 1

                            NText {
                                id: categoryLabel
                                anchors.centerIn: parent
                                text: modelData.name
                                pointSize: Style.fontSizeS
                                color: root.selectedCategoryId === modelData.id ? Color.mOnPrimary : Color.mOnSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedCategoryId = root.selectedCategoryId === modelData.id ? "all" : modelData.id
                            }
                        }
                    }
                }
            }

            NText {
                visible: service && service.hasError
                Layout.fillWidth: true
                text: root.errorSummary()
                pointSize: Style.fontSizeS
                color: Color.mError
                wrapMode: Text.Wrap
            }

            NDivider {
                Layout.fillWidth: true
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: articleList
                    model: root.displayItems
                    spacing: Style.marginS
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: articleDelegate

                        required property var modelData
                        required property int index

                        width: articleList.width
                        height: Math.max(106, articleLayout.implicitHeight + Style.marginM * 2)
                        radius: 8
                        color: itemMouse.containsMouse ? Color.mHover : Color.mSurfaceVariant
                        border.color: modelData.highlighted ? Color.mPrimary : "transparent"
                        border.width: modelData.highlighted ? 1 : 0

                        readonly property bool unread: service ? service.isUnread(modelData) : false
                        readonly property bool pinned: service ? service.isPinned(modelData) : false

                        Rectangle {
                            visible: parent.unread
                            width: 4
                            radius: 2
                            color: Color.mPrimary
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: 0
                            onClicked: service.openItem(modelData)
                        }

                        ColumnLayout {
                            id: articleLayout
                            z: 1
                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            anchors.leftMargin: parent.unread ? Style.marginL : Style.marginM
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginS

                                NText {
                                    text: root.subtitleFor(modelData)
                                    pointSize: Style.fontSizeS
                                    color: Color.mSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    z: 2
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 5
                                    color: pinMouse.containsMouse ? Color.mHover : "transparent"

                                    NIcon {
                                        anchors.centerIn: parent
                                        icon: articleDelegate.pinned ? "pin-filled" : "pin"
                                        pointSize: Style.fontSizeS
                                        color: articleDelegate.pinned ? Color.mPrimary : Color.mSecondary
                                    }

                                    MouseArea {
                                        id: pinMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: service.togglePinned(modelData)
                                    }
                                }
                            }

                            NText {
                                text: modelData.title || "Untitled"
                                pointSize: Style.fontSizeM
                                font.weight: unread ? Font.Bold : Font.Medium
                                color: Color.mOnSurface
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            NText {
                                visible: modelData.summary && modelData.summary.length > 0
                                text: modelData.summary
                                pointSize: Style.fontSizeS
                                color: Color.mSecondary
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            NText {
                                visible: modelData.matchedTerms && modelData.matchedTerms.length > 0
                                text: modelData.matchedTerms.join(", ")
                                pointSize: Style.fontSizeS
                                color: Color.mPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    NText {
                        visible: root.displayItems.length === 0
                        anchors.centerIn: parent
                        text: root.emptyText()
                        pointSize: Style.fontSizeM
                        color: Color.mSecondary
                    }
                }
            }
        }
    }
}
