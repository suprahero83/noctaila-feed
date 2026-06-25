.pragma library

function isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
}

function asArray(value) {
    return isArray(value) ? value : [];
}

function coalesce(value, fallback) {
    return value === undefined || value === null ? fallback : value;
}

function deepCopy(value) {
    if (value === undefined || value === null) {
        return value;
    }

    return JSON.parse(JSON.stringify(value));
}

function trim(value) {
    return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "");
}

function collapseWhitespace(value) {
    return trim(value).replace(/\s+/g, " ");
}

function decodeEntities(value) {
    var text = String(value === undefined || value === null ? "" : value);

    text = text.replace(/&#(\d+);/g, function(match, dec) {
        return String.fromCharCode(parseInt(dec, 10));
    });
    text = text.replace(/&#x([0-9A-Fa-f]+);/g, function(match, hex) {
        return String.fromCharCode(parseInt(hex, 16));
    });

    var named = {
        amp: "&",
        apos: "'",
        quot: "\"",
        lt: "<",
        gt: ">",
        nbsp: " ",
        ndash: "-",
        mdash: "-",
        lsquo: "'",
        rsquo: "'",
        ldquo: "\"",
        rdquo: "\"",
        hellip: "..."
    };

    return text.replace(/&([A-Za-z]+);/g, function(match, name) {
        return named[name] !== undefined ? named[name] : match;
    });
}

function stripCdata(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1");
}

function stripHtml(value) {
    return stripCdata(value)
        .replace(/<!--[\s\S]*?-->/g, " ")
        .replace(/<(br|br\/|\/p|\/div)\b[^>]*>/gi, " ")
        .replace(/<[^>]+>/g, " ");
}

function cleanText(value) {
    return collapseWhitespace(decodeEntities(stripHtml(value)));
}

function cleanXmlText(value) {
    return collapseWhitespace(decodeEntities(stripCdata(value)));
}

function escapeRegExp(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function escapeXml(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&apos;");
}

function normalizeUrl(url) {
    return decodeEntities(trim(url)).replace(/\s+/g, "");
}

function normalizeKey(value) {
    return collapseWhitespace(decodeEntities(value)).toLowerCase();
}

function looksLikeHttpUrl(url) {
    return /^https?:\/\/[^\s<>"]+$/i.test(trim(url));
}

function domainFromUrl(url) {
    var match = String(url || "").match(/^[a-z]+:\/\/([^\/?#]+)/i);
    return match ? match[1].replace(/^www\./i, "") : "";
}

function stableHash(value) {
    var text = String(value === undefined || value === null ? "" : value);
    var hash = 2166136261;

    for (var i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i);
        hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    }

    return (hash >>> 0).toString(16);
}

function stableId(parts) {
    return "nf-" + stableHash(asArray(parts).join("|"));
}

function parseDateToIso(value, fallbackIso) {
    var text = trim(value);
    var date = text ? new Date(text) : null;

    if (!date || isNaN(date.getTime())) {
        return fallbackIso || new Date().toISOString();
    }

    return date.toISOString();
}

function relativeTime(iso) {
    var date = new Date(iso);

    if (isNaN(date.getTime())) {
        return "";
    }

    var diffMs = new Date().getTime() - date.getTime();
    var future = diffMs < 0;
    var absMs = Math.abs(diffMs);
    var mins = Math.floor(absMs / 60000);
    var hours = Math.floor(absMs / 3600000);
    var days = Math.floor(absMs / 86400000);

    if (mins < 1) {
        return "now";
    }
    if (mins < 60) {
        return future ? "in " + mins + "m" : mins + "m ago";
    }
    if (hours < 24) {
        return future ? "in " + hours + "h" : hours + "h ago";
    }
    if (days < 7) {
        return future ? "in " + days + "d" : days + "d ago";
    }

    return date.toLocaleDateString();
}

function dedupeKey(item, mode) {
    var title = normalizeKey(item && item.title ? item.title : "");
    var link = normalizeUrl(item && item.link ? item.link : "").toLowerCase();
    var guid = normalizeKey(item && item.guid ? item.guid : "");

    if (mode === "guid" && guid) {
        return "guid:" + guid;
    }
    if (mode === "link" && link) {
        return "link:" + link;
    }
    if (mode === "title" && title) {
        return "title:" + title;
    }
    if (mode === "none") {
        return item.id || stableId([guid, link, title, item.feedId || ""]);
    }

    if (link) {
        return "link:" + link;
    }
    if (guid) {
        return "guid:" + guid;
    }

    return "title:" + title;
}

function containsTerm(haystack, term) {
    var needle = normalizeKey(term);

    if (!needle) {
        return false;
    }

    return normalizeKey(haystack).indexOf(needle) !== -1;
}

function uniquePush(array, value) {
    if (value && array.indexOf(value) === -1) {
        array.push(value);
    }
}

function sortItems(items, sortMode, pinnedItemIds) {
    var pinned = asArray(pinnedItemIds);
    var sorted = asArray(items).slice();

    sorted.sort(function(a, b) {
        var aPinned = pinned.indexOf(a.id) !== -1;
        var bPinned = pinned.indexOf(b.id) !== -1;

        if (aPinned !== bPinned) {
            return aPinned ? -1 : 1;
        }

        if (sortMode === "source") {
            var bySource = normalizeKey(a.feedName).localeCompare(normalizeKey(b.feedName));
            if (bySource !== 0) {
                return bySource;
            }
        }

        var aTime = new Date(a.publishedAt || 0).getTime() || 0;
        var bTime = new Date(b.publishedAt || 0).getTime() || 0;

        if (sortMode === "published-asc") {
            return aTime - bTime;
        }

        return bTime - aTime;
    });

    return sorted;
}
