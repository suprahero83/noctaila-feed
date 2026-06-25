# Noctalia News Feed Plugin Plan

## Summary

Build a new Noctalia v4 stable plugin named `news-feed` as a power-user RSS/Atom news aggregator. It will use a bar unread badge, a full panel for triage, settings-based feed and rule management, OPML import/export, launcher search, and quiet-by-default behavior with no bundled feeds.

## Current State

This workspace starts empty, so implementation should create a new `news-feed/` plugin directory. Noctalia v4 plugins are QML-based and use `manifest.json`, optional entry points such as `Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`, and `LauncherProvider.qml`.

The official registry already has an `rss-feed` plugin, so this plugin should be a cleaner, more capable sibling rather than a patch to that implementation.

## File Layout

Create:

```text
news-feed/
  manifest.json
  README.md
  CHANGELOG.md
  Main.qml
  BarWidget.qml
  Panel.qml
  Settings.qml
  LauncherProvider.qml
  lib/FeedParser.js
  lib/Opml.js
  lib/Rules.js
  lib/Utils.js
  i18n/en.json
  preview.png
```

## Manifest

Use:

```json
{
  "id": "news-feed",
  "name": "News Feed",
  "version": "1.0.0",
  "minNoctaliaVersion": "3.9.0",
  "author": "Corey",
  "license": "MIT",
  "repository": "https://github.com/corey/noctalia-news-feed",
  "description": "Power-user RSS and Atom news aggregator",
  "tags": ["Bar", "Panel", "Launcher", "Network", "Productivity"],
  "entryPoints": {
    "main": "Main.qml",
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml",
    "launcherProvider": "LauncherProvider.qml"
  },
  "dependencies": { "plugins": [] }
}
```

`minNoctaliaVersion` is `3.9.0` because launcher providers require Noctalia 3.9.0 or newer.

## Settings Schema

Default settings:

```js
{
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
}
```

Feed object:

```js
{ id, name, url, categoryId, enabled, pinned, priority, lastFetchedAt, lastStatus, lastError }
```

Rule object:

```js
{ id, name, mode: "include" | "exclude" | "highlight", terms: [], feedIds: [], categoryIds: [], enabled: true }
```

News item object:

```js
{ id, feedId, categoryId, title, link, summary, author, publishedAt, guid, matchedRuleIds, excluded }
```

## Architecture

`Main.qml` owns all feed state. It fetches feeds with `Quickshell.Io Process` and `curl`, parses RSS/Atom through `lib/FeedParser.js`, applies dedupe and keyword rules, computes unread counts, and exposes methods for the bar, panel, launcher, and IPC.

The bar and panel must not duplicate fetch/parse logic.

Use `Quickshell.Io FileView` for OPML import/export by path, with atomic writes for export. Keep all runtime self-contained in QML/JS plus `curl`; no Python, Node, `xmllint`, or third-party parser dependency.

## UI Behavior

### Bar Widget

`BarWidget.qml` shows:

- A `newspaper` or `rss` icon.
- Unread badge.
- Loading state.
- Error dot.

Left-click toggles the panel with `pluginApi.togglePanel(screen, root)`. Tooltip shows unread count and last refresh status.

### Panel

`Panel.qml` includes:

- Header with search, refresh, mark-all-read, and settings button.
- Filters for All, Unread, Pinned, Highlighted, and category chips.
- Article rows with source, title, summary, relative date, unread marker, matched keyword highlight, and pin action.

Opening an article calls `Qt.openUrlExternally()` and marks it read if enabled.

### Settings

`Settings.qml` manages:

- Feeds.
- Categories.
- Keyword rules.
- Refresh interval.
- Maximum item limits.
- Sorting.
- Dedupe mode.
- Read-on-open.
- OPML import/export path.

No default feeds are inserted automatically.

### Launcher Provider

`LauncherProvider.qml` provides the command `>news`.

It returns up to 50 cached items, searchable by title, summary, source, and category. Activating a result opens the article, closes launcher, and marks it read if enabled.

## IPC

Register `IpcHandler { target: "plugin:news-feed" }` in `Main.qml` with:

```text
refresh
markAllRead
clearReadState
togglePanel
search query
```

All IPC arguments are strings and must be validated before use.

## Error Handling

Per-feed failures should not fail the whole refresh. Store `lastStatus` and `lastError` per feed. Surface errors in the panel and as a bar error dot.

Keep quiet badge-only behavior by default; no toast notifications for new items.

## Testing

Test these scenarios:

- Empty install shows zero unread and helpful empty states.
- Add one valid RSS feed, refresh, view sorted articles.
- Add one Atom feed, verify links, titles, dates, and summaries parse.
- Invalid feed URL records an error without breaking other feeds.
- Duplicate item links/titles collapse under `dedupeMode: "link-title"`.
- Include, exclude, and highlight keyword rules apply correctly.
- Opening an item marks it read and updates bar, panel, and launcher.
- Mark all read persists through Noctalia restart.
- Pinned items remain visible in pinned filter.
- OPML import ignores duplicates and validates missing URLs.
- OPML export writes feeds/categories only, not read state.
- Launcher `>news` returns cached results and opens selected articles.
- IPC `refresh` and `markAllRead` work from `qs -c noctalia-shell ipc call ...`.
- Vertical and horizontal bars render without clipped text.
- Refresh timer does not overlap concurrent fetches.

## Assumptions

- Target Noctalia v4 stable, not v5 alpha.
- Build a new plugin ID: `news-feed`.
- Ship no bundled feeds.
- Use quiet badge-only new-item behavior.
- Store feed config and read state in plugin settings.
- Prune `readItemIds` to the latest `maxStoredItems`.
- Use English-only i18n for v1, with the structure ready for more languages.

## References

- Noctalia plugin overview: https://docs.noctalia.dev/v4/development/plugins/overview/
- Noctalia manifest reference: https://docs.noctalia.dev/v4/development/plugins/manifest/
- Noctalia bar widget docs: https://docs.noctalia.dev/v4/development/plugins/bar-widget/
- Noctalia panel docs: https://docs.noctalia.dev/v4/development/plugins/panel/
- Noctalia settings UI docs: https://docs.noctalia.dev/v4/development/plugins/settings-ui/
- Noctalia launcher provider docs: https://docs.noctalia.dev/v4/development/plugins/launcher-provider/
- Noctalia plugin IPC docs: https://docs.noctalia.dev/v4/development/plugins/ipc/
- Existing official `rss-feed` plugin: https://github.com/noctalia-dev/legacy-v4-plugins/tree/main/rss-feed
- Quickshell `Process`: https://quickshell.org/docs/v0.2.0/types/Quickshell.Io/Process/
- Quickshell `FileView`: https://quickshell.org/docs/v0.2.0/types/Quickshell.Io/FileView/
