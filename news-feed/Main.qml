import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

import "lib/FeedParser.js" as FeedParser
import "lib/Opml.js" as Opml
import "lib/Rules.js" as Rules
import "lib/Utils.js" as Utils

Item {
    id: root

    property var pluginApi: null

    readonly property var defaults: (pluginApi && pluginApi.manifest && pluginApi.manifest.metadata && pluginApi.manifest.metadata.defaultSettings)
        ? pluginApi.manifest.metadata.defaultSettings
        : ({
            feeds: [],
            categories: [{ id: "all", name: "All", color: "#A9AEFE" }],
            rules: [],
            refreshIntervalSec: 900,
            maxItemsPerFeed: 25,
            maxStoredItems: 500,
            showOnlyUnread: false,
            markReadOnOpen: true,
            sortMode: "published-desc",
            dedupeMode: "link-title",
            readItemIds: [],
            pinnedItemIds: [],
            lastSelectedCategoryId: "all"
        })

    property var feeds: []
    property var categories: []
    property var rules: []
    property var readItemIds: []
    property var pinnedItemIds: []
    property var rawItems: []
    property var allItems: []

    property int refreshIntervalSec: 900
    property int maxItemsPerFeed: 25
    property int maxStoredItems: 500
    property bool showOnlyUnread: false
    property bool markReadOnOpen: true
    property string sortMode: "published-desc"
    property string dedupeMode: "link-title"
    property string lastSelectedCategoryId: "all"

    property bool loading: false
    property bool hasError: false
    property int unreadCount: 0
    property int highlightedCount: 0
    property string lastRefreshStatus: "Idle"
    property string lastRefreshedAt: ""
    property string lastOpmlStatus: ""

    property string _settingsSignature: ""
    property string _feedSignature: ""
    property bool _initialized: false

    Component.onCompleted: initialize()
    onPluginApiChanged: initialize()

    Timer {
        id: refreshTimer
        interval: Math.max(60, root.refreshIntervalSec) * 1000
        running: root._initialized && root.feeds.length > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: settingsPollTimer
        interval: 1000
        running: root._initialized
        repeat: true
        onTriggered: root.syncFromSettings(false)
    }

    Process {
        id: fetchProcess
        running: false
        stdout: StdioCollector { id: curlStdout }
        stderr: StdioCollector { id: curlStderr }

        property bool active: false
        property int currentFeedIndex: 0
        property var activeFeeds: []
        property var fetchedItems: []
        property var workingFeeds: []
        property var currentFeed: null
        property int failureCount: 0

        onExited: function(exitCode, exitStatus) {
            if (!active || !currentFeed) {
                return;
            }

            var feed = Utils.deepCopy(currentFeed);
            var errorText = Utils.cleanText(curlStderr.text || "");

            if (exitCode !== 0) {
                feed.lastFetchedAt = new Date().toISOString();
                feed.lastStatus = "error";
                feed.lastError = errorText || "curl exited with code " + exitCode;
                failureCount++;
                root.replaceWorkingFeed(feed);
                root.fetchNextFeed();
                return;
            }

            if (!curlStdout.text || !String(curlStdout.text).trim()) {
                feed.lastFetchedAt = new Date().toISOString();
                feed.lastStatus = "error";
                feed.lastError = "Empty feed response";
                failureCount++;
                root.replaceWorkingFeed(feed);
                root.fetchNextFeed();
                return;
            }

            try {
                var parsed = FeedParser.parse(curlStdout.text, feed, root.maxItemsPerFeed);
                feed.lastFetchedAt = new Date().toISOString();
                feed.lastStatus = "ok";
                feed.lastError = "";
                fetchedItems = fetchedItems.concat(parsed);
            } catch (e) {
                feed.lastFetchedAt = new Date().toISOString();
                feed.lastStatus = "error";
                feed.lastError = String(e && e.message ? e.message : e);
                failureCount++;
            }

            root.replaceWorkingFeed(feed);
            root.fetchNextFeed();
        }
    }

    FileView {
        id: opmlImportFile
        path: ""
        blockLoading: true
        watchChanges: false
        printErrors: false
    }

    FileView {
        id: opmlExportFile
        path: ""
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false

        onSaved: root.lastOpmlStatus = "OPML exported"
        onSaveFailed: function(error) {
            root.lastOpmlStatus = "OPML export failed: " + error;
        }
    }

    IpcHandler {
        target: "plugin:news-feed"

        function refresh() {
            root.refresh();
        }

        function markAllRead() {
            root.markAllRead();
        }

        function clearReadState() {
            root.clearReadState();
        }

        function togglePanel() {
            root.togglePanelFromIpc();
        }

        function search(query) {
            var cleanQuery = Utils.cleanText(String(query || "")).substring(0, 160);
            var result = root.searchItems(cleanQuery, 50);

            return JSON.stringify(result.map(function(item) {
                return {
                    title: item.title,
                    source: item.feedName,
                    url: item.link,
                    publishedAt: item.publishedAt
                };
            }));
        }
    }

    function initialize() {
        if (_initialized || !pluginApi) {
            return;
        }

        _initialized = true;

        try {
            pluginApi.newsFeed = root;
        } catch (e) {
            Logger.d("NewsFeed", "Plugin API does not accept dynamic newsFeed property");
        }

        syncFromSettings(true);

        if (feeds.length > 0) {
            Qt.callLater(refresh);
        }
    }

    function ensureSettingsObject() {
        if (!pluginApi) {
            return {};
        }

        if (!pluginApi.pluginSettings) {
            pluginApi.pluginSettings = {};
        }

        var settings = pluginApi.pluginSettings;
        var defaultCopy = Utils.deepCopy(defaults);

        for (var key in defaultCopy) {
            if (settings[key] === undefined || settings[key] === null) {
                settings[key] = defaultCopy[key];
            }
        }

        return settings;
    }

    function syncFromSettings(force) {
        if (!pluginApi) {
            return;
        }

        var settings = ensureSettingsObject();
        var signature = JSON.stringify(settings);

        if (!force && signature === _settingsSignature) {
            return;
        }

        var nextCategories = sanitizeCategories(settings.categories || defaults.categories);
        var nextFeeds = sanitizeFeeds(settings.feeds || defaults.feeds, nextCategories);
        var nextRules = sanitizeRules(settings.rules || defaults.rules);
        var nextFeedSignature = JSON.stringify(nextFeeds.map(function(feed) {
            return {
                id: feed.id,
                url: feed.url,
                enabled: feed.enabled,
                categoryId: feed.categoryId,
                priority: feed.priority
            };
        }));
        var feedsChanged = _feedSignature !== "" && _feedSignature !== nextFeedSignature;

        categories = nextCategories;
        feeds = nextFeeds;
        rules = nextRules;
        refreshIntervalSec = boundedInt(settings.refreshIntervalSec, defaults.refreshIntervalSec, 60, 86400);
        maxItemsPerFeed = boundedInt(settings.maxItemsPerFeed, defaults.maxItemsPerFeed, 1, 200);
        maxStoredItems = boundedInt(settings.maxStoredItems, defaults.maxStoredItems, 50, 5000);
        showOnlyUnread = settings.showOnlyUnread === undefined ? defaults.showOnlyUnread : !!settings.showOnlyUnread;
        markReadOnOpen = settings.markReadOnOpen === undefined ? defaults.markReadOnOpen : !!settings.markReadOnOpen;
        sortMode = validChoice(settings.sortMode, ["published-desc", "published-asc", "source"], defaults.sortMode);
        dedupeMode = validChoice(settings.dedupeMode, ["link-title", "link", "guid", "title", "none"], defaults.dedupeMode);
        readItemIds = Utils.asArray(settings.readItemIds || defaults.readItemIds).slice(0, maxStoredItems);
        pinnedItemIds = Utils.asArray(settings.pinnedItemIds || defaults.pinnedItemIds);
        lastSelectedCategoryId = categoryExists(settings.lastSelectedCategoryId) ? settings.lastSelectedCategoryId : "all";

        _settingsSignature = signature;
        _feedSignature = nextFeedSignature;

        reprocessItems();

        if (feedsChanged && !loading) {
            Qt.callLater(refresh);
        }
    }

    function sanitizeCategories(value) {
        var raw = Utils.asArray(value);
        var result = [];
        var seen = {};

        for (var i = 0; i < raw.length; i++) {
            var category = raw[i] || {};
            var name = Utils.cleanText(category.name || category.id || "");
            var id = Utils.cleanText(category.id || Utils.stableId([name]));

            if (!id || seen[id]) {
                continue;
            }

            result.push({
                id: id,
                name: name || id,
                color: /^#[0-9A-Fa-f]{6}$/.test(category.color || "") ? category.color : "#A9AEFE"
            });
            seen[id] = true;
        }

        if (!seen.all) {
            result.unshift({
                id: "all",
                name: "All",
                color: "#A9AEFE"
            });
        }

        return result;
    }

    function sanitizeFeeds(value, knownCategories) {
        var raw = Utils.asArray(value);
        var result = [];
        var categorySet = {};
        var seenIds = {};

        for (var c = 0; c < knownCategories.length; c++) {
            categorySet[knownCategories[c].id] = true;
        }

        for (var i = 0; i < raw.length; i++) {
            var feed = raw[i] || {};
            var url = Utils.normalizeUrl(feed.url || "");

            if (!url) {
                continue;
            }

            var id = Utils.cleanText(feed.id || Utils.stableId([url, feed.name || ""]));
            if (!id || seenIds[id]) {
                id = Utils.stableId([url, i]);
            }

            var categoryId = categorySet[feed.categoryId] ? feed.categoryId : "all";
            result.push({
                id: id,
                name: Utils.cleanText(feed.name || Utils.domainFromUrl(url) || url),
                url: url,
                categoryId: categoryId,
                enabled: feed.enabled === undefined ? true : !!feed.enabled,
                pinned: !!feed.pinned,
                priority: boundedInt(feed.priority, 0, -999, 999),
                lastFetchedAt: Utils.cleanText(feed.lastFetchedAt || ""),
                lastStatus: Utils.cleanText(feed.lastStatus || "never"),
                lastError: Utils.cleanText(feed.lastError || "")
            });
            seenIds[id] = true;
        }

        result.sort(function(a, b) {
            if (a.pinned !== b.pinned) {
                return a.pinned ? -1 : 1;
            }
            if (a.priority !== b.priority) {
                return b.priority - a.priority;
            }
            return Utils.normalizeKey(a.name).localeCompare(Utils.normalizeKey(b.name));
        });

        return result;
    }

    function sanitizeRules(value) {
        var raw = Utils.asArray(value);
        var result = [];
        var modes = ["include", "exclude", "highlight"];

        for (var i = 0; i < raw.length; i++) {
            var rule = raw[i] || {};
            var terms = Utils.asArray(rule.terms);

            if (typeof rule.terms === "string") {
                terms = rule.terms.split(",");
            }

            terms = terms.map(function(term) {
                return Utils.cleanText(term);
            }).filter(function(term) {
                return term.length > 0;
            });

            result.push({
                id: Utils.cleanText(rule.id || Utils.stableId([rule.name || "", terms.join(","), i])),
                name: Utils.cleanText(rule.name || "Rule"),
                mode: modes.indexOf(rule.mode) !== -1 ? rule.mode : "highlight",
                terms: terms,
                feedIds: Utils.asArray(rule.feedIds),
                categoryIds: Utils.asArray(rule.categoryIds),
                enabled: rule.enabled === undefined ? true : !!rule.enabled
            });
        }

        return result;
    }

    function boundedInt(value, fallback, min, max) {
        var number = parseInt(value, 10);

        if (isNaN(number)) {
            number = fallback;
        }

        return Math.max(min, Math.min(max, number));
    }

    function validChoice(value, choices, fallback) {
        return choices.indexOf(value) !== -1 ? value : fallback;
    }

    function categoryExists(categoryId) {
        for (var i = 0; i < categories.length; i++) {
            if (categories[i].id === categoryId) {
                return true;
            }
        }

        return false;
    }

    function categoryById(categoryId) {
        for (var i = 0; i < categories.length; i++) {
            if (categories[i].id === categoryId) {
                return categories[i];
            }
        }

        return { id: "all", name: "All", color: "#A9AEFE" };
    }

    function feedById(feedId) {
        for (var i = 0; i < feeds.length; i++) {
            if (feeds[i].id === feedId) {
                return feeds[i];
            }
        }

        return null;
    }

    function buildCategoriesById() {
        var map = {};

        for (var i = 0; i < categories.length; i++) {
            map[categories[i].id] = categories[i];
        }

        return map;
    }

    function refresh() {
        if (loading || fetchProcess.active) {
            Logger.d("NewsFeed", "Refresh skipped because a fetch is already running");
            return;
        }

        syncFromSettings(false);

        var activeFeeds = feeds.filter(function(feed) {
            return feed.enabled !== false && Utils.looksLikeHttpUrl(feed.url);
        });

        if (activeFeeds.length === 0) {
            loading = false;
            rawItems = [];
            allItems = [];
            unreadCount = 0;
            highlightedCount = 0;
            hasError = feeds.length > 0;
            lastRefreshStatus = feeds.length === 0 ? "No feeds configured" : "No enabled HTTP feeds";
            return;
        }

        loading = true;
        hasError = false;
        lastRefreshStatus = "Refreshing " + activeFeeds.length + " feed" + (activeFeeds.length === 1 ? "" : "s");

        fetchProcess.active = true;
        fetchProcess.currentFeedIndex = 0;
        fetchProcess.activeFeeds = activeFeeds;
        fetchProcess.workingFeeds = Utils.deepCopy(feeds);
        fetchProcess.fetchedItems = [];
        fetchProcess.failureCount = 0;
        fetchNextFeed();
    }

    function fetchNextFeed() {
        if (fetchProcess.currentFeedIndex >= fetchProcess.activeFeeds.length) {
            finishRefresh();
            return;
        }

        var feed = fetchProcess.activeFeeds[fetchProcess.currentFeedIndex];
        fetchProcess.currentFeedIndex++;
        fetchProcess.currentFeed = feed;
        lastRefreshStatus = "Fetching " + (feed.name || feed.url);

        fetchProcess.command = [
            "curl",
            "--silent",
            "--show-error",
            "--location",
            "--fail",
            "--max-time",
            "20",
            "--user-agent",
            "Noctalia News Feed/1.0",
            feed.url
        ];
        fetchProcess.running = true;
    }

    function replaceWorkingFeed(updatedFeed) {
        var nextFeeds = fetchProcess.workingFeeds.slice();
        var replaced = false;

        for (var i = 0; i < nextFeeds.length; i++) {
            if (nextFeeds[i].id === updatedFeed.id) {
                nextFeeds[i] = updatedFeed;
                replaced = true;
                break;
            }
        }

        if (!replaced) {
            nextFeeds.push(updatedFeed);
        }

        fetchProcess.workingFeeds = nextFeeds;
    }

    function finishRefresh() {
        fetchProcess.active = false;
        loading = false;
        feeds = sanitizeFeeds(fetchProcess.workingFeeds, categories);

        rawItems = fetchProcess.fetchedItems;
        allItems = processItems(rawItems);
        lastRefreshedAt = new Date().toISOString();
        hasError = fetchProcess.failureCount > 0;
        lastRefreshStatus = hasError
            ? "Updated with " + fetchProcess.failureCount + " feed error" + (fetchProcess.failureCount === 1 ? "" : "s")
            : "Updated " + allItems.length + " item" + (allItems.length === 1 ? "" : "s");

        pruneReadState();
        updateCounts();
        saveSettingsState();
    }

    function processItems(rawItems) {
        var seen = {};
        var unique = [];

        for (var i = 0; i < rawItems.length; i++) {
            var item = rawItems[i];
            var key = Utils.dedupeKey(item, dedupeMode);

            if (seen[key]) {
                continue;
            }

            seen[key] = true;
            unique.push(item);
        }

        var ruled = Rules.apply(unique, rules, buildCategoriesById()).filter(function(item) {
            return !item.excluded;
        });

        return Utils.sortItems(ruled, sortMode, pinnedItemIds).slice(0, maxStoredItems);
    }

    function reprocessItems() {
        if (rawItems.length === 0 && allItems.length === 0) {
            updateCounts();
            return;
        }

        allItems = processItems(rawItems.length > 0 ? rawItems : allItems);
        updateCounts();
    }

    function pruneReadState() {
        var liveIds = {};

        for (var i = 0; i < allItems.length && i < maxStoredItems; i++) {
            liveIds[allItems[i].id] = true;
        }

        readItemIds = readItemIds.filter(function(id) {
            return liveIds[id];
        }).slice(0, maxStoredItems);

        pinnedItemIds = pinnedItemIds.filter(function(id) {
            return liveIds[id];
        });
    }

    function updateCounts() {
        var unread = 0;
        var highlighted = 0;

        for (var i = 0; i < allItems.length; i++) {
            if (readItemIds.indexOf(allItems[i].id) === -1) {
                unread++;
            }
            if (allItems[i].highlighted) {
                highlighted++;
            }
        }

        unreadCount = unread;
        highlightedCount = highlighted;
    }

    function saveSettingsState() {
        if (!pluginApi) {
            return;
        }

        var settings = ensureSettingsObject();
        settings.feeds = feeds;
        settings.categories = categories;
        settings.rules = rules;
        settings.refreshIntervalSec = refreshIntervalSec;
        settings.maxItemsPerFeed = maxItemsPerFeed;
        settings.maxStoredItems = maxStoredItems;
        settings.showOnlyUnread = showOnlyUnread;
        settings.markReadOnOpen = markReadOnOpen;
        settings.sortMode = sortMode;
        settings.dedupeMode = dedupeMode;
        settings.readItemIds = readItemIds;
        settings.pinnedItemIds = pinnedItemIds;
        settings.lastSelectedCategoryId = lastSelectedCategoryId;
        _settingsSignature = JSON.stringify(settings);

        pluginApi.saveSettings();
    }

    function isUnread(item) {
        return item && readItemIds.indexOf(item.id) === -1;
    }

    function isPinned(item) {
        return item && pinnedItemIds.indexOf(item.id) !== -1;
    }

    function itemById(itemId) {
        for (var i = 0; i < allItems.length; i++) {
            if (allItems[i].id === itemId) {
                return allItems[i];
            }
        }

        return null;
    }

    function markItemRead(itemOrId) {
        var itemId = typeof itemOrId === "string" ? itemOrId : itemOrId && itemOrId.id;

        if (!itemId || readItemIds.indexOf(itemId) !== -1) {
            return;
        }

        var next = readItemIds.slice();
        next.unshift(itemId);
        readItemIds = next.slice(0, maxStoredItems);
        updateCounts();
        saveSettingsState();
    }

    function markItemUnread(itemOrId) {
        var itemId = typeof itemOrId === "string" ? itemOrId : itemOrId && itemOrId.id;

        if (!itemId) {
            return;
        }

        readItemIds = readItemIds.filter(function(id) {
            return id !== itemId;
        });
        updateCounts();
        saveSettingsState();
    }

    function markAllRead() {
        var next = readItemIds.slice();

        for (var i = 0; i < allItems.length; i++) {
            Utils.uniquePush(next, allItems[i].id);
        }

        readItemIds = next.slice(0, maxStoredItems);
        updateCounts();
        saveSettingsState();
    }

    function clearReadState() {
        readItemIds = [];
        updateCounts();
        saveSettingsState();
    }

    function togglePinned(itemOrId) {
        var itemId = typeof itemOrId === "string" ? itemOrId : itemOrId && itemOrId.id;

        if (!itemId) {
            return;
        }

        var next = pinnedItemIds.slice();
        var index = next.indexOf(itemId);

        if (index === -1) {
            next.unshift(itemId);
        } else {
            next.splice(index, 1);
        }

        pinnedItemIds = next;
        allItems = Utils.sortItems(allItems, sortMode, pinnedItemIds);
        saveSettingsState();
    }

    function openItem(itemOrId) {
        var item = typeof itemOrId === "string" ? itemById(itemOrId) : itemOrId;

        if (!item || !item.link) {
            return;
        }

        Qt.openUrlExternally(item.link);

        if (markReadOnOpen) {
            markItemRead(item.id);
        }
    }

    function setSelectedCategory(categoryId) {
        lastSelectedCategoryId = categoryExists(categoryId) ? categoryId : "all";
        saveSettingsState();
    }

    function filteredItems(filterMode, query, categoryId) {
        var mode = filterMode || "all";
        var text = Utils.normalizeKey(query || "");
        var selectedCategory = categoryId || "all";
        var cats = buildCategoriesById();
        var output = [];

        for (var i = 0; i < allItems.length; i++) {
            var item = allItems[i];

            if (selectedCategory !== "all" && item.categoryId !== selectedCategory) {
                continue;
            }
            if (showOnlyUnread && mode === "all" && !isUnread(item)) {
                continue;
            }
            if (mode === "unread" && !isUnread(item)) {
                continue;
            }
            if (mode === "pinned" && !isPinned(item)) {
                continue;
            }
            if (mode === "highlighted" && !item.highlighted) {
                continue;
            }
            if (text) {
                var category = cats[item.categoryId] || {};
                var haystack = Utils.normalizeKey([
                    item.title,
                    item.summary,
                    item.author,
                    item.feedName,
                    category.name
                ].join(" "));

                if (haystack.indexOf(text) === -1) {
                    continue;
                }
            }

            output.push(item);
        }

        return output;
    }

    function searchItems(query, limit) {
        var max = Math.max(1, Math.min(50, Number(limit || 50)));
        return filteredItems("all", query || "", "all").slice(0, max);
    }

    function statusText() {
        if (loading) {
            return lastRefreshStatus;
        }

        var parts = [];
        parts.push(unreadCount + " unread");

        if (lastRefreshedAt) {
            parts.push("updated " + Utils.relativeTime(lastRefreshedAt));
        } else {
            parts.push(lastRefreshStatus);
        }

        if (hasError) {
            parts.push("errors");
        }

        return parts.join(" - ");
    }

    function importOpml(path) {
        var cleanPath = Utils.trim(path);

        if (!cleanPath || cleanPath.indexOf("\u0000") !== -1) {
            lastOpmlStatus = "Enter a valid OPML path";
            return false;
        }

        try {
            opmlImportFile.path = cleanPath;
            opmlImportFile.reload();
            var text = opmlImportFile.text();

            if (!text || !String(text).trim()) {
                lastOpmlStatus = "OPML file is empty or unreadable";
                return false;
            }

            var result = Opml.importFeeds(text, feeds, categories);
            feeds = sanitizeFeeds(result.feeds, result.categories);
            categories = sanitizeCategories(result.categories);
            lastOpmlStatus = "Imported " + result.addedFeeds + " feed" + (result.addedFeeds === 1 ? "" : "s");
            if (result.errors.length > 0) {
                lastOpmlStatus += " with " + result.errors.length + " warning" + (result.errors.length === 1 ? "" : "s");
            }
            saveSettingsState();
            syncFromSettings(true);
            return true;
        } catch (e) {
            lastOpmlStatus = "OPML import failed: " + (e && e.message ? e.message : e);
            return false;
        }
    }

    function exportOpml(path) {
        var cleanPath = Utils.trim(path);

        if (!cleanPath || cleanPath.indexOf("\u0000") !== -1) {
            lastOpmlStatus = "Enter a valid OPML path";
            return false;
        }

        try {
            opmlExportFile.path = cleanPath;
            opmlExportFile.setText(Opml.exportFeeds(feeds, categories));
            lastOpmlStatus = "Exporting OPML";
            return true;
        } catch (e) {
            lastOpmlStatus = "OPML export failed: " + (e && e.message ? e.message : e);
            return false;
        }
    }

    function togglePanelFromIpc() {
        if (!pluginApi) {
            return;
        }

        if (pluginApi.withCurrentScreen) {
            pluginApi.withCurrentScreen(function(screen) {
                pluginApi.togglePanel(screen);
            });
            return;
        }

        try {
            pluginApi.togglePanel(pluginApi.panelOpenScreen);
        } catch (e) {
            Logger.w("NewsFeed", "IPC togglePanel failed:", e);
        }
    }
}
