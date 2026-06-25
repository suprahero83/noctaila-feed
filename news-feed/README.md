# News Feed

Power-user RSS and Atom news aggregator for Noctalia v4 stable.

## Features

- Badge-only unread status in the bar.
- Full triage panel with search, unread, pinned, highlighted, and category filters.
- RSS and Atom fetching with `curl`; no Python, Node, or external parser runtime.
- Per-feed status and error tracking.
- Keyword rules for include, exclude, and highlight workflows.
- OPML import and export for feeds and categories.
- Launcher provider command: `>news`.
- IPC commands for refresh, read-state actions, panel toggling, and search.

## Install

Copy the `news-feed` directory to:

```text
~/.config/noctalia/plugins/news-feed
```

Then enable the plugin from Noctalia settings and add the bar widget where you want the unread badge.

## Configuration

The plugin ships with no bundled feeds. Add feeds from the plugin settings panel.

Default settings:

```json
{
  "feeds": [],
  "categories": [{ "id": "all", "name": "All", "color": "#A9AEFE" }],
  "rules": [],
  "refreshIntervalSec": 900,
  "maxItemsPerFeed": 25,
  "maxStoredItems": 500,
  "showOnlyUnread": false,
  "markReadOnOpen": true,
  "sortMode": "published-desc",
  "dedupeMode": "link-title",
  "readItemIds": [],
  "pinnedItemIds": [],
  "lastSelectedCategoryId": "all"
}
```

## Feed Rules

Rules match against article title, summary, author, source name, and category name.

- `include`: if an include rule applies to an item scope, matching items are kept and non-matching items in that scope are hidden.
- `exclude`: matching items are hidden.
- `highlight`: matching items stay visible and are highlighted in the panel and launcher.

## OPML

Import and export use `Quickshell.Io FileView`. Exported OPML includes feed URLs and categories only. It does not export read state, pinned state, or cached article data.

## Launcher

Open Noctalia launcher and type:

```text
>news
```

Add a query after the command to search cached article title, summary, source, author, and category.

## IPC

```bash
qs -c noctalia-shell ipc call plugin:news-feed refresh
qs -c noctalia-shell ipc call plugin:news-feed markAllRead
qs -c noctalia-shell ipc call plugin:news-feed clearReadState
qs -c noctalia-shell ipc call plugin:news-feed togglePanel
qs -c noctalia-shell ipc call plugin:news-feed search "query"
```

## Notes

- Refreshes do not overlap; a refresh request is ignored while another fetch is active.
- Feed failures are stored per feed and do not prevent other feeds from updating.
- Read state is pruned against the current cached item limit.
- No toast notifications are emitted for new items.
