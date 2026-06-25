import QtQuick
import qs.Commons

import "lib/Utils.js" as Utils

Item {
    id: root

    property var pluginApi: null
    property var launcher: null
    property string name: "News Feed"
    property bool handleSearch: false
    property string supportedLayouts: "list"

    readonly property var service: pluginApi && pluginApi.mainInstance
        ? pluginApi.mainInstance
        : (pluginApi && pluginApi.newsFeed ? pluginApi.newsFeed : null)

    function init() {
        Logger.d("NewsFeed", "Launcher provider initialized");
    }

    function onOpened() {
        if (launcher) {
            launcher.updateResults();
        }
    }

    function handleCommand(searchText) {
        var text = String(searchText || "").trim();
        return text === ">news" || text.indexOf(">news ") === 0;
    }

    function commands() {
        return [{
            name: ">news",
            description: "Search cached news articles",
            icon: "newspaper",
            isTablerIcon: true,
            onActivate: function() {
                if (launcher) {
                    launcher.setSearchText(">news ");
                }
            }
        }];
    }

    function getResults(searchText) {
        if (!handleCommand(searchText)) {
            return [];
        }

        if (!service) {
            return [{
                name: "News Feed is starting",
                description: "Try again after the plugin has loaded",
                icon: "newspaper",
                isTablerIcon: true,
                provider: root,
                onActivate: function() {}
            }];
        }

        var query = String(searchText || "").replace(/^>news\s*/i, "");
        var items = service.searchItems(query, 50);

        if (items.length === 0) {
            return [{
                name: service.feeds.length === 0 ? "No feeds configured" : "No cached articles",
                description: service.lastRefreshStatus,
                icon: "newspaper",
                isTablerIcon: true,
                provider: root,
                onActivate: function() {}
            }];
        }

        return items.map(function(item) {
            var unread = service.isUnread(item);
            var category = service.categoryById(item.categoryId);
            var parts = [];

            if (unread) {
                parts.push("Unread");
            }
            parts.push(item.feedName || "Feed");
            if (category && category.id !== "all") {
                parts.push(category.name);
            }
            if (item.publishedAt) {
                parts.push(Utils.relativeTime(item.publishedAt));
            }

            return {
                name: item.title || "Untitled",
                description: parts.join(" - "),
                icon: item.highlighted ? "sparkles" : "newspaper",
                isTablerIcon: true,
                singleLine: false,
                provider: root,
                onActivate: function() {
                    service.openItem(item);
                    if (launcher) {
                        launcher.close();
                    }
                }
            };
        });
    }
}
