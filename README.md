# Cubby.spoon

> *Reach into a folder, grab whatever landed there most recently.*

A Hammerspoon Spoon for the "where did that just go" moment: the screenshot
you took two seconds ago, the file your browser just finished downloading.
One call finds it, no digging through a Desktop full of old shots or a
Downloads folder sorted by name.

Two spots come stocked:

| Spot | Where | Matches |
| --- | --- | --- |
| `screenshot` | wherever macOS actually saves them — reads the real `defaults` setting, not a hardcoded `~/Desktop` | `.png .jpg .jpeg .gif .bmp .tiff` |
| `download` | `~/Downloads` | anything |

Add your own — a folder is all it takes:

```lua
spoon.Cubby.spots.receipts = { dir = "/path/to/folder", extensions = { "pdf" } }
```

## Install

```sh
git clone https://github.com/MadnessEngineering/Cubby.spoon.git \
  ~/.hammerspoon/Spoons/Cubby.spoon
```

```lua
hs.loadSpoon("Cubby")

spoon.Cubby:bindHotkeys({
    copyScreenshot = { { "cmd", "ctrl", "alt" }, "i" },
    openDownload   = { { "cmd", "ctrl", "alt" }, "d" },
})
```

Most configs skip `bindHotkeys` and point at the methods straight from
`hotkeys.json` (see [BindForge.spoon](https://github.com/MadnessEngineering/BindForge.spoon)):

```json
{ "id": "hammer+i", "mods": "hammer", "key": "i",
  "description": "Copy latest screenshot",
  "action": { "kind": "call", "fn": "spoon.Cubby:copy", "args": ["screenshot"] } }
```

## What it does with what it finds

| Method | |
| --- | --- |
| `:open(spot)` | opens it with its default app |
| `:reveal(spot)` | selects it in Finder |
| `:copy(spot)` | puts it on the clipboard |
| `:find(spot)` | just the path, or nil (having alerted why) |
| `:captureNew()` | takes a fresh screenshot with interactive selection, straight to the clipboard — no file ever touches disk |

`:copy` looks at the file, not the spot: an image copies as a picture, ready
to paste into a chat or a doc; anything else copies as a file reference,
ready to paste into Finder or an attachment field. A `download` spot holding
today a screenshot and tomorrow a `.dmg` does the right thing either way.

## The small print that turned out to matter

- **Real file paths, not shell strings.** Every launch goes through
  `hs.task` with an argv array — a filename with a space, an apostrophe, or
  parentheses (macOS's own default screenshot names have all three) never
  touches a shell and never needs escaping.
- **A directory can be named `whatever.png`.** It happens more than you'd
  think — an unzip, an export folder. `newestIn` checks that every candidate
  is actually a file before it counts.
- **The file-URL copy is percent-encoded**, verified against a real macOS
  pasteboard: `public.file-url` and `NSFilenamesPboardType` both come back
  clean, so the file pastes into Finder as itself, not as a broken link.

---

Part of [Madness Interactive](https://github.com/MadnessEngineering). MIT.
