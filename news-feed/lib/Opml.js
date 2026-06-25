.pragma library
.import "Utils.js" as Utils

function exportFeeds(feeds, categories) {
    var categoryList = Utils.asArray(categories);
    var feedList = Utils.asArray(feeds);
    var byCategory = {};
    var lines = [];

    for (var c = 0; c < categoryList.length; c++) {
        var category = categoryList[c];
        if (!category || !category.id) {
            continue;
        }
        byCategory[category.id] = [];
    }

    if (!byCategory.all) {
        byCategory.all = [];
    }

    for (var f = 0; f < feedList.length; f++) {
        var feed = feedList[f];
        if (!feed || !feed.url) {
            continue;
        }

        var categoryId = feed.categoryId || "all";
        if (!byCategory[categoryId]) {
            byCategory[categoryId] = [];
        }

        byCategory[categoryId].push(feed);
    }

    lines.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
    lines.push("<opml version=\"2.0\">");
    lines.push("  <head>");
    lines.push("    <title>Noctalia News Feed Subscriptions</title>");
    lines.push("  </head>");
    lines.push("  <body>");

    for (var i = 0; i < categoryList.length; i++) {
        var cat = categoryList[i];
        if (!cat || !cat.id) {
            continue;
        }

        var catFeeds = byCategory[cat.id] || [];
        if (cat.id === "all") {
            for (var a = 0; a < catFeeds.length; a++) {
                lines.push(feedOutline(catFeeds[a], "    "));
            }
            continue;
        }

        lines.push("    <outline text=\"" + Utils.escapeXml(cat.name || cat.id) + "\" title=\"" + Utils.escapeXml(cat.name || cat.id) + "\" categoryId=\"" + Utils.escapeXml(cat.id) + "\" color=\"" + Utils.escapeXml(cat.color || "") + "\">");
        for (var cf = 0; cf < catFeeds.length; cf++) {
            lines.push(feedOutline(catFeeds[cf], "      "));
        }
        lines.push("    </outline>");
    }

    var seenCategories = {};
    for (var sc = 0; sc < categoryList.length; sc++) {
        if (categoryList[sc] && categoryList[sc].id) {
            seenCategories[categoryList[sc].id] = true;
        }
    }

    for (var unknownId in byCategory) {
        if (seenCategories[unknownId] || unknownId === "all") {
            continue;
        }

        var unknownFeeds = byCategory[unknownId] || [];
        for (var uf = 0; uf < unknownFeeds.length; uf++) {
            lines.push(feedOutline(unknownFeeds[uf], "    "));
        }
    }

    lines.push("  </body>");
    lines.push("</opml>");

    return lines.join("\n") + "\n";
}

function feedOutline(feed, indent) {
    var name = feed.name || Utils.domainFromUrl(feed.url) || feed.url;

    return indent + "<outline type=\"rss\" text=\"" + Utils.escapeXml(name) +
        "\" title=\"" + Utils.escapeXml(name) +
        "\" xmlUrl=\"" + Utils.escapeXml(feed.url) +
        "\" categoryId=\"" + Utils.escapeXml(feed.categoryId || "all") +
        "\" />";
}

function importFeeds(opmlText, existingFeeds, existingCategories) {
    var feeds = Utils.deepCopy(Utils.asArray(existingFeeds));
    var categories = ensureAllCategory(Utils.deepCopy(Utils.asArray(existingCategories)));
    var feedUrlSet = {};
    var categoryIdSet = {};
    var addedFeeds = 0;
    var addedCategories = 0;
    var errors = [];
    var categoryStack = [];
    var regex = /<\/outline\s*>|<outline\b([^>]*?)(\/?)>/gi;
    var match;

    for (var ef = 0; ef < feeds.length; ef++) {
        if (feeds[ef] && feeds[ef].url) {
            feedUrlSet[Utils.normalizeUrl(feeds[ef].url).toLowerCase()] = true;
        }
    }

    for (var ec = 0; ec < categories.length; ec++) {
        if (categories[ec] && categories[ec].id) {
            categoryIdSet[categories[ec].id] = true;
        }
    }

    while ((match = regex.exec(opmlText || "")) !== null) {
        if (match[0].indexOf("</") === 0) {
            categoryStack.pop();
            continue;
        }

        var attrs = parseAttrs(match[1] || "");
        var selfClosing = match[2] === "/" || /\/\s*$/.test(match[1] || "");
        var xmlUrl = Utils.normalizeUrl(attrs.xmlUrl || attrs.xmlurl || attrs.url || "");
        var text = Utils.cleanText(attrs.text || attrs.title || attrs.name || "");

        if (xmlUrl) {
            if (!Utils.looksLikeHttpUrl(xmlUrl)) {
                errors.push("Skipped invalid feed URL: " + xmlUrl);
                continue;
            }

            var normalized = xmlUrl.toLowerCase();
            if (feedUrlSet[normalized]) {
                continue;
            }

            var categoryId = attrs.categoryId || attrs.categoryid || attrs.category || categoryStack[categoryStack.length - 1] || "all";
            if (!categoryIdSet[categoryId]) {
                categoryId = "all";
            }

            feeds.push({
                id: Utils.stableId([xmlUrl, text]),
                name: text || Utils.domainFromUrl(xmlUrl) || xmlUrl,
                url: xmlUrl,
                categoryId: categoryId,
                enabled: true,
                pinned: false,
                priority: 0,
                lastFetchedAt: "",
                lastStatus: "never",
                lastError: ""
            });
            feedUrlSet[normalized] = true;
            addedFeeds++;
            continue;
        }

        if (text && text.toLowerCase() !== "subscriptions") {
            var categoryIdFromAttrs = attrs.categoryId || attrs.categoryid || Utils.stableId([text]);
            if (!categoryIdSet[categoryIdFromAttrs]) {
                categories.push({
                    id: categoryIdFromAttrs,
                    name: text,
                    color: attrs.color || "#A9AEFE"
                });
                categoryIdSet[categoryIdFromAttrs] = true;
                addedCategories++;
            }

            if (!selfClosing) {
                categoryStack.push(categoryIdFromAttrs);
            }
        } else if (!selfClosing) {
            categoryStack.push(categoryStack[categoryStack.length - 1] || "all");
        }
    }

    return {
        feeds: feeds,
        categories: categories,
        addedFeeds: addedFeeds,
        addedCategories: addedCategories,
        errors: errors
    };
}

function ensureAllCategory(categories) {
    var list = Utils.asArray(categories);
    var hasAll = false;

    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === "all") {
            hasAll = true;
            break;
        }
    }

    if (!hasAll) {
        list.unshift({
            id: "all",
            name: "All",
            color: "#A9AEFE"
        });
    }

    return list;
}

function parseAttrs(text) {
    var attrs = {};
    var regex = /([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*["']([^"']*)["']/g;
    var match;

    while ((match = regex.exec(text || "")) !== null) {
        attrs[match[1]] = Utils.decodeEntities(match[2]);
    }

    return attrs;
}
