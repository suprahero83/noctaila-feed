import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

import "lib/Utils.js" as Utils

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null
    readonly property var service: pluginApi && pluginApi.mainInstance
        ? pluginApi.mainInstance
        : (pluginApi && pluginApi.newsFeed ? pluginApi.newsFeed : null)
    readonly property var defaults: pluginApi && pluginApi.manifest && pluginApi.manifest.metadata
        ? pluginApi.manifest.metadata.defaultSettings
        : ({})

    property var editFeeds: []
    property var editCategories: []
    property var editRules: []
    property int editRefreshIntervalSec: 900
    property int editMaxItemsPerFeed: 25
    property int editMaxStoredItems: 500
    property bool editShowOnlyUnread: false
    property bool editMarkReadOnOpen: true
    property string editSortMode: "published-desc"
    property string editDedupeMode: "link-title"
    property string settingsStatus: ""
    property string opmlPath: ""

    property string newFeedName: ""
    property string newFeedUrl: ""
    property int newFeedCategoryIndex: 0
    property bool newFeedPinned: false

    property string newCategoryName: ""
    property string newCategoryColor: "#A9AEFE"

    property string newRuleName: ""
    property int newRuleModeIndex: 2
    property string newRuleTerms: ""
    property int newRuleFeedIndex: 0
    property int newRuleCategoryIndex: 0

    property var categoryOptions: []
    property var feedOptions: []
    property var categoryNameOptions: []
    property var feedNameOptions: []
    property var sortModes: ["published-desc", "published-asc", "source"]
    property var sortModeLabels: ["Newest first", "Oldest first", "Source"]
    property var sortModeOptions: [
        { key: "published-desc", name: "Newest first" },
        { key: "published-asc", name: "Oldest first" },
        { key: "source", name: "Source" }
    ]
    property var dedupeModes: ["link-title", "link", "guid", "title", "none"]
    property var dedupeModeLabels: ["Link or title", "Link", "GUID", "Title", "None"]
    property var dedupeModeOptions: [
        { key: "link-title", name: "Link or title" },
        { key: "link", name: "Link" },
        { key: "guid", name: "GUID" },
        { key: "title", name: "Title" },
        { key: "none", name: "None" }
    ]
    property var ruleModes: ["include", "exclude", "highlight"]
    property var ruleModeLabels: ["Include", "Exclude", "Highlight"]
    property var ruleModeOptions: [
        { key: "include", name: "Include" },
        { key: "exclude", name: "Exclude" },
        { key: "highlight", name: "Highlight" }
    ]

    Component.onCompleted: loadState()
    onPluginApiChanged: loadState()

    function currentSettings() {
        return pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings : defaults;
    }

    function loadState() {
        if (!pluginApi) {
            return;
        }

        var settings = currentSettings();
        editFeeds = Utils.deepCopy(Utils.asArray(settings.feeds || defaults.feeds));
        editCategories = ensureAllCategory(Utils.deepCopy(Utils.asArray(settings.categories || defaults.categories)));
        editRules = Utils.deepCopy(Utils.asArray(settings.rules || defaults.rules));
        editRefreshIntervalSec = boundedInt(settings.refreshIntervalSec, defaults.refreshIntervalSec || 900, 60, 86400);
        editMaxItemsPerFeed = boundedInt(settings.maxItemsPerFeed, defaults.maxItemsPerFeed || 25, 1, 200);
        editMaxStoredItems = boundedInt(settings.maxStoredItems, defaults.maxStoredItems || 500, 50, 5000);
        editShowOnlyUnread = settings.showOnlyUnread === undefined ? false : !!settings.showOnlyUnread;
        editMarkReadOnOpen = settings.markReadOnOpen === undefined ? true : !!settings.markReadOnOpen;
        editSortMode = settings.sortMode || "published-desc";
        editDedupeMode = settings.dedupeMode || "link-title";
        refreshOptions();
    }

    function saveSettings() {
        if (!pluginApi) {
            return;
        }

        if (!pluginApi.pluginSettings) {
            pluginApi.pluginSettings = {};
        }

        pluginApi.pluginSettings.feeds = editFeeds;
        pluginApi.pluginSettings.categories = ensureAllCategory(editCategories);
        pluginApi.pluginSettings.rules = editRules;
        pluginApi.pluginSettings.refreshIntervalSec = editRefreshIntervalSec;
        pluginApi.pluginSettings.maxItemsPerFeed = editMaxItemsPerFeed;
        pluginApi.pluginSettings.maxStoredItems = editMaxStoredItems;
        pluginApi.pluginSettings.showOnlyUnread = editShowOnlyUnread;
        pluginApi.pluginSettings.markReadOnOpen = editMarkReadOnOpen;
        pluginApi.pluginSettings.sortMode = editSortMode;
        pluginApi.pluginSettings.dedupeMode = editDedupeMode;

        if (!pluginApi.pluginSettings.readItemIds) {
            pluginApi.pluginSettings.readItemIds = [];
        }
        if (!pluginApi.pluginSettings.pinnedItemIds) {
            pluginApi.pluginSettings.pinnedItemIds = [];
        }
        if (!pluginApi.pluginSettings.lastSelectedCategoryId) {
            pluginApi.pluginSettings.lastSelectedCategoryId = "all";
        }

        pluginApi.saveSettings();

        if (service) {
            service.syncFromSettings(true);
        }

        settingsStatus = "Settings saved";
    }

    function boundedInt(value, fallback, min, max) {
        var number = parseInt(value, 10);
        if (isNaN(number)) {
            number = fallback;
        }
        return Math.max(min, Math.min(max, number));
    }

    function ensureAllCategory(categories) {
        var list = Utils.asArray(categories).slice();
        var hasAll = false;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === "all") {
                hasAll = true;
                list[i].name = list[i].name || "All";
                list[i].color = list[i].color || "#A9AEFE";
            }
        }
        if (!hasAll) {
            list.unshift({ id: "all", name: "All", color: "#A9AEFE" });
        }
        return list;
    }

    function refreshOptions() {
        categoryOptions = ensureAllCategory(editCategories).map(function(category) {
            return {
                key: category.id,
                name: category.name || category.id
            };
        });
        feedOptions = [{ key: "", name: "Any feed" }].concat(editFeeds.map(function(feed) {
            return {
                key: feed.id,
                name: feed.name || feed.url
            };
        }));
        categoryNameOptions = categoryOptions;
        feedNameOptions = feedOptions;
        newFeedCategoryIndex = Math.max(0, Math.min(newFeedCategoryIndex, categoryOptions.length - 1));
        newRuleFeedIndex = Math.max(0, Math.min(newRuleFeedIndex, feedOptions.length - 1));
        newRuleCategoryIndex = Math.max(0, Math.min(newRuleCategoryIndex, categoryOptions.length - 1));
    }

    function categoryNameModel() {
        return categoryNameOptions;
    }

    function feedNameModel() {
        return feedNameOptions;
    }

    function categoryIndexById(categoryId) {
        for (var i = 0; i < categoryOptions.length; i++) {
            if (categoryOptions[i].key === categoryId) {
                return i;
            }
        }
        return 0;
    }

    function categoryKeyAt(index) {
        var option = categoryOptions[index] || categoryOptions[0] || { key: "all" };
        return option.key || "all";
    }

    function feedKeyAt(index) {
        var option = feedOptions[index] || feedOptions[0] || { key: "" };
        return option.key || "";
    }

    function indexByKey(options, key) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].key === key) {
                return i;
            }
        }

        return 0;
    }

    function addFeed() {
        var name = Utils.cleanText(newFeedName);
        var url = Utils.normalizeUrl(newFeedUrl);

        if (!name || !Utils.looksLikeHttpUrl(url)) {
            settingsStatus = "Feed name and HTTP URL are required";
            return;
        }

        for (var i = 0; i < editFeeds.length; i++) {
            if (Utils.normalizeUrl(editFeeds[i].url).toLowerCase() === url.toLowerCase()) {
                settingsStatus = "Feed already exists";
                return;
            }
        }

        var category = categoryOptions[newFeedCategoryIndex] || categoryOptions[0] || { key: "all" };
        var next = editFeeds.slice();
        next.push({
            id: Utils.stableId([url, name]),
            name: name,
            url: url,
            categoryId: category.key || "all",
            enabled: true,
            pinned: newFeedPinned,
            priority: 0,
            lastFetchedAt: "",
            lastStatus: "never",
            lastError: ""
        });
        editFeeds = next;
        newFeedName = "";
        newFeedUrl = "";
        newFeedPinned = false;
        refreshOptions();
        settingsStatus = "Feed added";
    }

    function updateFeed(index, patch) {
        var next = editFeeds.slice();
        if (index < 0 || index >= next.length) {
            return;
        }

        var feed = Utils.deepCopy(next[index]);
        var changed = false;
        for (var key in patch) {
            if (JSON.stringify(feed[key]) !== JSON.stringify(patch[key])) {
                feed[key] = patch[key];
                changed = true;
            }
        }

        if (!changed) {
            return;
        }
        next[index] = feed;
        editFeeds = next;
        refreshOptions();
    }

    function removeFeed(index) {
        var next = editFeeds.slice();
        if (index < 0 || index >= next.length) {
            return;
        }

        var removed = next.splice(index, 1)[0];
        editFeeds = next;
        editRules = editRules.map(function(rule) {
            var copy = Utils.deepCopy(rule);
            copy.feedIds = Utils.asArray(copy.feedIds).filter(function(feedId) {
                return feedId !== removed.id;
            });
            return copy;
        });
        refreshOptions();
        settingsStatus = "Feed removed";
    }

    function addCategory() {
        var name = Utils.cleanText(newCategoryName);
        var color = /^#[0-9A-Fa-f]{6}$/.test(newCategoryColor) ? newCategoryColor : "#A9AEFE";

        if (!name) {
            settingsStatus = "Category name is required";
            return;
        }

        var next = ensureAllCategory(editCategories);
        var id = Utils.stableId([name]);
        for (var i = 0; i < next.length; i++) {
            if (next[i].name.toLowerCase() === name.toLowerCase()) {
                settingsStatus = "Category already exists";
                return;
            }
        }

        next.push({ id: id, name: name, color: color });
        editCategories = next;
        newCategoryName = "";
        refreshOptions();
        settingsStatus = "Category added";
    }

    function removeCategory(index) {
        var next = ensureAllCategory(editCategories);
        if (index <= 0 || index >= next.length) {
            return;
        }

        var removed = next.splice(index, 1)[0];
        editCategories = next;
        editFeeds = editFeeds.map(function(feed) {
            var copy = Utils.deepCopy(feed);
            if (copy.categoryId === removed.id) {
                copy.categoryId = "all";
            }
            return copy;
        });
        editRules = editRules.map(function(rule) {
            var copy = Utils.deepCopy(rule);
            copy.categoryIds = Utils.asArray(copy.categoryIds).filter(function(categoryId) {
                return categoryId !== removed.id;
            });
            return copy;
        });
        refreshOptions();
        settingsStatus = "Category removed";
    }

    function addRule() {
        var terms = newRuleTerms.split(",").map(function(term) {
            return Utils.cleanText(term);
        }).filter(function(term) {
            return term.length > 0;
        });
        var name = Utils.cleanText(newRuleName) || ruleModeLabels[newRuleModeIndex] + " rule";

        if (terms.length === 0) {
            settingsStatus = "Rule terms are required";
            return;
        }

        var feedScope = feedOptions[newRuleFeedIndex] || { id: "" };
        var categoryScope = categoryOptions[newRuleCategoryIndex] || { id: "all" };
        var next = editRules.slice();
        next.push({
            id: Utils.stableId([name, terms.join(","), Date.now()]),
            name: name,
            mode: ruleModes[newRuleModeIndex] || "highlight",
            terms: terms,
            feedIds: feedScope.key ? [feedScope.key] : [],
            categoryIds: categoryScope.key && categoryScope.key !== "all" ? [categoryScope.key] : [],
            enabled: true
        });
        editRules = next;
        newRuleName = "";
        newRuleTerms = "";
        newRuleFeedIndex = 0;
        newRuleCategoryIndex = 0;
        settingsStatus = "Rule added";
    }

    function updateRule(index, patch) {
        var next = editRules.slice();
        if (index < 0 || index >= next.length) {
            return;
        }

        var rule = Utils.deepCopy(next[index]);
        var changed = false;
        for (var key in patch) {
            if (JSON.stringify(rule[key]) !== JSON.stringify(patch[key])) {
                rule[key] = patch[key];
                changed = true;
            }
        }

        if (!changed) {
            return;
        }
        next[index] = rule;
        editRules = next;
    }

    function removeRule(index) {
        var next = editRules.slice();
        if (index < 0 || index >= next.length) {
            return;
        }
        next.splice(index, 1);
        editRules = next;
        settingsStatus = "Rule removed";
    }

    function ruleScopeText(rule) {
        var parts = [];
        if (rule.feedIds && rule.feedIds.length > 0) {
            parts.push(rule.feedIds.length + " feed");
        }
        if (rule.categoryIds && rule.categoryIds.length > 0) {
            parts.push(rule.categoryIds.length + " category");
        }
        return parts.length === 0 ? "All feeds" : parts.join(", ");
    }

    function runImport() {
        if (service && service.importOpml(opmlPath)) {
            loadState();
        }
        settingsStatus = service ? service.lastOpmlStatus : "News Feed is not ready";
    }

    function runExport() {
        if (service) {
            service.exportOpml(opmlPath);
            settingsStatus = service.lastOpmlStatus;
        }
    }

    NLabel {
        Layout.fillWidth: true
        label: "Refresh and Storage"
        description: "Set how often feeds refresh and how much cached state is kept."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NLabel { label: "Refresh interval"; description: "Seconds between automatic refreshes." }
            NSpinBox {
                from: 60
                to: 86400
                value: root.editRefreshIntervalSec
                onValueChanged: root.editRefreshIntervalSec = value
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NLabel { label: "Items per feed"; description: "Maximum articles fetched from each feed." }
            NSpinBox {
                from: 1
                to: 200
                value: root.editMaxItemsPerFeed
                onValueChanged: root.editMaxItemsPerFeed = value
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NLabel { label: "Stored items"; description: "Maximum cached article IDs and items." }
            NSpinBox {
                from: 50
                to: 5000
                value: root.editMaxStoredItems
                onValueChanged: root.editMaxStoredItems = value
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NToggle {
            Layout.fillWidth: true
            label: "Show only unread"
            description: "Make the default panel view unread-only."
            checked: root.editShowOnlyUnread
            onCheckedChanged: root.editShowOnlyUnread = checked
        }

        NToggle {
            Layout.fillWidth: true
            label: "Mark read on open"
            description: "Opening an article marks it read."
            checked: root.editMarkReadOnOpen
            onCheckedChanged: root.editMarkReadOnOpen = checked
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NLabel { label: "Sort"; description: "Article ordering in the panel and launcher." }
            NComboBox {
                Layout.fillWidth: true
                model: root.sortModeOptions
                currentKey: root.editSortMode
                onSelected: key => root.editSortMode = key
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NLabel { label: "Dedupe"; description: "How duplicate articles are collapsed." }
            NComboBox {
                Layout.fillWidth: true
                model: root.dedupeModeOptions
                currentKey: root.editDedupeMode
                onSelected: key => root.editDedupeMode = key
            }
        }
    }

    NDivider { Layout.fillWidth: true }

    NLabel {
        Layout.fillWidth: true
        label: "Feeds"
        description: "No feeds are bundled. Add RSS or Atom URLs here."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "Feed name"
            text: root.newFeedName
            onTextChanged: root.newFeedName = text
        }

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "https://example.com/feed.xml"
            text: root.newFeedUrl
            onTextChanged: root.newFeedUrl = text
        }

        NComboBox {
            Layout.preferredWidth: 160
            model: root.categoryNameModel()
            currentKey: root.categoryKeyAt(root.newFeedCategoryIndex)
            onSelected: key => root.newFeedCategoryIndex = root.indexByKey(root.categoryOptions, key)
        }

        NButton {
            text: "Add"
            enabled: root.newFeedName.length > 0 && root.newFeedUrl.length > 0
            onClicked: root.addFeed()
        }
    }

    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: 220
        clip: true

        ListView {
            model: root.editFeeds
            spacing: Style.marginS

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                height: feedLayout.implicitHeight + Style.marginM * 2
                radius: 8
                color: Color.mSurfaceVariant

                RowLayout {
                    id: feedLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NToggle {
                        checked: modelData.enabled !== false
                        onCheckedChanged: root.updateFeed(index, { enabled: checked })
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                            text: modelData.name || "Feed"
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        NText {
                            text: modelData.url || ""
                            pointSize: Style.fontSizeS
                            color: Color.mSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        NText {
                            visible: modelData.lastStatus === "error"
                            text: modelData.lastError || "Refresh failed"
                            pointSize: Style.fontSizeS
                            color: Color.mError
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    NComboBox {
                        Layout.preferredWidth: 150
                        model: root.categoryNameModel()
                        currentKey: modelData.categoryId || "all"
                        onSelected: key => root.updateFeed(index, { categoryId: key || "all" })
                    }

                    NToggle {
                        checked: !!modelData.pinned
                        onCheckedChanged: root.updateFeed(index, { pinned: checked })
                    }

                    NButton {
                        text: "Remove"
                        onClicked: root.removeFeed(index)
                    }
                }
            }

            NText {
                visible: root.editFeeds.length === 0
                anchors.centerIn: parent
                text: "No feeds configured"
                pointSize: Style.fontSizeM
                color: Color.mSecondary
            }
        }
    }

    NDivider { Layout.fillWidth: true }

    NLabel {
        Layout.fillWidth: true
        label: "Categories"
        description: "Use categories to group feed sources and filter the panel."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "Category name"
            text: root.newCategoryName
            onTextChanged: root.newCategoryName = text
        }

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: 4
            color: /^#[0-9A-Fa-f]{6}$/.test(root.newCategoryColor) ? root.newCategoryColor : "#A9AEFE"
            border.color: Style.capsuleBorderColor
            border.width: 1
        }

        NTextInput {
            Layout.preferredWidth: 110
            placeholderText: "#A9AEFE"
            text: root.newCategoryColor
            onTextChanged: root.newCategoryColor = text
        }

        NButton {
            text: "Add"
            enabled: root.newCategoryName.length > 0
            onClicked: root.addCategory()
        }
    }

    Repeater {
        model: root.editCategories

        delegate: Rectangle {
            required property var modelData
            required property int index

            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: 8
            color: Color.mSurfaceVariant

            RowLayout {
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginM

                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 4
                    color: modelData.color || "#A9AEFE"
                }

                NText {
                    Layout.fillWidth: true
                    text: modelData.name || modelData.id
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                    elide: Text.ElideRight
                }

                NButton {
                    text: "Remove"
                    enabled: modelData.id !== "all"
                    onClicked: root.removeCategory(index)
                }
            }
        }
    }

    NDivider { Layout.fillWidth: true }

    NLabel {
        Layout.fillWidth: true
        label: "Rules"
        description: "Keyword rules can include, exclude, or highlight matching articles."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "Rule name"
            text: root.newRuleName
            onTextChanged: root.newRuleName = text
        }

        NComboBox {
            Layout.preferredWidth: 120
            model: root.ruleModeOptions
            currentKey: root.ruleModes[root.newRuleModeIndex] || "highlight"
            onSelected: key => root.newRuleModeIndex = Math.max(0, root.ruleModes.indexOf(key))
        }

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "keywords, separated, by comma"
            text: root.newRuleTerms
            onTextChanged: root.newRuleTerms = text
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NComboBox {
            Layout.fillWidth: true
            model: root.feedNameModel()
            currentKey: root.feedKeyAt(root.newRuleFeedIndex)
            onSelected: key => root.newRuleFeedIndex = root.indexByKey(root.feedOptions, key)
        }

        NComboBox {
            Layout.fillWidth: true
            model: root.categoryNameModel()
            currentKey: root.categoryKeyAt(root.newRuleCategoryIndex)
            onSelected: key => root.newRuleCategoryIndex = root.indexByKey(root.categoryOptions, key)
        }

        NButton {
            text: "Add rule"
            enabled: root.newRuleTerms.length > 0
            onClicked: root.addRule()
        }
    }

    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: 180
        clip: true

        ListView {
            model: root.editRules
            spacing: Style.marginS

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                height: ruleLayout.implicitHeight + Style.marginM * 2
                radius: 8
                color: Color.mSurfaceVariant

                RowLayout {
                    id: ruleLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NToggle {
                        checked: modelData.enabled !== false
                        onCheckedChanged: root.updateRule(index, { enabled: checked })
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                            text: modelData.name || "Rule"
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        NText {
                            text: (modelData.mode || "highlight") + " - " + Utils.asArray(modelData.terms).join(", ") + " - " + root.ruleScopeText(modelData)
                            pointSize: Style.fontSizeS
                            color: Color.mSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    NButton {
                        text: "Remove"
                        onClicked: root.removeRule(index)
                    }
                }
            }

            NText {
                visible: root.editRules.length === 0
                anchors.centerIn: parent
                text: "No keyword rules"
                pointSize: Style.fontSizeM
                color: Color.mSecondary
            }
        }
    }

    NDivider { Layout.fillWidth: true }

    NLabel {
        Layout.fillWidth: true
        label: "OPML"
        description: "Import or export feed subscriptions and categories."
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
            Layout.fillWidth: true
            placeholderText: "/home/user/feeds.opml"
            text: root.opmlPath
            onTextChanged: root.opmlPath = text
        }

        NButton {
            text: "Import"
            enabled: root.opmlPath.length > 0
            onClicked: root.runImport()
        }

        NButton {
            text: "Export"
            enabled: root.opmlPath.length > 0
            onClicked: root.runExport()
        }
    }

    NText {
        visible: root.settingsStatus.length > 0
        Layout.fillWidth: true
        text: root.settingsStatus
        pointSize: Style.fontSizeS
        color: Color.mSecondary
        wrapMode: Text.Wrap
    }
}
