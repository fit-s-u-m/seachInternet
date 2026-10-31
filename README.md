# DuckDuckGo Search (DMS launcher plugin)

Search DuckDuckGo from the DankMaterialShell launcher.

## Install
Copy this folder to `~/.config/DankMaterialShell/plugins/duckduckgoSearch`, then restart DMS
(or reload plugins) and enable it in Settings -> Plugins.

Requires: `xdg-open`. No other dependencies (HTTP is done in QML).

The preview glimpse comes from Wikipedia (typo-tolerant), falling back to the DuckDuckGo Instant Answer API.
Note: the text you type is sent to those services for non-bang queries.

## Usage
Type the trigger (default `ddg `) followed by a query.

- `ddg linux kernel`: shows a short glimpse of the answer; Enter opens full results in the browser.
- `ddg what is 15% of 80`: glimpse if DDG returns one, otherwise just the search item.
- `ddg !yt lofi`: opens YouTube search in your default browser.
- `ddg !gh quickshell`, `ddg !w linux`, `ddg !aur foo`: any bang works.

The "Search DuckDuckGo" item is always shown. Bang queries never call the Instant Answer API.

## Change the trigger
Settings -> Plugins -> DuckDuckGo Search -> Trigger, or edit `"trigger"` in `plugin.json`
(the value saved in settings takes priority).
