--- === Cubby ===
---
--- Reach into a folder, grab whatever landed there most recently.
---
--- Two spots come stocked: the screenshot you just took, and whatever your
--- browser just downloaded. Open it, copy it, or find it in Finder — one call,
--- no digging through Desktop clutter or a Downloads folder sorted by name.
---
--- Usage:
---   hs.loadSpoon("Cubby")
---   spoon.Cubby:copy("screenshot")   -- clipboard, ready to paste into chat
---   spoon.Cubby:open("download")     -- opens with its default app
---   spoon.Cubby:reveal("screenshot") -- selected in Finder
---
--- Add a spot of your own:
---   spoon.Cubby.spots.receipts = { dir = "/path/to/folder", extensions = {"pdf"} }
---
--- Download: https://github.com/MadnessEngineering/Cubby.spoon

local obj = {}
obj.__index = obj

obj.name = "Cubby"
obj.version = "1.0"
obj.author = "Dan Edens"
obj.homepage = "https://github.com/MadnessEngineering/Cubby.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local function log()
    return _G.AppLogger or hs.logger.new("Cubby")
end

-- Deciding "copy as a picture" vs "copy as a file" by extension, not by spot,
-- so a spot mixing file types (a Downloads folder, say) still does the right
-- thing per file rather than committing to one behavior for everything in it.
local IMAGE_EXTENSIONS = {
    png = true, jpg = true, jpeg = true, gif = true,
    bmp = true, tiff = true, heic = true, webp = true,
}

--- Cubby.spots
--- Variable
--- Named folders to reach into. Each entry: `dir` (a path, or a function
--- returning one — `screenshot` resolves its real save location lazily, since
--- reading a macOS default on every spoon load would be wasteful) and
--- `extensions` (a list of lowercase extensions, or nil for any file).
--- Add your own, or edit these two, before calling anything else.
obj.spots = {
    screenshot = {
        dir = function()
            -- Most people never change this, but `defaults write
            -- com.apple.screencapture location` is one command away, and
            -- hardcoding ~/Desktop would silently miss every shot for anyone
            -- who has.
            local out = hs.execute("defaults read com.apple.screencapture location 2>/dev/null")
            out = out and out:gsub("%s+$", "")
            if out and out ~= "" then
                return (out:gsub("^~", os.getenv("HOME")))
            end
            return os.getenv("HOME") .. "/Desktop"
        end,
        extensions = { "png", "jpg", "jpeg", "gif", "bmp", "tiff" },
    },
    download = {
        dir = os.getenv("HOME") .. "/Downloads",
        extensions = nil,   -- whatever it is, it counts
    },
}

local function resolveDir(spot)
    if type(spot.dir) == "function" then return spot.dir() end
    return spot.dir
end

local function matchesExtension(filename, extensions)
    if not extensions then return true end
    local ext = filename:match("%.([%w]+)$")
    if not ext then return false end
    ext = ext:lower()
    for _, allowed in ipairs(extensions) do
        if allowed:lower() == ext then return true end
    end
    return false
end

--- Cubby.newestIn(dir, extensions)
--- Function
--- The newest file directly inside `dir` whose name matches `extensions` (a
--- list of lowercase extensions, or nil for any file). Does not recurse.
--- Returns nil if the directory does not exist or nothing inside matches.
---
--- A plain Lua directory scan rather than shelling out to `find | ls -t`: no
--- filename-in-a-shell-command quoting to get wrong, and no dependency on
--- which flavor of `find` is on $PATH.
function obj.newestIn(dir, extensions)
    if not dir or hs.fs.attributes(dir, "mode") ~= "directory" then return nil end

    local newestPath, newestTime
    for entry in hs.fs.dir(dir) do
        if entry ~= "." and entry ~= ".." and entry:sub(1, 1) ~= "." then
            local path = dir .. "/" .. entry
            if hs.fs.attributes(path, "mode") == "file" and matchesExtension(entry, extensions) then
                local mtime = hs.fs.attributes(path, "modification")
                if mtime and (not newestTime or mtime > newestTime) then
                    newestPath, newestTime = path, mtime
                end
            end
        end
    end
    return newestPath
end

--- Cubby:find(spotName)
--- Method
--- The newest file in a named spot, or nil (having alerted why) if there is
--- no such spot or nothing in it yet.
function obj:find(spotName)
    local spot = self.spots[spotName]
    if not spot then
        hs.alert.show("Cubby: no spot named '" .. tostring(spotName) .. "'")
        return nil
    end

    local dir = resolveDir(spot)
    local path = obj.newestIn(dir, spot.extensions)
    if not path then
        hs.alert.show("Cubby: nothing in " .. spotName .. " yet")
        log():i("find: " .. spotName .. " (" .. tostring(dir) .. ") is empty")
        return nil
    end
    return path
end

--- Percent-encode a filesystem path into a valid file:// URL. NSURL is lenient
--- about raw spaces in practice, but macOS's own default screenshot names
--- ("Screen Shot 2026-... at ... PM.png") have them, a comma, and colons in
--- the time -- worth encoding properly rather than trusting leniency.
local function fileURL(path)
    local encoded = path:gsub("[^%w%-%_%.%~/]", function(c)
        return string.format("%%%02X", c:byte())
    end)
    return "file://" .. encoded
end

--- Cubby:open(spotName)
--- Method
--- Opens the newest file in a spot with its default application.
function obj:open(spotName)
    local path = self:find(spotName)
    if not path then return end
    hs.task.new("/usr/bin/open", nil, { path }):start()
end

--- Cubby:reveal(spotName)
--- Method
--- Opens Finder with the newest file in a spot selected.
function obj:reveal(spotName)
    local path = self:find(spotName)
    if not path then return end
    hs.task.new("/usr/bin/open", nil, { "-R", path }):start()
end

--- Cubby:copy(spotName)
--- Method
--- Copies the newest file in a spot to the clipboard. An image copies as a
--- picture, ready to paste into a chat or a doc; anything else copies as a
--- file reference, ready to paste into Finder or an attachment field.
function obj:copy(spotName)
    local path = self:find(spotName)
    if not path then return end

    local ext = path:match("%.([%w]+)$")
    local ok
    if ext and IMAGE_EXTENSIONS[ext:lower()] then
        local image = hs.image.imageFromPath(path)
        if not image then
            hs.alert.show("Cubby: could not read " .. path:match("[^/]+$"))
            return
        end
        ok = hs.pasteboard.writeObjects(image)
    else
        ok = hs.pasteboard.writeObjects({ url = fileURL(path) })
    end

    if ok then
        hs.alert.show("Copied: " .. path:match("[^/]+$"))
    else
        hs.alert.show("Cubby: could not write to the clipboard")
    end
end

--- Cubby:captureNew()
--- Method
--- Takes a fresh screenshot with interactive selection and copies it straight
--- to the clipboard -- no file on disk, no floating thumbnail, no waiting for
--- `find` to notice a new Desktop file. A bonus, not a "spot": there is
--- nothing to look up first.
function obj:captureNew()
    hs.task.new("/usr/sbin/screencapture", function(exitCode)
        if exitCode == 0 then
            hs.alert.show("Screenshot copied to clipboard")
        else
            -- exit code 1 is the normal result of pressing Escape mid-selection
            if exitCode ~= 1 then
                hs.alert.show("Cubby: screencapture failed (" .. tostring(exitCode) .. ")")
            end
        end
    end, { "-i", "-c" }):start()
end

--- Cubby:bindHotkeys(mapping)
--- Method
--- Standard Spoon hotkey binding. Recognised keys: `copyScreenshot`,
--- `openScreenshot`, `revealScreenshot`, `captureNew`, `copyDownload`,
--- `openDownload`, `revealDownload`. Most configs skip this and bind straight
--- to `spoon.Cubby:copy` with `args` from `hotkeys.json` instead.
function obj:bindHotkeys(mapping)
    local spec = {
        copyScreenshot   = function() self:copy("screenshot") end,
        openScreenshot   = function() self:open("screenshot") end,
        revealScreenshot = function() self:reveal("screenshot") end,
        captureNew       = function() self:captureNew() end,
        copyDownload     = function() self:copy("download") end,
        openDownload     = function() self:open("download") end,
        revealDownload   = function() self:reveal("download") end,
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping)
    return self
end

return obj
