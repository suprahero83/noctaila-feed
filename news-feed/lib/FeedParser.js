.pragma library
.import "Utils.js" as Utils

function parse(xml, feed, maxItems) {
    var text = String(xml || "").replace(/^\uFEFF/, "");
    var items = [];
    var limit = Math.max(1, Number(maxItems || 25));

    if (!text || !/<(rss|feed|rdf:RDF|rdf)\b/i.test(text)) {
        throw new Error("Response is not an RSS or Atom document");
    }

    if (/<entry\b/i.test(text)) {
        items = items.concat(parseEntries(text, feed, limit));
    }
    if (items.length < limit && /<item\b/i.test(text)) {
        items = items.concat(parseItems(text, feed, limit - items.length));
    }

    if (items.length === 0) {
        throw new Error("No feed items found");
    }

    return items.slice(0, limit);
}

function parseItems(xml, feed, limit) {
    var items = [];
    var regex = /<item\b[^>]*>([\s\S]*?)<\/item>/gi;
    var match;

    while ((match = regex.exec(xml)) !== null && items.length < limit) {
        items.push(parseRssItem(match[1], feed));
    }

    return items;
}

function parseEntries(xml, feed, limit) {
    var items = [];
    var regex = /<entry\b[^>]*>([\s\S]*?)<\/entry>/gi;
    var match;

    while ((match = regex.exec(xml)) !== null && items.length < limit) {
        items.push(parseAtomEntry(match[1], feed));
    }

    return items;
}

function parseRssItem(itemXml, feed) {
    var title = tagText(itemXml, "title") || "Untitled";
    var link = tagText(itemXml, "link");
    var summary = tagText(itemXml, "description") || tagText(itemXml, "content:encoded") || tagText(itemXml, "summary");
    var author = tagText(itemXml, "dc:creator") || tagText(itemXml, "author");
    var published = tagText(itemXml, "pubDate") || tagText(itemXml, "published") || tagText(itemXml, "updated") || tagText(itemXml, "dc:date");
    var guid = tagText(itemXml, "guid") || tagText(itemXml, "id") || link || title;

    return normalizeItem(feed, title, link, summary, author, published, guid);
}

function parseAtomEntry(entryXml, feed) {
    var title = tagText(entryXml, "title") || "Untitled";
    var link = atomLink(entryXml) || tagText(entryXml, "link");
    var summary = tagText(entryXml, "summary") || tagText(entryXml, "content") || tagText(entryXml, "subtitle");
    var author = tagText(tagTextRaw(entryXml, "author"), "name") || tagText(entryXml, "name") || tagText(entryXml, "dc:creator");
    var published = tagText(entryXml, "published") || tagText(entryXml, "updated") || tagText(entryXml, "issued");
    var guid = tagText(entryXml, "id") || link || title;

    return normalizeItem(feed, title, link, summary, author, published, guid);
}

function normalizeItem(feed, title, link, summary, author, published, guid) {
    var feedId = feed.id || Utils.stableId([feed.url || "", feed.name || ""]);
    var cleanTitle = Utils.cleanText(title) || "Untitled";
    var cleanLink = Utils.normalizeUrl(link);
    var cleanSummary = Utils.cleanText(summary);
    var cleanAuthor = Utils.cleanText(author);
    var cleanGuid = Utils.cleanXmlText(guid) || cleanLink || cleanTitle;
    var publishedAt = Utils.parseDateToIso(published, new Date().toISOString());
    var itemId = Utils.stableId([feedId, cleanGuid, cleanLink, cleanTitle]);

    return {
        id: itemId,
        feedId: feedId,
        feedName: feed.name || Utils.domainFromUrl(feed.url) || "Feed",
        feedUrl: feed.url || "",
        categoryId: feed.categoryId || "all",
        title: cleanTitle,
        link: cleanLink,
        summary: cleanSummary,
        author: cleanAuthor,
        publishedAt: publishedAt,
        guid: cleanGuid,
        matchedRuleIds: [],
        matchedTerms: [],
        excluded: false,
        highlighted: false
    };
}

function tagPattern(tag) {
    if (tag.indexOf(":") !== -1) {
        return Utils.escapeRegExp(tag);
    }

    return "(?:[A-Za-z0-9_.-]+:)?" + Utils.escapeRegExp(tag);
}

function tagTextRaw(xml, tag) {
    if (!xml) {
        return "";
    }

    var pattern = tagPattern(tag);
    var regex = new RegExp("<" + pattern + "\\b[^>]*>([\\s\\S]*?)<\\/" + pattern + ">", "i");
    var match = regex.exec(xml);

    return match ? match[1] : "";
}

function tagText(xml, tag) {
    return Utils.cleanXmlText(tagTextRaw(xml, tag));
}

function atomLink(entryXml) {
    var regex = /<link\b([^>]*)\/?>/gi;
    var fallback = "";
    var match;

    while ((match = regex.exec(entryXml)) !== null) {
        var attrs = parseAttrs(match[1]);
        var rel = (attrs.rel || "").toLowerCase();
        var href = attrs.href || "";

        if (!href) {
            continue;
        }

        if (!fallback) {
            fallback = href;
        }
        if (!rel || rel === "alternate") {
            return Utils.decodeEntities(href);
        }
    }

    return Utils.decodeEntities(fallback);
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
