--[[
  @description Project Launcher
  @author Reapertips (Alejandro Hernandez)
  @version 1.0.1
  @license MIT
  @changelog
    - The toolbar button now lights up while Project Launcher is open.
    - Click the button again to close it. No more "new instance" prompt!
    - Pick your own accent color in `Settings` > `General`. It's saved per theme, and `Reset` brings back your theme's color.
    - `About` now tells you where the accent color comes from.
  @link
    Reapertips https://www.reapertips.com
  @about
    # Project Launcher

    Project Launcher puts your recent projects, project templates and project
    folders in one window. You can search everything, check the project
    details and open it without digging through folders.

    ## Project templates

    Organize your templates into sections without moving any files. You can
    check the track list before opening one, then open it as a new project or
    edit the template itself.

    ## Project folders

    Add your project folders and Project Launcher scans them in the
    background. It remembers the results, so they are ready the next time you
    open it.

    ## Startup

    Project Launcher can open with REAPER and stay hidden when another project
    is already open.

    ## Shortcuts

    - `Enter` opens the selected project.
    - `Ctrl/Cmd` + `Enter` opens it in a new tab.
    - `Alt/Option` + `Enter` opens it as a new version.
    - `Ctrl/Cmd` + `F` jumps to search.
    - `Esc` clears the search or closes the window.

    ## Requirements

    You need **ReaImGui 0.10 or newer**. Project Launcher checks this when it
    starts and tells you if it is missing.

    **js_ReaScriptAPI** is optional. It adds modified dates and a folder
    picker. **SWS** is also optional and lets Project Launcher switch off
    REAPER's own startup prompt.

    ## Credits and license

    Project Launcher is MIT licensed.

    The startup hook handling is adapted from **Gridbox** by Ilias-Timon
    Poulakis (FeedTheCat), used under the MIT license:

    > MIT License
    >
    > Copyright (c) 2020 iliaspoulakis
    >
    > Permission is hereby granted, free of charge, to any person obtaining a
      copy of this software and associated documentation files (the
      "Software"), to deal in the Software without restriction, including
      without limitation the rights to use, copy, modify, merge, publish,
      distribute, sublicense, and/or sell copies of the Software, and to
      permit persons to whom the Software is furnished to do so, subject to
      the following conditions:
    >
    > The above copyright notice and this permission notice shall be included
      in all copies or substantial portions of the Software.
    >
    > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
      OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
      IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
      CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
      TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
      SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

------------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------------

local SB = {
    NAME    = 'Project Launcher',
    VERSION = '1.0.1',
    EXTNAME = 'RTIPS.ProjectLauncher',
    OLD_EXTNAME = 'RTIPS.StartBox',
}

local ImGui
do
    local ok, path = pcall(function() return reaper.ImGui_GetBuiltinPath() end)
    if not ok or not path then
        reaper.MB('Project Launcher needs ReaImGui.\n\n' ..
            'Install it with ReaPack:\nExtensions > ReaPack > Browse packages ' ..
            '> search "ReaImGui" > install "ReaImGui: ReaScript binding for ' ..
            'Dear ImGui".', 'Project Launcher', 0)
        return
    end
    package.path = path .. '/?.lua'
    local ok2, mod = pcall(function() return require 'imgui' '0.10' end)
    if not ok2 then
        reaper.MB('Project Launcher needs ReaImGui 0.10 or newer.\n\n' ..
            'Update it with ReaPack: Extensions > ReaPack > Synchronize ' ..
            'packages.\n\n' .. tostring(mod), 'Project Launcher', 0)
        return
    end
    ImGui = mod
end

local HAS_JS  = reaper.JS_File_Stat ~= nil
local HAS_SWS = reaper.CF_LocateInExplorer ~= nil or reaper.BR_Win32_GetPrivateProfileString ~= nil

local OS      = reaper.GetOS()
local IS_WIN  = OS:find('Win') ~= nil
local IS_MAC  = OS:find('OSX') ~= nil or OS:find('macOS') ~= nil
local SEP     = IS_WIN and '\\' or '/'
SB.SEP = SEP


-- Every ReaImGui name this script touches. Checked once at start so a
-- missing one becomes a clear message instead of a crash mid-frame.
local API_NAMES = {
    'Attach', 'Begin', 'BeginChild', 'BeginDisabled',
    'BeginDragDropSource', 'BeginDragDropTarget', 'SetDragDropPayload',
    'AcceptDragDropPayload', 'EndDragDropSource', 'EndDragDropTarget',
    'BeginPopupContextItem', 'BeginPopupModal', 'BeginTable', 'Button',
    'Combo', 'AlignTextToFramePadding', 'NewLine', 'SetNextWindowPos',
    'CalcTextSize', 'Checkbox', 'ChildFlags_AlwaysUseWindowPadding',
    'CloseCurrentPopup', 'ColorEdit3', 'ColorEditFlags_NoInputs',
    'Col_Border', 'Col_Button', 'Col_ButtonActive',
    'Col_ButtonHovered', 'Col_CheckMark', 'Col_ChildBg', 'Col_FrameBg',
    'Col_FrameBgActive', 'Col_FrameBgHovered', 'Col_Header',
    'Col_HeaderActive', 'Col_HeaderHovered', 'Col_ModalWindowDimBg',
    'Col_PopupBg', 'Col_ResizeGrip', 'Col_ResizeGripActive',
    'Col_ResizeGripHovered', 'Col_ScrollbarBg', 'Col_ScrollbarGrab',
    'Col_ScrollbarGrabActive', 'Col_ScrollbarGrabHovered', 'Col_Separator',
    'Col_SeparatorActive', 'Col_SeparatorHovered', 'Col_TableBorderLight',
    'Col_TableBorderStrong', 'Col_TableHeaderBg', 'Col_TableRowBgAlt',
    'Col_Text', 'Col_TextDisabled', 'Col_TitleBgActive', 'Col_WindowBg',
    'Cond_Appearing', 'Cond_FirstUseEver',
    'ConfigVar_WindowsMoveFromTitleBarOnly', 'CreateContext',
    'CreateListClipper', 'DrawList_AddLine', 'DrawList_AddRectFilled',
    'DrawList_PathArcTo', 'DrawList_PathClear', 'DrawList_PathFillConcave',
    'DrawList_AddText', 'DrawList_PushClipRect', 'DrawList_PopClipRect',
    'Dummy', 'End', 'EndChild', 'EndDisabled', 'EndPopup', 'EndTable',
    'GetContentRegionAvail', 'GetCursorPosX', 'GetCursorPosY',
    'GetCursorScreenPos', 'GetFrameHeight', 'GetKeyMods', 'GetMousePos',
    'GetScrollY', 'GetStyleVar', 'GetTextLineHeight', 'GetWindowPos',
    'GetWindowSize', 'DrawList_AddRect',
    'GetTextLineHeightWithSpacing', 'GetWindowDrawList', 'GetWindowWidth',
    'HoveredFlags_ChildWindows', 'InputTextWithHint',
    'InputTextFlags_EnterReturnsTrue', 'InvisibleButton',
    'IsItemActive', 'IsItemHovered', 'IsKeyPressed',
    'IsMouseDoubleClicked', 'IsWindowHovered', 'Key_Comma', 'Key_D',
    'Key_DownArrow', 'Key_End', 'Key_Enter', 'Key_Escape', 'Key_F',
    'Key_F5', 'Key_Home', 'Key_KeypadEnter', 'Key_N', 'Key_O',
    'Key_PageDown', 'Key_PageUp', 'Key_UpArrow', 'ListClipper_Begin',
    'ListClipper_GetDisplayRange', 'ListClipper_Step', 'MenuItem',
    'BeginMenu', 'EndMenu', 'Mod_Alt', 'Mod_Ctrl', 'Mod_Super',
    'OpenPopup', 'PopFont', 'PopID',
    'PopStyleColor', 'PopStyleVar', 'PushFont', 'PushID', 'PushStyleColor',
    'PushStyleVar', 'SameLine', 'Selectable',
    'SelectableFlags_AllowDoubleClick', 'SelectableFlags_SpanAllColumns',
    'Separator', 'SetConfigVar', 'SetCursorPosX', 'SetCursorPosY',
    'SetKeyboardFocusHere', 'SetNextItemWidth',
    'SetNextWindowFocus', 'SetNextWindowSize',
    'SetNextWindowSizeConstraints', 'SetScrollHereY',
    'SmallButton', 'SortDirection_Descending', 'StyleVar_ButtonTextAlign',
    'StyleVar_CellPadding', 'StyleVar_ChildBorderSize',
    'StyleVar_ChildRounding', 'StyleVar_FramePadding',
    'StyleVar_FrameRounding', 'StyleVar_GrabRounding',
    'StyleVar_ItemSpacing', 'StyleVar_PopupRounding',
    'StyleVar_ScrollbarRounding', 'StyleVar_ScrollbarSize',
    'StyleVar_WindowBorderSize', 'StyleVar_WindowPadding',
    'StyleVar_WindowRounding', 'TableColumnFlags_DefaultHide',
    'TableColumnFlags_NoHeaderLabel', 'TableColumnFlags_NoHide',
    'TableColumnFlags_NoReorder', 'TableColumnFlags_NoResize',
    'TableColumnFlags_NoSort', 'TableColumnFlags_PreferSortDescending',
    'TableColumnFlags_WidthFixed', 'TableColumnFlags_WidthStretch',
    'TableFlags_Hideable', 'TableFlags_Reorderable',
    'TableFlags_Resizable', 'TableFlags_ScrollY',
    'TableFlags_SizingStretchProp', 'TableFlags_SortTristate',
    'TableFlags_Sortable', 'TableGetColumnSortSpecs', 'TableHeadersRow',
    'TableNeedSort', 'TableNextRow', 'TableSetColumnIndex',
    'TableSetupColumn', 'TableSetupScrollFreeze', 'Text', 'TextColored',
    'TextWrapped', 'WindowFlags_AlwaysAutoResize', 'WindowFlags_NoCollapse', 'WindowFlags_NoScrollWithMouse', 'WindowFlags_NoScrollbar',
    'WindowFlags_NoTitleBar',
}

function SB.check_api()
    local missing = {}
    for _, name in ipairs(API_NAMES) do
        if rawget(ImGui, name) == nil then missing[#missing + 1] = name end
    end
    return missing
end

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

function SB.join(...)
    local parts, out = { ... }, nil
    for _, p in ipairs(parts) do
        if p and p ~= '' then
            if out == nil then
                out = p
            else
                out = out:gsub('[/\\]+$', '') .. SEP .. p:gsub('^[/\\]+', '')
            end
        end
    end
    return out or ''
end

function SB.split_path(path)
    local dir, file = path:match('^(.*)[/\\]([^/\\]*)$')
    if not dir then return '', path end
    return dir, file
end

-- The last component of a folder path. split_path on a path with a trailing
-- separator hands back an empty name, which is how the whole path ended up
-- in the rail.
-- A configured folder in the form everything else compares against: no
-- trailing separator, EXCEPT where the separator is the whole address.
-- '/' would otherwise become '' and never be scanned, and 'C:\\' would
-- become 'C:', which on Windows means the current directory of that drive
-- rather than the drive itself.
function SB.root_base(path)
    path = tostring(path or '')
    local base = (path:gsub('[/\\]+$', ''))
    if base == '' or base:match('^%a:$') then return path end
    return base
end

function SB.dir_name(path)
    path = tostring(path or '')
    local base = (path:gsub('[/\\]+$', ''))
    if base == '' then return path end          -- the root itself
    return base:match('[^/\\]+$') or base
end

function SB.strip_ext(name)
    return (name:gsub('%.[^.]+$', ''))
end

function SB.ext(name)
    return (name:match('%.([^.]+)$') or ''):lower()
end

-- Shortens a folder for display: keeps the last `keep` components.
function SB.short_dir(dir, keep)
    keep = keep or 3
    local parts = {}
    for piece in dir:gmatch('[^/\\]+') do parts[#parts + 1] = piece end
    if #parts <= keep then return dir end
    local out = {}
    for i = #parts - keep + 1, #parts do out[#out + 1] = parts[i] end
    return '...' .. SEP .. table.concat(out, SEP)
end

function SB.file_size(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    -- A drive that goes away mid-seek raises; a wrong size is better than
    -- a dead script.
    local ok, size = pcall(f.seek, f, 'end')
    f:close()
    return ok and size or nil
end

function SB.human_size(bytes)
    if not bytes then return '-' end
    if bytes < 1024 then return string.format('%d B', bytes) end
    if bytes < 1024 * 1024 then return string.format('%.0f KB', bytes / 1024) end
    if bytes < 1024 * 1024 * 1024 then
        return string.format('%.1f MB', bytes / 1024 / 1024)
    end
    return string.format('%.2f GB', bytes / 1024 / 1024 / 1024)
end

function SB.human_time(seconds)
    if not seconds or seconds <= 0 then return '-' end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m >= 60 then
        return string.format('%d:%02d:%02d', math.floor(m / 60), m % 60, s)
    end
    return string.format('%d:%02d', m, s)
end

-- One shape for every date in the column: 08/20/26. Relative words like
-- "yesterday" read nicely on their own but wreck a column you scan.
function SB.relative_date(stamp)
    if not stamp or stamp <= 0 then return '' end
    return os.date('%m/%d/%y', stamp)
end

-- Diagnostics for the one thing that depends on another extension.
function SB.js_probe(path)
    if not HAS_JS then return 'js_ReaScriptAPI not installed' end
    local ok, a, b, c, d, e = pcall(reaper.JS_File_Stat, path)
    return ('JS_File_Stat -> %s | %s | %s | %s | %s | %s'):format(
        tostring(ok), tostring(a), tostring(b), tostring(c), tostring(d),
        tostring(e))
end

function SB.file_mtime(path)
    if not HAS_JS then return nil end
    local ok, _, _, _, mtime = pcall(reaper.JS_File_Stat, path)
    if not ok then return nil end
    if type(mtime) == 'number' then return SB.sane_time(math.floor(mtime)) end
    if type(mtime) ~= 'string' then return nil end
    local y, mo, d = mtime:match('(%d%d%d%d)[-./](%d%d)[-./](%d%d)')
    if not y then return nil end
    -- Windows' mktime cannot represent anything before 1970 and Lua turns
    -- that into a hard error, so reject the year before asking.
    if tonumber(y) < 1970 then return nil end
    local h, mi, sec = mtime:match('(%d%d):(%d%d):(%d%d)')
    local ok2, stamp = pcall(os.time, {
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h) or 12, min = tonumber(mi) or 0,
        sec = tonumber(sec) or 0,
    })
    return ok2 and SB.sane_time(stamp) or nil
end

-- A file on an unplugged drive can hand back a timestamp from 1963. Nothing
-- older than REAPER itself is a real project date.
function SB.sane_time(t)
    if type(t) ~= 'number' then return nil end
    if t < 1041379200 then return nil end       -- 1 Jan 2003
    if t > os.time() + 86400 then return nil end
    return t
end

-- Five-point star with rounded corners, as a list of arcs. Every corner is
-- replaced by an arc of radius `round` tangent to both of its edges, which
-- is the only way to get round points: a filled polygon has sharp ones and
-- ImGui's thick outlines are mitred, so they stay sharp too.
function SB.star_arcs(cx, cy, r, round)
    local pts = {}
    for i = 0, 9 do
        local rad = (i % 2 == 0) and r or r * 0.382   -- classic star ratio
        local a = -math.pi / 2 + i * math.pi / 5
        pts[#pts + 1] = { cx + math.cos(a) * rad, cy + math.sin(a) * rad }
    end

    local arcs = {}
    for i = 1, 10 do
        local p    = pts[i]
        local prev = pts[(i - 2) % 10 + 1]
        local next = pts[i % 10 + 1]

        local ux, uy = prev[1] - p[1], prev[2] - p[2]
        local vx, vy = next[1] - p[1], next[2] - p[2]
        local ul = math.sqrt(ux * ux + uy * uy)
        local vl = math.sqrt(vx * vx + vy * vy)
        ux, uy, vx, vy = ux / ul, uy / ul, vx / vl, vy / vl

        local dot  = math.max(-1, math.min(1, ux * vx + uy * vy))
        local half = math.acos(dot) / 2                -- half the corner
        local tan  = math.tan(half)
        -- The five points get the full radius; the notches between them get
        -- much less, or the star turns into a starfish.
        local want = (i % 2 == 1) and round or round * 0.45
        -- Never eat more than half of the shortest edge.
        local rc   = math.min(want, tan * math.min(ul, vl) * 0.5)
        local back = rc / tan                          -- tangent distance
        local dist = rc / math.sin(half)               -- corner to center

        local bx, by = ux + vx, uy + vy
        local bl = math.sqrt(bx * bx + by * by)
        if bl < 1e-9 then bx, by, bl = -uy, ux, 1 end
        local ox = p[1] + bx / bl * dist
        local oy = p[2] + by / bl * dist

        local a0 = math.atan(p[2] + uy * back - oy, p[1] + ux * back - ox)
        local a1 = math.atan(p[2] + vy * back - oy, p[1] + vx * back - ox)
        while a1 - a0 >  math.pi do a1 = a1 - 2 * math.pi end
        while a0 - a1 >  math.pi do a1 = a1 + 2 * math.pi end

        arcs[#arcs + 1] = { ox, oy, rc, a0, a1 }
    end
    return arcs
end

------------------------------------------------------------------------------
-- Settings (ExtState)
------------------------------------------------------------------------------

-- This was called StartBox until 1.0. Anything saved under the old name is
-- copied across once, so favorites, folders and sections survive the rename
-- without the user doing anything.
--
-- Once only, and behind a flag: an empty value is a real answer. Emptying
-- your favorites, or removing your last project folder, stores '' - and a
-- migration that fires whenever the new value is empty would hand the old
-- list straight back on the next launch, every launch.
SB.MIGRATE_SKIP = { hook_cmd_name = true, migrated = true }

local function get_ext(key, default)
    local v = reaper.GetExtState(SB.EXTNAME, key)
    if v == '' and not SB.migrated and SB.OLD_EXTNAME
            and not SB.MIGRATE_SKIP[key] then
        local old = reaper.GetExtState(SB.OLD_EXTNAME, key)
        if old ~= '' then
            reaper.SetExtState(SB.EXTNAME, key, old, true)
            return old
        end
    end
    if v == '' then return default end
    return v
end

local function set_ext(key, value)
    reaper.SetExtState(SB.EXTNAME, key, tostring(value), true)
end

local function get_bool(key, default)
    -- Through get_ext, so the old settings come across with everything else.
    local v = get_ext(key, nil)
    if v == nil then return default end
    return v == '1'
end

local function set_bool(key, value)
    set_ext(key, value and '1' or '0')
end

-- Persisted ExtState ends up in reaper-extstate.ini, one key per line, so a
-- value with a newline in it loses everything after the first entry the next
-- time REAPER starts. Unit separator instead; \n is still read so lists
-- saved by earlier versions survive the upgrade.
SB.LIST_SEP = '\31'

function SB.list_decode(str)
    local out = {}
    for line in tostring(str or ''):gmatch('[^\31\n]+') do
        if line ~= '' then out[#out + 1] = line end
    end
    return out
end

function SB.list_encode(list)
    return table.concat(list, SB.LIST_SEP)
end

------------------------------------------------------------------------------
-- Template sections
--
-- REAPER itself does not look inside subfolders of ProjectTemplates, so
-- almost nobody has any - which means the folders that matter have to be
-- ones Project Launcher keeps. Sections live in ExtState and never touch the disk:
-- making one, renaming it or throwing it away moves no files. A real
-- subfolder, if someone does have one, becomes a section of the same name
-- automatically, and a template that was filed by hand overrides it.
------------------------------------------------------------------------------

SB.SCAN_DEPTH = 5
SB.VIEWS = { recent = 'Recent', templates = 'Templates', folders = 'Folders' }
SB.OPEN_ON = { 'last', 'recent', 'templates', 'folders' }
SB.OPEN_ON_LABEL = 'Last used\0Recent\0Templates\0Folders\0'
SB.UNSORTED = 'Unsorted'
SB.DND = 'SB_TEMPLATE'
SB.PAIR_SEP = '\30'

-- 'path<RS>section' entries, joined the same way every other list is.
function SB.map_decode(str)
    local out = {}
    for entry in tostring(str or ''):gmatch('[^\31\n]+') do
        local path, section = entry:match('^(.-)' .. SB.PAIR_SEP .. '(.*)$')
        if path and path ~= '' and section ~= '' then out[path] = section end
    end
    return out
end

function SB.map_encode(map)
    local keys = {}
    for path in pairs(map) do keys[#keys + 1] = path end
    table.sort(keys)
    local parts = {}
    for _, path in ipairs(keys) do
        parts[#parts + 1] = path .. SB.PAIR_SEP .. map[path]
    end
    return table.concat(parts, SB.LIST_SEP)
end

SB.cfg = {}

function SB.cfg_load()
    SB.migrated = reaper.GetExtState(SB.EXTNAME, 'migrated') == '1'
    SB.cfg.favorites     = SB.list_decode(get_ext('favorites', ''))
    SB.cfg.roots         = SB.list_decode(get_ext('roots', ''))
    -- Not a setting any more. Five levels covers every layout anyone
    -- actually uses (Folder / Year / Client / Project / file) and the scan
    -- is incremental, so the cost of the extra levels is not felt.
    SB.cfg.depth         = SB.SCAN_DEPTH
    reaper.DeleteExtState(SB.EXTNAME, 'depth', true)
    SB.cfg.hide_missing  = get_bool('hide_missing', true)
    SB.cfg.keep_open     = get_bool('keep_open', false)
    SB.cfg.skip_if_open  = get_bool('skip_if_open', true)
    SB.cfg.view          = get_ext('view', 'recent')
    SB.cfg.open_on       = get_ext('open_on', 'last')
    SB.cfg.sections      = SB.list_decode(get_ext('sections', ''))
    SB.cfg.filed         = SB.map_decode(get_ext('filed', ''))
    SB.cfg.used          = SB.map_decode(get_ext('used', ''))
    local scale_pct = math.floor(SB.UI_DEFAULT.scale * 100 + 0.5)
    local font_pct   = math.floor(SB.UI_DEFAULT.font * 100 + 0.5)
    SB.ui.scale = math.max(0.8, math.min(2.0,
        (tonumber(get_ext('scale', tostring(scale_pct))) or scale_pct) / 100))
    SB.ui.font  = math.max(0.8, math.min(1.6,
        (tonumber(get_ext('font', tostring(font_pct))) or font_pct) / 100))
    SB.fav_set = {}
    for _, p in ipairs(SB.cfg.favorites) do SB.fav_set[p] = true end
    if not SB.migrated then
        SB.migrated = true
        reaper.SetExtState(SB.EXTNAME, 'migrated', '1', true)
    end
end

-- Where a template sits: filed by hand first, then the real subfolder it
-- came from, and Unsorted for anything left at the top level.
function SB.section_of(item)
    local filed = SB.cfg.filed[item.path]
    if filed and filed ~= '' then return filed end
    if item.group and item.group ~= '' then return item.group end
    return SB.UNSORTED
end

-- Passing nil clears the filing (so a real subfolder shows through again);
-- passing SB.UNSORTED pins it to Unsorted, which is the only way to get a
-- template out of the subfolder it happens to live in.
function SB.file_under(path, section)
    if section == nil or section == '' then
        SB.cfg.filed[path] = nil
    else
        SB.cfg.filed[path] = section
    end
    set_ext('filed', SB.map_encode(SB.cfg.filed))
end

function SB.sections_save()
    set_ext('sections', SB.list_encode(SB.cfg.sections))
end

function SB.section_index(name)
    for i, s in ipairs(SB.cfg.sections) do
        if s == name then return i end
    end
end

-- Control characters would split the stored list in two on the next
-- launch, so they never make it into a name.
function SB.clean_name(name)
    name = tostring(name or ''):gsub('[%z\1-\31]', ' ')
    return (name:gsub('^%s+', ''):gsub('%s+$', ''))
end

function SB.section_add(name)
    name = SB.clean_name(name)
    if name == '' or name == SB.UNSORTED then return false end
    if SB.section_index(name) then return false end
    SB.cfg.sections[#SB.cfg.sections + 1] = name
    SB.sections_save()
    return true
end

function SB.section_rename(old, new)
    new = SB.clean_name(new)
    local at = SB.section_index(old)
    if not at or new == '' or new == SB.UNSORTED then return false end
    if new ~= old and SB.section_index(new) then return false end
    SB.cfg.sections[at] = new
    -- Templates are filed by name, so every one of them moves with it.
    for path, section in pairs(SB.cfg.filed) do
        if section == old then SB.cfg.filed[path] = new end
    end
    SB.sections_save()
    set_ext('filed', SB.map_encode(SB.cfg.filed))
    return true
end

-- Deleting a section is not deleting anything of the user's: the templates
-- that were in it go back to Unsorted, and no file moves.
function SB.section_remove(name)
    local at = SB.section_index(name)
    if not at then return false end
    table.remove(SB.cfg.sections, at)
    for path, section in pairs(SB.cfg.filed) do
        if section == name then SB.cfg.filed[path] = nil end
    end
    SB.sections_save()
    set_ext('filed', SB.map_encode(SB.cfg.filed))
    return true
end

function SB.section_move(name, delta)
    local at = SB.section_index(name)
    if not at then return false end
    local to = at + delta
    if to < 1 or to > #SB.cfg.sections then return false end
    table.remove(SB.cfg.sections, at)
    table.insert(SB.cfg.sections, to, name)
    SB.sections_save()
    return true
end

-- The rail's list: the user's own sections in their order, then any real
-- subfolder nobody has filed away, and Unsorted last when it holds anything.
function SB.section_list(items)
    local counts, seen, out = {}, {}, {}
    for _, item in ipairs(items or {}) do
        local name = SB.section_of(item)
        counts[name] = (counts[name] or 0) + 1
    end
    for _, name in ipairs(SB.cfg.sections) do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = { name = name, count = counts[name] or 0, own = true }
        end
    end
    local extra = {}
    for name in pairs(counts) do
        if not seen[name] and name ~= SB.UNSORTED then extra[#extra + 1] = name end
    end
    table.sort(extra, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(extra) do
        out[#out + 1] = { name = name, count = counts[name], own = false }
    end
    if counts[SB.UNSORTED] and #out > 0 then
        out[#out + 1] = { name = SB.UNSORTED, count = counts[SB.UNSORTED],
                          own = false, unsorted = true }
    end
    return out
end

-- Adding and removing project folders happens in the Folders rail, beside
-- the folders themselves - the same rule Sections follow in Templates.
-- One key for "the same folder": case folded where the system folds it, and
-- separators normalized, or C:\\Music and C:/Music would be two folders and
-- every project in them would be listed twice.
function SB.root_key(path)
    return SB.path_key((SB.root_base(path):gsub('[/\\]', SEP)))
end

-- Is there really a folder there? file_exists says no for directories, so
-- the test is whether it can be enumerated - and for a folder that is empty,
-- whether its parent lists it.
function SB.is_dir(path)
    local base = SB.root_base(path)
    if base == '' then return false end
    if reaper.EnumerateSubdirectories(base, 0) ~= nil then return true end
    if reaper.EnumerateFiles(base, 0) ~= nil then return true end
    local parent, leaf = SB.split_path(base)
    if parent == '' or leaf == '' then return false end
    local i, sub = 0, reaper.EnumerateSubdirectories(parent, 0)
    while sub do
        if SB.path_key(sub) == SB.path_key(leaf) then return true end
        i = i + 1
        sub = reaper.EnumerateSubdirectories(parent, i)
    end
    return false
end

function SB.root_add(path)
    path = tostring(path or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if path == '' then return false end
    local key = SB.root_key(path)
    for _, r in ipairs(SB.cfg.roots) do
        if SB.root_key(r) == key then
            return false, 'That folder is already in the list'
        end
    end
    if not SB.is_dir(path) then return false, 'No folder there' end
    SB.cfg.roots[#SB.cfg.roots + 1] = path
    set_ext('roots', SB.list_encode(SB.cfg.roots))
    return true
end

function SB.root_remove(path)
    local key = SB.root_key(path)
    for i, r in ipairs(SB.cfg.roots) do
        if SB.root_key(r) == key then
            table.remove(SB.cfg.roots, i)
            set_ext('roots', SB.list_encode(SB.cfg.roots))
            return true
        end
    end
    return false
end

function SB.mark_used(path)
    if not path or path == '' then return end
    SB.cfg.used[path] = tostring(math.floor(os.time()))
    set_ext('used', SB.map_encode(SB.cfg.used))
end

function SB.used_at(path)
    return tonumber(SB.cfg.used[path] or '') or 0
end

function SB.fav_toggle(path)
    if SB.fav_set[path] then
        SB.fav_set[path] = nil
        for i, p in ipairs(SB.cfg.favorites) do
            if p == path then table.remove(SB.cfg.favorites, i) break end
        end
    else
        SB.fav_set[path] = true
        table.insert(SB.cfg.favorites, path)
    end
    set_ext('favorites', SB.list_encode(SB.cfg.favorites))
end

------------------------------------------------------------------------------
-- Recent projects (parsed from reaper.ini, no extension needed)
------------------------------------------------------------------------------

-- REAPER stores recents in [Recent] as recent01..recentNN.
-- The HIGHEST index is the most recently opened one.
function SB.parse_recent_ini(text)
    local entries, in_section = {}, false
    for line in text:gmatch('[^\r\n]+') do
        local section = line:match('^%[(.-)%]%s*$')
        if section then
            in_section = section:lower() == 'recent'
        elseif in_section then
            local key, value = line:match('^([^=]+)=(.*)$')
            if key then
                local idx = key:lower():match('^recent(%d+)$')
                if idx and value ~= '' then
                    entries[#entries + 1] = { idx = tonumber(idx), path = value }
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.idx > b.idx end)
    local paths, seen = {}, {}
    for _, e in ipairs(entries) do
        local key = SB.path_key(e.path)
        if not seen[key] then
            seen[key] = true
            paths[#paths + 1] = e.path
        end
    end
    return paths
end

-- Windows and macOS treat Mix.rpp and mix.rpp as one file; Linux does not,
-- and folding case there would silently hide one of two real projects.
local CASE_FOLD = IS_WIN or IS_MAC

function SB.path_key(path)
    return CASE_FOLD and path:lower() or path
end

function SB.read_file(path, max_bytes)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read(max_bytes or 'a')
    f:close()
    return data
end

function SB.load_recents()
    local ini = reaper.get_ini_file()
    local text = ini and SB.read_file(ini)
    if not text then return {} end
    local list = {}
    for order, path in ipairs(SB.parse_recent_ini(text)) do
        local dir, file = SB.split_path(path)
        list[#list + 1] = {
            path    = path,
            name    = SB.strip_ext(file),
            dir     = dir,
            order   = order,
            missing = not reaper.file_exists(path),
            kind    = 'project',
        }
    end
    return list
end

------------------------------------------------------------------------------
-- Templates
------------------------------------------------------------------------------

function SB.enum_dir(dir, exts, depth, out, base)
    out = out or {}
    base = base or dir
    if depth < 0 then return out end
    local i, file = 0, reaper.EnumerateFiles(dir, 0)
    while file do
        local e = SB.ext(file)
        for _, want in ipairs(exts) do
            if e == want then
                local full = SB.join(dir, file)
                out[#out + 1] = {
                    path  = full,
                    name  = SB.strip_ext(file),
                    dir   = dir,
                    group = dir == base and '' or (dir:match('[^/\\]+$') or ''),
                }
                break
            end
        end
        i = i + 1
        file = reaper.EnumerateFiles(dir, i)
    end
    local j, sub = 0, reaper.EnumerateSubdirectories(dir, 0)
    while sub do
        if sub:sub(1, 1) ~= '.' then
            SB.enum_dir(SB.join(dir, sub), exts, depth - 1, out, base)
        end
        j = j + 1
        sub = reaper.EnumerateSubdirectories(dir, j)
    end
    return out
end

function SB.load_templates(mode)
    local res = reaper.GetResourcePath()
    local list
    if mode == 'track' then
        list = SB.enum_dir(SB.join(res, 'TrackTemplates'),
            { 'rtracktemplate' }, 3)
    else
        list = SB.enum_dir(SB.join(res, 'ProjectTemplates'), { 'rpp' }, 3)
    end
    for _, it in ipairs(list) do
        it.kind    = mode == 'track' and 'tracktemplate' or 'template'
        it.missing = false
    end
    table.sort(list, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name:lower() < b.name:lower()
    end)
    for i, it in ipairs(list) do it.order = i end
    return list
end

------------------------------------------------------------------------------
-- Folder scan (incremental, never blocks the UI)
------------------------------------------------------------------------------

SB.scan = { running = false, found = {}, queue = {}, seen = {}, dirs = 0 }

local SKIP_DIRS = {
    ['.']       = true, ['..'] = true,
    ['peaks']   = true, ['reaper_peaks'] = true,
    ['renders'] = true, ['bounces'] = true,
    ['audio files'] = true, ['video files'] = true,
    ['_to_delete']  = true, ['node_modules'] = true,
}

function SB.scan_start(roots, depth)
    SB.scan.running = true
    SB.scan.found   = {}
    SB.scan.seen    = {}
    SB.scan.dirs    = 0
    SB.scan.queue   = {}
    SB.scan.walked  = {}
    SB.scan.aborted = false
    for _, r in ipairs(roots) do
        -- SB.join never leaves a trailing separator, so roots must not
        -- either, or the loop guard would not recognize the same folder.
        local dir = SB.root_base(r)
        if dir ~= '' then
            SB.scan.queue[#SB.scan.queue + 1] = {
                dir = dir, depth = depth or SB.SCAN_DEPTH,
            }
        end
    end
end

-- Processes up to `budget` directories. Returns true while more work remains.
function SB.scan_step(budget)
    budget = budget or 6
    local q = SB.scan.queue
    local done = 0
    SB.scan.walked = SB.scan.walked or {}
    while done < budget and #q > 0 do
        local job = table.remove(q, 1)
        -- Two roots that overlap, or a Windows junction pointing back up the
        -- tree, would otherwise walk the same folders over and over.
        local walked = SB.path_key(job.dir)
        if SB.scan.walked[walked] then done = done + 1 goto continue end
        SB.scan.walked[walked] = true
        done = done + 1
        SB.scan.dirs = SB.scan.dirs + 1

        local i, file = 0, reaper.EnumerateFiles(job.dir, 0)
        while file do
            if SB.ext(file) == 'rpp' then
                local full = SB.join(job.dir, file)
                local key = SB.path_key(full)
                if not SB.scan.seen[key] then
                    SB.scan.seen[key] = true
                    SB.scan.found[#SB.scan.found + 1] = {
                        path = full,
                        name = SB.strip_ext(file),
                        dir  = job.dir,
                        kind = 'project',
                        missing = false,
                    }
                end
            end
            i = i + 1
            file = reaper.EnumerateFiles(job.dir, i)
        end

        if job.depth > 0 then
            local j, sub = 0, reaper.EnumerateSubdirectories(job.dir, 0)
            while sub do
                if not SKIP_DIRS[sub:lower()] and sub:sub(1, 1) ~= '.' then
                    q[#q + 1] = { dir = SB.join(job.dir, sub), depth = job.depth - 1 }
                end
                j = j + 1
                sub = reaper.EnumerateSubdirectories(job.dir, j)
            end
        end
        ::continue::
    end

    if #q == 0 then
        SB.scan.running = false
        table.sort(SB.scan.found, function(a, b)
            return a.name:lower() < b.name:lower()
        end)
        for k, it in ipairs(SB.scan.found) do it.order = k end
        -- An empty result usually means an unplugged drive or a bad path.
        -- Keep the last good cache instead of wiping it.
        -- A stopped scan only saw part of the disk; keeping the last full
        -- cache is better than replacing it with a fragment.
        if #SB.scan.found > 0 and not SB.scan.aborted then
            SB.cache_save(SB.scan.found)
        end
        return false
    end
    return true
end

-- Which configured folder a project belongs to, and where it sits inside
-- it. Done in one pass so it works the same for a fresh scan and for the
-- cache read back at startup.
function SB.tag_roots(list, roots)
    local bases = {}
    for _, r in ipairs(roots or {}) do
        local base = SB.root_base(r)
        if base ~= '' then
            bases[#bases + 1] = { path = base, key = SB.path_key(base),
                                  name = SB.dir_name(base) }
        end
    end
    for _, item in ipairs(list) do
        item.root, item.rel = nil, nil
        local dir = SB.path_key(item.dir)
        for _, b in ipairs(bases) do
            local prefix = b.key
            if prefix:sub(-1) ~= SEP then prefix = prefix .. SEP end
            if dir == b.key or dir:sub(1, #prefix) == prefix then
                -- Nested roots: the longest match is the real owner.
                if not item.root or #b.path > #item.root then
                    item.root = b.path
                    item.root_name = b.name ~= '' and b.name or b.path
                    item.rel = dir == b.key and ''
                        or item.dir:sub(#prefix + 1)
                end
            end
        end
    end
    return list
end

-- What the FOLDER column shows: the folder you added, plus how far in the
-- project sits. The full path is in the panel on the right.
-- Just the folder you added, never the way down to the file. REAPER puts
-- most projects in a subfolder named after the project, so anything deeper
-- only repeats the name already in the NAME column.
function SB.folder_label(item)
    if not item.root then return SB.short_dir(item.dir, 2) end
    return item.root_name or SB.dir_name(item.root)
end

function SB.cache_path()
    local dir = SB.join(reaper.GetResourcePath(), 'Scripts', 'Reapertips', 'Project Launcher')
    return dir, SB.join(dir, 'folder-cache.txt')
end

function SB.cache_save(list)
    local dir, file = SB.cache_path()
    reaper.RecursiveCreateDirectory(dir, 0)
    local f = io.open(file, 'wb')
    if not f then return end
    for _, it in ipairs(list) do f:write(it.path, '\n') end
    f:close()
    set_ext('cache_stamp', tostring(os.time()))
end

function SB.cache_load()
    local _, file = SB.cache_path()
    local text = SB.read_file(file)
    if not text then return {} end
    local list = {}
    for path in text:gmatch('[^\r\n]+') do
        local dir, name = SB.split_path(path)
        list[#list + 1] = {
            path = path, name = SB.strip_ext(name), dir = dir,
            kind = 'project', missing = not reaper.file_exists(path),
            order = #list + 1,
        }
    end
    return list
end

------------------------------------------------------------------------------
-- .rpp metadata - everything here is read from the file, never typed by hand
------------------------------------------------------------------------------

-- A template with more tracks than this is not something anyone reads off a
-- side panel; the count still shows the real number.
SB.MAX_NAMES = 60

SB.meta_cache = {}

function SB.parse_rpp(path, max_lines)
    max_lines = max_lines or 400000
    -- 'rb': in text mode MSVC treats 0x1A as end of file, so a project with
    -- that byte in a notes block would parse as half a project on Windows.
    local f = io.open(path, 'rb')
    if not f then return nil end

    local meta = { tracks = 0, items = 0, length = 0, names = {} }
    local in_item, pos, len = false, nil, nil
    local want_name = false
    local n = 0

    for line in f:lines() do
        n = n + 1
        if n == 1 then
            -- Not a REAPER file (or binary): stop before reading megabytes.
            -- Some editors add a UTF-8 BOM when a project is round-tripped.
            line = line:gsub('^\239\187\191', '')
            if #line > 4096 or not line:match('^%s*<[A-Z]') then
                f:close()
                return nil
            end
            meta.created = tonumber(line:match('^<REAPER_PROJECT%s+%S+%s+"[^"]*"%s+(%d+)'))
            meta.version = line:match('^<REAPER_PROJECT%s+%S+%s+"([^"]*)"')
        end

        if not meta.tempo then
            local t, num, den = line:match('^%s*TEMPO%s+([%d%.]+)%s+(%d+)%s+(%d+)')
            if t then
                meta.tempo = tonumber(t)
                meta.num, meta.den = tonumber(num), tonumber(den)
            end
        end
        if not meta.srate then
            local sr = line:match('^%s*SAMPLERATE%s+(%d+)')
            if sr then meta.srate = tonumber(sr) end
        end
        if line:match('^%s*<TRACK') then
            meta.tracks = meta.tracks + 1
            -- The first NAME after <TRACK is the track's own; every later
            -- one belongs to an FX or a send inside it.
            -- Past the cap, stop looking: writing into the last slot
            -- would put the final track's name on the 60th row.
            want_name = #meta.names < SB.MAX_NAMES
            if want_name then meta.names[#meta.names + 1] = '' end
        elseif want_name and line:match('^%s*NAME%s') then
            want_name = false
            local name = line:match('^%s*NAME%s+"([^"]*)"')
                or line:match('^%s*NAME%s+"(.*)$')   -- quote never closed
                or line:match('^%s*NAME%s+(%S+)')
            if name and #meta.names > 0 then
                meta.names[#meta.names] = name
            end
        elseif line:match('^%s*<ITEM') then
            want_name = false
            meta.items = meta.items + 1
            in_item, pos, len = true, nil, nil
        elseif in_item then
            -- Stop at the first nested block: <SOURCE carries its own LENGTH.
            if line:match('^%s*<') then
                in_item = false
            else
                if not pos then
                    pos = tonumber(line:match('^%s*POSITION%s+([%d%.%-]+)'))
                end
                if not len then
                    len = tonumber(line:match('^%s*LENGTH%s+([%d%.%-]+)'))
                end
                if pos and len then
                    if pos + len > meta.length then meta.length = pos + len end
                    in_item = false
                end
            end
        end

        if n >= max_lines then
            meta.truncated = true
            break
        end
    end
    f:close()

    meta.size = SB.file_size(path)
    return meta
end

SB.meta_count = 0

-- Tempo lives near the top of the file, so a bounded read is enough.
function SB.rpp_tempo(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local tempo, n = nil, 0
    -- A share that disappears mid-read raises out of f:lines(); this is
    -- called per visible row, so it has to fail quietly.
    pcall(function()
        for line in f:lines() do
            n = n + 1
            local t = line:match('^%s*TEMPO%s+([%d%.]+)')
            if t then tempo = tonumber(t) break end
            if n > 400 or line:match('^%s*<ITEM') then break end
        end
    end)
    f:close()
    return tempo
end

-- Fills in (and caches on the item) whatever a column needs to show or sort.
function SB.value_of(item, col)
    if col == 0 then return SB.fav_set[item.path] and 1 or 0 end
    if col == 1 then return item.order or 0 end
    if col == 2 then return item.name:lower() end
    if col == 3 then return item.dir:lower() end
    if col == 4 then
        if item.when == nil then item.when = SB.file_mtime(item.path) or false end
        return item.when or 0
    end
    if col == 5 then
        if item.size == nil then item.size = SB.file_size(item.path) or false end
        return item.size or 0
    end
    if col == 6 then
        if item.bpm == nil then item.bpm = SB.rpp_tempo(item.path) or false end
        return item.bpm or 0
    end
    return 0
end

-- Columns 4, 5 and 6 have to open every file to sort. Past this many
-- entries that is a visible stall, so those sorts are refused instead.
SB.SORT_IO_LIMIT = 2000

function SB.sort_list(list, col, descending)
    if col >= 4 and #list > SB.SORT_IO_LIMIT then return false end
    -- Read every value first: a comparator with side effects can trip
    -- table.sort into "invalid order function".
    for _, item in ipairs(list) do SB.value_of(item, col) end
    table.sort(list, function(a, b)
        local va, vb = SB.value_of(a, col), SB.value_of(b, col)
        if va == vb then return a.name:lower() < b.name:lower() end
        if descending then return va > vb end
        return va < vb
    end)
    return true
end

function SB.meta_for(path)
    local cached = SB.meta_cache[path]
    if cached ~= nil then return cached end
    if SB.meta_count > 500 then
        SB.meta_cache, SB.meta_count = {}, 0
    end
    SB.meta_count = SB.meta_count + 1
    if not reaper.file_exists(path) then
        SB.meta_cache[path] = false
        return false
    end
    local ok, meta = pcall(SB.parse_rpp, path)
    SB.meta_cache[path] = (ok and meta) or false
    return SB.meta_cache[path]
end

------------------------------------------------------------------------------
-- Filtering
------------------------------------------------------------------------------

-- Every space separated word must appear in the name or the folder.
function SB.matches(item, words)
    if #words == 0 then return true end
    local hay = (item.name .. ' ' .. item.dir):lower()
    for _, w in ipairs(words) do
        if not hay:find(w, 1, true) then return false end
    end
    return true
end

function SB.split_words(query)
    local words = {}
    for w in tostring(query or ''):lower():gmatch('%S+') do
        words[#words + 1] = w
    end
    return words
end

function SB.filter(list, query, favs_only, hide_missing, fav_set)
    local words, out = SB.split_words(query), {}
    for _, item in ipairs(list) do
        local ok = true
        if favs_only and not fav_set[item.path] then ok = false end
        if ok and hide_missing and item.missing then ok = false end
        if ok and not SB.matches(item, words) then ok = false end
        if ok then out[#out + 1] = item end
    end
    return out
end

------------------------------------------------------------------------------
-- Opening things
------------------------------------------------------------------------------

local CMD_NEW_TAB_NO_TEMPLATE = 41929 -- New project tab (ignore default template)
local CMD_SAVE_NEW_VERSION    = 41895 -- Save new version of project
local CMD_NEW_PROJECT         = 40023
local CMD_OPEN_PROJECT        = 40025

function SB.open(item, mode)
    if not item then return end
    if item.missing then
        reaper.MB('This file is not there any more:\n\n' .. item.path,
            'Project Launcher', 0)
        return
    end

    if item.kind == 'tracktemplate' then
        reaper.Main_openProject(item.path)
        return true
    end

    if mode == 'tab' or mode == 'copy' then
        reaper.Main_OnCommand(CMD_NEW_TAB_NO_TEMPLATE, 0)
    end

    if item.kind == 'template' and mode ~= 'edit' then
        reaper.Main_openProject('template:' .. item.path)
    else
        reaper.Main_openProject(item.path)
    end

    if mode == 'copy' then
        reaper.Main_OnCommand(CMD_SAVE_NEW_VERSION, 0)
    end
    if item.kind == 'template' then SB.mark_used(item.path) end
    return true
end

function SB.reveal(path)
    if not path or path == '' then return end
    if reaper.CF_LocateInExplorer then
        reaper.CF_LocateInExplorer(path)
        return
    end
    -- No SWS: shell out, but refuse anything that could break out of the
    -- quotes instead of running a mangled command. Backslash is a path
    -- separator on Windows, so it can only be rejected on the other two.
    local unsafe = IS_WIN and '["%%\n^&|<>]' or '["\'`$\\\n]'
    if path:find(unsafe) then
        reaper.MB('This path needs the SWS extension to be shown in the ' ..
            'finder:\n\n' .. path, 'Project Launcher', 0)
        return
    end
    if IS_MAC then
        os.execute(('open -R "%s"'):format(path))
    elseif IS_WIN then
        os.execute(('explorer /select,"%s"'):format(path))
    else
        os.execute(('xdg-open "%s"'):format((SB.split_path(path))))
    end
end

------------------------------------------------------------------------------
-- Startup hook (adapted from Gridbox by FeedTheCat, MIT)
------------------------------------------------------------------------------

local _, script_path, section, cmd_id = reaper.get_action_context()

local HOOK_MARK = '-- Start script: Project Launcher'
local HOOK_MARK_OLD = '-- Start script: StartBox'
local HOOK_TAIL = 'NamedCommandLookup(launcher_cmd_name)'
local HOOK_TAIL_OLD = 'NamedCommandLookup(startbox_cmd_name)'

local function startup_command_id(no_register)
    local id = cmd_id
    if section == 0 then
        local name = reaper.ReverseNamedCommandLookup(id)
        if not name or name == '' then return 0 end
        set_ext('hook_cmd_name', '_' .. name)
    else
        local stored = get_ext('hook_cmd_name', '')
        id = stored ~= '' and reaper.NamedCommandLookup(stored) or 0
        if id == 0 and no_register then return 0 end
        if id == 0 then
            id = reaper.AddRemoveReaScript(true, 0, script_path, true)
            if id == 0 then return 0 end
            local name = reaper.ReverseNamedCommandLookup(id)
            if not name or name == '' then return 0 end
            set_ext('hook_cmd_name', '_' .. name)
        end
    end
    return id
end

local function startup_path()
    return SB.join(reaper.GetResourcePath(), 'Scripts', '__startup.lua')
end

local function startup_error(detail)
    reaper.MB('Project Launcher could not update __startup.lua.\n\n' ..
        tostring(detail or 'Check the file permissions and try again.'),
        SB.NAME, 0)
    return false
end

local function hook_block(name)
    return HOOK_MARK .. '\n' ..
        ("reaper.SetExtState('%s', 'startup', '1', false)\n"):format(SB.EXTNAME) ..
        ("local launcher_cmd_name = '_%s'\n"):format(name) ..
        'reaper.Main_OnCommand(reaper.' .. HOOK_TAIL .. ', 0)\n'
end

-- Finds our own block and nothing else: from the marker comment to the end
-- of the line that runs the action. Other scripts in __startup.lua are never
-- touched, because their run line does not mention launcher_cmd_name.
local function find_one(content, mark, tail)
    local from = content:find(mark, 1, true)
    if not from then return nil end
    local run = content:find(tail, from, true)
    if not run then return nil end
    local eol = content:find('\n', run, true)
    return from, eol or #content
end

-- Either marker: a hook written before the rename still has to be found, or
-- enabling startup would install a second one beside it.
local function find_hook(content)
    local from, to = find_one(content, HOOK_MARK, HOOK_TAIL)
    if from then return from, to end
    return find_one(content, HOOK_MARK_OLD, HOOK_TAIL_OLD)
end

function SB.startup_enabled()
    local path = startup_path()
    if not reaper.file_exists(path) then return false end
    local content = SB.read_file(path)
    if not content then return false end
    local from, to = find_hook(content)
    if not from then return false end
    local block = content:sub(from, to)
    -- Enabled when the line that runs the action is not commented out.
    if not block:match('\n%s*reaper%.Main_OnCommand') then return false end
    -- ...and when the action it names still exists. Reinstalling from a
    -- different folder changes the command ID, and the hook would quietly
    -- stop working while this box stayed ticked.
    local name = block:match("launcher_cmd_name%s*=%s*'([^']+)'")
        or block:match("startbox_cmd_name%s*=%s*'([^']+)'")
    if name and reaper.NamedCommandLookup(name) == 0 then return false end
    return true
end

function SB.startup_set(enabled)
    local id = startup_command_id()
    if id == 0 then return false end
    local name = reaper.ReverseNamedCommandLookup(id)
    if not name or name == '' then return false end

    local path = startup_path()
    local content = ''
    if reaper.file_exists(path) then
        content = SB.read_file(path)
        -- The file is there but will not open (locked, no permission). It
        -- holds other scripts' hooks, so the only safe move is to stop.
        if not content then return startup_error('The file could not be read.') end
    end

    -- A file upgraded from StartBox can hold both blocks. Cut the old one
    -- out first, or switching startup off would leave it firing.
    if content:find(HOOK_MARK, 1, true) then
        local of, ot = find_one(content, HOOK_MARK_OLD, HOOK_TAIL_OLD)
        if of then content = content:sub(1, of - 1) .. content:sub(ot + 1) end
    end
    local from, to = find_hook(content)
    local block

    if enabled then
        -- Always rewritten, so a stale command ID is repaired on the way.
        block = hook_block(name)
    elseif from then
        block = content:sub(from, to):gsub('\n(%s*)reaper%.Main_OnCommand',
            '\n%1-- reaper.Main_OnCommand', 1)
    end

    if from then
        content = content:sub(1, from - 1) .. block .. content:sub(to + 1)
    elseif enabled then
        content = block .. '\n' .. content
    else
        return true -- nothing installed, nothing to switch off
    end

    -- __startup.lua usually holds other scripts' hooks too. Writing in
    -- place would lose all of them if the write failed halfway, so the new
    -- text lands beside it and only replaces the file once it is complete.
    local tmp = path .. '.launcher-tmp'
    local out = io.open(tmp, 'wb')
    if not out then return startup_error('The temporary file could not be created.') end
    -- A full disk shows up at close(), not at write().
    local written = out:write(content)
    local closed = out:close()
    if not (written and closed) then
        os.remove(tmp)
        return startup_error('The temporary file could not be written.')
    end

    if not os.rename(tmp, path) then
        -- Windows refuses to rename onto a file that already exists. Move
        -- the old one aside rather than deleting it, so a second failure
        -- still leaves the user with their original file.
        local bak = path .. '.launcher-bak'
        os.remove(bak)
        os.rename(path, bak)
        if not os.rename(tmp, path) then
            os.rename(bak, path)
            os.remove(tmp)
            return startup_error('The new file could not replace the old one.')
        end
        os.remove(bak)
    end
    return true
end

-- REAPER's own startup prompt fights this window. 20 = "Prompt".
function SB.startup_prompt_conflict()
    if not reaper.SNM_GetIntConfigVar then return false end
    return reaper.SNM_GetIntConfigVar('loadlastproj', -1) == 20
end

function SB.fix_startup_prompt()
    if reaper.SNM_SetIntConfigVar then
        reaper.SNM_SetIntConfigVar('loadlastproj', 19) -- New project
    end
end

------------------------------------------------------------------------------
-- Colors: gray everywhere, one accent that follows the theme
------------------------------------------------------------------------------

local function rgba(hex, alpha)
    return ((hex & 0xFFFFFF) << 8) | (alpha or 0xFF)
end

function SB.theme_key()
    local path = reaper.GetLastColorThemeFile() or ''
    local name = path:match('[^/\\]+$') or 'default'
    return (name:gsub('%.[Rr]eaper[Tt]heme[Zz]?[Ii]?[Pp]?$', ''))
end

-- Ext-state key for a per-theme accent override, sanitized so any theme
-- file name turns into a safe key name.
function SB.accent_ext_key(key)
    return 'accent.' .. tostring(key or ''):gsub('[^%w]', '_')
end

function SB.get_accent_override(key)
    local v = get_ext(SB.accent_ext_key(key), '')
    if v:match('^%x%x%x%x%x%x$') then return tonumber(v, 16) end
    return nil
end

function SB.set_accent_override(key, rgb)
    set_ext(SB.accent_ext_key(key), ('%06X'):format(rgb & 0xFFFFFF))
end

function SB.clear_accent_override(key)
    reaper.DeleteExtState(SB.EXTNAME, SB.accent_ext_key(key), true)
end

-- Returns the accent color and where it came from: 'custom' (a per-theme
-- override), 'reapertips' or 'default' (the built-in themes), 'theme' (the
-- razor edit outline color), or 'fallback' (the theme color was too dark
-- or unavailable).
function SB.accent_for_theme(key)
    local override = SB.get_accent_override(key)
    if override then return override, 'custom' end
    local lower = tostring(key or ''):lower()
    if lower:find('reapertips', 1, true) then return 0x46B9FE, 'reapertips' end
    if lower:find('default', 1, true) then return 0x10BD9A, 'default' end
    local native = reaper.GetThemeColor and
        reaper.GetThemeColor('areasel_outline', 0) or -1
    if native and native >= 0 then
        local r, g, b = reaper.ColorFromNative(native)
        if r + g + b > 60 then return (r << 16) | (g << 8) | b, 'theme' end
    end
    return 0x10BD9A, 'fallback'
end

-- Interface scale and text size. Everything with a pixel value goes
-- through PX(); every font size goes through FS().
-- The list reads better one step up from the chrome, so that is where it
-- starts. Both defaults live here: the reset button returns to them.
SB.UI_DEFAULT = { scale = 1.0, font = 1.1 }
SB.ui = { scale = SB.UI_DEFAULT.scale, font = SB.UI_DEFAULT.font }
local BASE_FONT = 13

local function PX(n)
    return math.max(1, math.floor(n * SB.ui.scale + 0.5))
end

local FAV_COL_W, CELL_PAD_X = 18, 4

-- Chrome text: tabs, rail, detail, status. Follows the interface size only.
local function FS(n)
    return math.max(7, n * SB.ui.scale)
end

-- List text: also follows the A- / A+ buttons, like ReaLauncher's
-- listboxFontSize. Nothing else in the window changes with it.
local function LFS(n)
    return math.max(7, n * SB.ui.scale * SB.ui.font)
end

-- Boxes that have to hold list text: the fixed table columns. They follow
-- both sliders, or bigger text gets clipped by a column that did not grow.
local function LPX(n)
    return math.max(1, math.floor(n * SB.ui.scale * SB.ui.font + 0.5))
end

function SB.set_ui(scale, font)
    local was = SB.ui.scale
    SB.ui.scale = math.max(0.8, math.min(2.0, scale))
    SB.ui.font  = math.max(0.8, math.min(1.6, font))
    -- Grow (or shrink) the window by the same factor, otherwise 200% just
    -- squeezes the same layout into the same box.
    if SB.ui.scale ~= was and was > 0 then SB.ui.resize = SB.ui.scale / was end
    -- Stored as whole percents: the decimal point is not the same
    -- character in every locale and tonumber would give up on "1,20".
    set_ext('scale', tostring(math.floor(SB.ui.scale * 100 + 0.5)))
    set_ext('font', tostring(math.floor(SB.ui.font * 100 + 0.5)))
    SB.style_dirty = true
end

-- ReaImGui has no combined Cmd/Ctrl modifier: pick the right one per OS.
local MOD_CMD = IS_MAC and ImGui.Mod_Super or ImGui.Mod_Ctrl

local C = {}

function SB.build_palette()
    SB.style_dirty = true
    SB.theme = SB.theme_key()
    local a, source = SB.accent_for_theme(SB.theme)
    SB.accent_rgb = a
    SB.accent_source = source
    -- Values below are the approved mockup, one for one.
    C.accent      = rgba(a)
    C.accent_dim  = rgba(a, 0x29)   -- selected row / primary button, 16%
    C.accent_soft = rgba(a, 0x3D)
    C.text        = rgba(0xD2D4DA)
    C.text_bright = rgba(0xEFF1F4)
    C.text_dim    = rgba(0x9A9CA4)
    C.text_faint  = rgba(0x7C7E86)
    C.win         = rgba(0x232326)   -- one surface: window, rail, list, detail
    C.child       = rgba(0x232326)
    C.line        = rgba(0x33333A)
    C.frame       = rgba(0xFFFFFF, 0x0D)   -- search field, 5% white
    C.frame_hover = rgba(0xFFFFFF, 0x14)
    C.button      = rgba(0xFFFFFF, 0x0F)   -- 6% white
    C.button_hov  = rgba(0xFFFFFF, 0x18)
    C.tab_on      = rgba(0xFFFFFF, 0x12)   -- 7% white
    C.ghost       = rgba(0xFFFFFF, 0x2E)   -- only while dragging a column edge
    C.dim_bg      = rgba(0x000000, 0x88)
    C.row_hover   = rgba(0xFFFFFF, 0x0C)
    C.clear       = rgba(0x000000, 0x00)
    C.warn        = rgba(0xFF8A8A)
end

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

local S = {
    query      = '',
    view       = 'recent',
    sel        = 1,
    favs_only  = false,
    froot      = nil,     -- folders rail: which configured folder, nil = all
    tmode      = 'all',   -- templates rail: all | fav | recent | section
    tsec       = nil,     -- ...and which section, when tmode is 'section'
    items      = {},      -- current source list
    shown      = {},      -- after filtering
    focus_search = true,
    scroll_to  = false,
    quit       = false,
    status     = '',
    show_settings = false,
    settings_tab  = 'general',
    dirty      = true,
    new_root   = '',
    last_key_at = 0,
}

-- Exposed so the tests can look at the live state.
function SB.state() return S end

local function set_status(msg)
    S.status = msg or ''
    S.status_at = reaper.time_precise()
end

function SB.reload(view)
    view = view or S.view
    S.view = view
    if view == 'recent' then
        S.items = SB.load_recents()
    elseif view == 'templates' then
        S.items = SB.load_templates('project')
    else
        S.items = SB.tag_roots(SB.cache_load(), SB.cfg.roots)
    end
    S.dirty = true
end

-- The templates rail narrows what the list already filtered. Search always
-- searches everything, so typing gets you out of a section you forgot you
-- were in.
function SB.section_filter(list, mode, want, query, sorted)
    if mode == 'all' or query ~= '' then return list end
    local out = {}
    for _, item in ipairs(list) do
        local keep
        if mode == 'fav' then
            keep = SB.fav_set[item.path] and true or false
        elseif mode == 'recent' then
            keep = SB.used_at(item.path) > 0
        else
            keep = SB.section_of(item) == want
        end
        if keep then out[#out + 1] = item end
    end
    -- Recency is the point of this row, but a column the user clicked on
    -- is a more explicit request than the row they clicked before it.
    if mode == 'recent' and not sorted then
        table.sort(out, function(a, b)
            return SB.used_at(a.path) > SB.used_at(b.path)
        end)
    end
    return out
end

function SB.refilter()
    S.shown = SB.filter(S.items, S.query, S.favs_only,
        SB.cfg.hide_missing and S.view == 'recent', SB.fav_set)
    if S.view == 'folders' and S.froot and S.query == '' then
        local out = {}
        for _, item in ipairs(S.shown) do
            if item.root == S.froot then out[#out + 1] = item end
        end
        S.shown = out
    end
    if S.view == 'templates' then
        if S.tmode == 'section' and not SB.section_index(S.tsec) then
            local live = false
            for _, sec in ipairs(SB.section_list(S.items)) do
                if sec.name == S.tsec then live = true break end
            end
            if not live then S.tmode, S.tsec = 'all', nil end
        end
        S.shown = SB.section_filter(S.shown, S.tmode, S.tsec, S.query,
            S.sort_col ~= nil)
    end
    if S.sort_col then SB.sort_list(S.shown, S.sort_col, S.sort_dir) end
    SB.restore_sel()
    if S.sel > #S.shown then S.sel = #S.shown end
    if S.sel < 1 then S.sel = 1 end
    S.dirty = false
end

local function selected()
    return S.shown[S.sel]
end

local function set_sel(index)
    S.sel = index
    S.sel_at = reaper.time_precise()
    local item = S.shown[index]
    S.sel_path = item and item.path or nil
end

-- After a filter or a sort the same project should stay selected.
function SB.restore_sel()
    if not S.sel_path then return end
    for i, item in ipairs(S.shown) do
        if item.path == S.sel_path then
            S.sel = i
            return
        end
    end
end

local function move_sel(delta)
    if #S.shown == 0 then return end
    set_sel(math.max(1, math.min(#S.shown, S.sel + delta)))
    S.scroll_to = true
end

local function do_open(mode)
    local item = selected()
    if not item then return end
    if SB.open(item, mode) and not SB.cfg.keep_open then
        S.quit = true
    end
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------

local ctx = ImGui.CreateContext(SB.NAME)

-- Hovering a control writes a line for the status bar rather than opening a
-- tooltip under the pointer. The bar is already there, it never covers the
-- list, and a tooltip inside the list resets ImGui's pushed font size.
local function hint(text)
    if ImGui.IsItemHovered(ctx) then S.hint = text end
end


local STYLE_C, STYLE_V

-- A real drop shadow needs a transparent margin around the window, and that
-- margin swallows the resize corner: the grip either floats out in the empty
-- space or has to be hidden, and the seam along the bottom edge never quite
-- goes away. Two rounds of that was enough. The window paints its own
-- background again, and the separation from the arrange view comes from a
-- dark outline with one hairline of light inside the top edge.
local function draw_surface()
    local dl = ImGui.GetWindowDrawList(ctx)
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    local r = PX(12)
    ImGui.DrawList_AddLine(dl, wx + r, wy + 0.5, wx + ww - r, wy + 0.5,
        rgba(0xFFFFFF, 0x12), 1)
end

local function build_style()
    STYLE_C = {
        { ImGui.Col_WindowBg,        C.win },
        { ImGui.Col_ChildBg,         C.child },
        { ImGui.Col_PopupBg,         C.child },
        { ImGui.Col_Text,            C.text },
        { ImGui.Col_TextDisabled,    C.text_dim },
        { ImGui.Col_Border,          rgba(0x000000, 0x8C) },
        { ImGui.Col_FrameBg,         C.frame },
        { ImGui.Col_FrameBgHovered,  C.frame_hover },
        { ImGui.Col_FrameBgActive,   C.frame_hover },
        { ImGui.Col_Button,          C.button },
        { ImGui.Col_ButtonHovered,   C.button_hov },
        { ImGui.Col_ButtonActive,    C.accent_soft },
        { ImGui.Col_Header,          C.accent_dim },
        { ImGui.Col_HeaderHovered,   C.row_hover },
        { ImGui.Col_HeaderActive,    C.accent_soft },
        { ImGui.Col_Separator,       C.line },
        -- No rules between columns: the ghost line only shows up while the
        -- user is actually dragging a column edge.
        { ImGui.Col_SeparatorHovered,  C.ghost },
        { ImGui.Col_SeparatorActive,   C.ghost },
        { ImGui.Col_TableRowBgAlt,     C.clear },
        { ImGui.Col_TableHeaderBg,     C.clear },
        { ImGui.Col_TableBorderLight,  C.clear },
        { ImGui.Col_TableBorderStrong, C.clear },
        { ImGui.Col_ModalWindowDimBg,  C.dim_bg },
        { ImGui.Col_CheckMark,       C.accent },
        { ImGui.Col_TitleBgActive,   C.child },
        { ImGui.Col_ScrollbarGrab,   rgba(0xFFFFFF, 0x1A) },
        { ImGui.Col_ScrollbarGrabHovered, rgba(0xFFFFFF, 0x2A) },
        { ImGui.Col_ScrollbarBg,     C.clear },
        -- Back on the real corner of the window, where it can be grabbed.
        { ImGui.Col_ResizeGrip,        rgba(0xFFFFFF, 0x16) },
        { ImGui.Col_ResizeGripHovered, rgba(0xFFFFFF, 0x2E) },
        { ImGui.Col_ResizeGripActive,  C.accent_soft },
    }
    STYLE_V = {
        { ImGui.StyleVar_WindowPadding,   PX(9), PX(9) },
        { ImGui.StyleVar_FramePadding,   PX(11), PX(6) },
        { ImGui.StyleVar_ItemSpacing,     PX(7), PX(7) },
        { ImGui.StyleVar_CellPadding, PX(CELL_PAD_X), PX(6) },
        { ImGui.StyleVar_WindowRounding, PX(12) },
        -- The outline is what lifts the window off the arrange view.
        { ImGui.StyleVar_WindowBorderSize,    1 },
        { ImGui.StyleVar_ChildRounding,       0 },
        { ImGui.StyleVar_ChildBorderSize,     0 },
        { ImGui.StyleVar_PopupRounding,  PX(10) },
        { ImGui.StyleVar_FrameRounding,   PX(8) },
        { ImGui.StyleVar_GrabRounding,    PX(4) },
        { ImGui.StyleVar_ScrollbarRounding, PX(5) },
        { ImGui.StyleVar_ScrollbarSize,   PX(9) },
    }
end

local function push_style()
    if not STYLE_C or SB.style_dirty then
        SB.style_dirty = false
        build_style()
    end
    for _, pair in ipairs(STYLE_C) do
        ImGui.PushStyleColor(ctx, pair[1], pair[2])
    end
    for _, item in ipairs(STYLE_V) do
        if item[3] then
            ImGui.PushStyleVar(ctx, item[1], item[2], item[3])
        else
            ImGui.PushStyleVar(ctx, item[1], item[2])
        end
    end
end

local function pop_style()
    ImGui.PopStyleVar(ctx, #STYLE_V)
    ImGui.PopStyleColor(ctx, #STYLE_C)
end

-- Small vector icons, drawn by hand so no font glyph can go missing.

-- Every zone is a child window with its own padding and no scrollbar of
-- its own: the list's table is the only thing allowed to scroll.
-- A Lua error thrown while a child window is open never reaches EndChild,
-- and ReaImGui then reports the imbalance ("Missing EndChild()") instead of
-- the mistake that caused it. Catching it here keeps the window stack sane
-- and prints what actually happened, once.
function SB.guard(what, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok and not SB.reported then
        SB.reported = true
        reaper.ShowConsoleMsg(('Project Launcher %s hit an error in %s.\nPlease send '
            .. 'this to reapertips.com so it can be fixed.\n\n%s\n\n')
            :format(SB.VERSION, what, tostring(err)))
        reaper.ShowConsoleMsg(('state: view=%s scale=%.2f font=%.2f ' ..
            'items=%d shown=%d sel=%s js=%s sws=%s os=%s\n')
            :format(tostring(S.view), SB.ui.scale, SB.ui.font,
                #S.items, #S.shown, tostring(S.sel), tostring(HAS_JS),
                tostring(HAS_SWS), tostring(reaper.GetOS())))
        -- Whatever the body pushed and did not pop is still on ImGui's
        -- stacks, so carrying on would only pile unrelated errors on top
        -- of the real one. Close after this frame instead.
        S.quit = true
    end
    return ok
end

local function panel(id, w, h, pad_x, pad_y, body)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, pad_x, pad_y)
    -- A child window with no border throws its padding away unless it is
    -- asked for by name. That is why every label sat on the edge.
    local open = ImGui.BeginChild(ctx, id, w, h,
        ImGui.ChildFlags_AlwaysUseWindowPadding,
        ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleVar(ctx)
    -- EndChild is NOT optional. BeginChild returns false as soon as the
    -- child is entirely clipped - which happens for real, on a small or
    -- partly off-screen window - and skipping EndChild there leaves the
    -- context broken: "Missing EndChild()", after which every ReaImGui
    -- call starts handing back nil. Only the body is skipped.
    -- (ReaImGui_Demo.lua still shows the old conditional pairing. The
    -- runtime is the authority, and the runtime wants them balanced.)
    if open then SB.guard(id, body) end
    ImGui.EndChild(ctx)
end

-- A flat toggle that matches the tabs, instead of ImGui's big checkbox.
-- Popup menus inherit the window's tight spacing, which reads as cramped in
-- a short list of verbs. These are the only numbers a menu needs.
local function push_menu_style()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, PX(8), PX(8))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(8), PX(6))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, PX(8), PX(4))
end

local function pop_menu_style()
    ImGui.PopStyleVar(ctx, 3)
end

local function pill_toggle(label, on, width)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, on and C.tab_on or C.clear)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
        on and C.tab_on or C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, on and C.accent or C.text_dim)
    local clicked = ImGui.Button(ctx, label, width or 0)
    ImGui.PopStyleColor(ctx, 4)
    return clicked
end
local RAIL_W, DETAIL_W, BODY_GAP = 150, 196, 8
local SHORTCUT = IS_MAC and 'Cmd+' or 'Ctrl+'

local function draw_star(dl, cx, cy, r, col)
    ImGui.DrawList_PathClear(dl)
    for _, arc in ipairs(SB.star_arcs(cx, cy, r, r * 0.11)) do
        ImGui.DrawList_PathArcTo(dl, arc[1], arc[2], arc[3], arc[4], arc[5])
    end
    ImGui.DrawList_PathFillConcave(dl, col)
end

local function draw_cross(dl, cx, cy, r, col)
    ImGui.DrawList_AddLine(dl, cx - r, cy - r, cx + r, cy + r, col, PX(1.5))
    ImGui.DrawList_AddLine(dl, cx - r, cy + r, cx + r, cy - r, col, PX(1.5))
end

-- A button whose face is drawn, not typed. Returns true when clicked.
local function icon_button(id, size, painter)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, id, size, size)
    local hot = ImGui.IsItemHovered(ctx)
    painter(ImGui.GetWindowDrawList(ctx), x + size / 2, y + size / 2, hot)
    return clicked
end

local function tab_button(label, view)
    local active = S.view == view
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, active and C.tab_on or C.clear)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
        active and C.tab_on or C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text,
        active and C.text_bright or C.text_dim)
    local clicked = ImGui.Button(ctx, label)
    ImGui.PopStyleColor(ctx, 4)

    if clicked and not active then
        -- The name field only exists in the templates rail; leaving it open
        -- would keep the keyboard to itself with nowhere to type.
        S.naming, S.name_draft, S.file_after = nil, nil, nil
        S.adding_root, S.new_root = nil, ''
        SB.reload(view)
        S.sel = 1
        S.sel_path = nil
        set_ext('view', view)
    end
    ImGui.SameLine(ctx)
end

local function draw_header(content_w)
    -- SameLine measures from the window edge, not from the content region,
    -- so the start of the line has to be added back or the icon sits one
    -- window padding short of the edge - a gap that doubles with the size.
    local line_x = ImGui.GetCursorPosX(ctx)
    ImGui.PushFont(ctx, nil, FS(10))
    -- The wordmark is the name letter-spaced; keeping it derived from
    -- SB.NAME means there is one place to change it.
    ImGui.TextColored(ctx, C.text_faint,
        (SB.NAME:upper():gsub('(.)', '%1 '):gsub(' $', '')))
    ImGui.PopFont(ctx)

    ImGui.SameLine(ctx, line_x + content_w - PX(20))
    if icon_button('##close', PX(20), function(dl, cx, cy, hot)
                draw_cross(dl, cx, cy, PX(20) * 0.24,
                    hot and C.text_bright or C.text_faint)
            end) then
        S.quit = true
    end
    hint('Closes the window. Esc')
end

local function draw_top_bar()
    tab_button('Recent', 'recent')
    tab_button('Templates', 'templates')
    tab_button('Folders', 'folders')

    ImGui.SameLine(ctx, 0, PX(12))
    local avail = ImGui.GetContentRegionAvail(ctx)

    -- Leave exactly enough room for the Settings button so it lands on the
    -- right edge instead of stopping short of it.
    local pad_x   = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
    local spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local tail    = ImGui.CalcTextSize(ctx, 'Settings') + pad_x * 2 + spacing
    ImGui.SetNextItemWidth(ctx, math.max(PX(40), avail - tail))

    if S.focus_search then
        ImGui.SetKeyboardFocusHere(ctx)
        S.focus_search = false
    end
    local what = S.view == 'templates' and 'templates'
        or S.view == 'folders' and 'projects' or 'recent projects'
    local changed, query = ImGui.InputTextWithHint(ctx, '##search',
        ('Type to search %d %s...'):format(#S.shown, what), S.query)
    if changed then
        S.query = query
        S.sel = 1
        S.sel_path = nil  -- a new search starts from the best match
        S.dirty = true
    end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Settings') then
        S.show_settings = true
    end
    hint(SHORTCUT .. ', opens settings')
end

-- One row of the templates rail: a name on the left, its count on the
-- right, and a menu dot in place of the count while the pointer is on it.
-- Every heading in the rail sits the same distance from what follows it.
-- `plus` draws an add button on the heading's right edge, on the same axis
-- as the counts below.
local function rail_head(label, plus, tip)
    local hit = false
    ImGui.TextColored(ctx, C.text_faint, label)
    if plus then
        local lx = ImGui.GetCursorPosX(ctx)
        local lw = ImGui.GetContentRegionAvail(ctx)
        ImGui.SameLine(ctx, lx + lw - PX(7) - PX(11))
        hit = icon_button(plus, PX(11), function(dl, cx, cy, hot)
            local r, col = PX(4), hot and C.text_bright or C.text_dim
            ImGui.DrawList_AddLine(dl, cx - r, cy, cx + r, cy, col, PX(1))
            ImGui.DrawList_AddLine(dl, cx, cy - r, cx, cy + r, col, PX(1))
        end)
        if tip then hint(tip) end
    end
    ImGui.Dummy(ctx, 1, PX(4))
    return hit
end

-- Returns whether it was clicked, and the path of a template dropped on it.
local function rail_row(id, label, count, active, accepts)
    local w = ImGui.GetContentRegionAvail(ctx)
    local h = ImGui.GetFrameHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, id, w, h)
    local hot = ImGui.IsItemHovered(ctx)
    local dropped, over
    -- Asked before the row is painted, so the highlight follows the pointer
    -- with no frame of lag while something is being dragged over it.
    if accepts and ImGui.BeginDragDropTarget(ctx) then
        over = true
        local took, path = ImGui.AcceptDragDropPayload(ctx, SB.DND)
        if took and path and path ~= '' then dropped = path end
        ImGui.EndDragDropTarget(ctx)
    end
    local dl = ImGui.GetWindowDrawList(ctx)
    if active or hot or over then
        ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h,
            (active or over) and C.accent_dim or C.button, PX(7))
    end
    if over then
        ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.accent, PX(7), 0, PX(1))
    end
    -- Everything below is painted straight into the draw list rather than
    -- submitted as widgets, so the button above stays the last item ImGui
    -- knows about. BeginPopupContextItem needs that: a Text call in between
    -- leaves the last-item id at 0 and it asserts.
    local pad = PX(7)
    local ty = y + (h - ImGui.GetTextLineHeight(ctx)) / 2
    -- Plain ASCII: the default ReaImGui font has no glyph for a bullet and
    -- would draw three empty boxes.
    -- No hover affordance on the count: three dots that do nothing when
    -- clicked are worse than no hint at all. Right click is the way in, and
    -- the status bar says so.
    local tail = count and tostring(count) or nil
    local tail_w = tail and ImGui.CalcTextSize(ctx, tail) or 0
    if tail then
        ImGui.DrawList_AddText(dl, x + w - pad - tail_w, ty,
            active and C.accent or C.text_faint, tail)
    end
    local room = w - pad * 2 - (tail and tail_w + PX(6) or 0)
    ImGui.DrawList_PushClipRect(dl, x + pad, y,
        x + pad + math.max(PX(8), room), y + h, true)
    ImGui.DrawList_AddText(dl, x + pad, ty,
        active and C.accent or C.text, label)
    ImGui.DrawList_PopClipRect(dl)
    return clicked, dropped
end

local function pick(mode, name)
    S.tmode, S.tsec = mode, name
    S.sel, S.sel_path = 1, nil
    S.dirty = true
end

local function section_editor()
    -- Naming a section happens in place, in the rail, where the section
    -- will appear. There is no dialog for this.
    ImGui.SetNextItemWidth(ctx, -1)
    local first = S.name_focus
    if first then
        ImGui.SetKeyboardFocusHere(ctx)
        S.name_focus = false
    end
    local commit, text = ImGui.InputTextWithHint(ctx, '##sectionname',
        'Section name', S.name_draft or '',
        ImGui.InputTextFlags_EnterReturnsTrue)
    S.name_draft = text
    -- Escape and clicking away both close the field. Tying them to the
    -- field's own focus is what stops a stray Enter somewhere else from
    -- committing a half-typed name - and stops the field from being left
    -- open with no way back, which would take the whole keyboard with it.
    local active = ImGui.IsItemActive(ctx)
    local cancel = (active and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape))
        or (not active and not first)
    if commit then
        local name = SB.clean_name(S.name_draft)
        if S.naming == '' then
            -- An existing name is not an error: file the template there.
            if name ~= '' and (SB.section_add(name) or SB.section_index(name)) then
                if S.file_after then SB.file_under(S.file_after, name) end
                pick('section', name)
            end
        elseif SB.section_rename(S.naming, name) then
            if S.tsec == S.naming then S.tsec = name end
        end
        S.dirty = true
    end
    if commit or cancel then
        S.naming, S.name_draft, S.file_after = nil, nil, nil
    end
end

local function draw_template_rail()
    -- The rows are frame-height buttons, so the usual item spacing would
    -- leave the rail looking gappy.
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(7), PX(2))
    rail_head('TEMPLATES')
    local click, drop = rail_row('##t_all', 'All', #S.items,
        S.tmode == 'all', true)
    if click then pick('all') end
    if drop then
        -- Dropping on All takes the template out of whatever section it was
        -- in; a real subfolder shows through again.
        SB.file_under(drop, nil)
        S.dirty = true
    end
    local n_fav = 0
    for _, it in ipairs(S.items) do
        if SB.fav_set[it.path] then n_fav = n_fav + 1 end
    end
    if rail_row('##t_fav', 'Favorites', n_fav, S.tmode == 'fav') then
        pick('fav')
    end
    local n_used = 0
    for _, it in ipairs(S.items) do
        if SB.used_at(it.path) > 0 then n_used = n_used + 1 end
    end
    if rail_row('##t_recent', 'Recently used', n_used, S.tmode == 'recent') then
        pick('recent')
    end

    ImGui.Dummy(ctx, 1, PX(14))
    if rail_head('SECTIONS', '##addsection',
            'New section. Nothing is created on disk') then
        S.naming, S.name_draft, S.name_focus = '', '', true
    end

    local list = SB.section_list(S.items)
    for _, sec in ipairs(list) do
        ImGui.PushID(ctx, sec.name)
        if S.naming == sec.name then
            section_editor()
        else
            local on = S.tmode == 'section' and S.tsec == sec.name
            local hit, got = rail_row('##sec', sec.name, sec.count, on, true)
            if hit then pick('section', sec.name) end
            if got then
                SB.file_under(got, sec.unsorted and SB.UNSORTED or sec.name)
                S.dirty = true
                set_status('Moved to ' .. sec.name)
            end
            if sec.own then
                hint('Right click to rename, reorder or delete')
            elseif sec.unsorted then
                hint('Templates you have not filed anywhere')
            else
                hint('A real subfolder of ProjectTemplates')
            end
            push_menu_style()
            if sec.own and ImGui.BeginPopupContextItem(ctx) then
                if ImGui.MenuItem(ctx, 'Rename') then
                    S.naming, S.name_draft, S.name_focus = sec.name, sec.name, true
                end
                if ImGui.MenuItem(ctx, 'Move up') then
                    SB.section_move(sec.name, -1)
                end
                if ImGui.MenuItem(ctx, 'Move down') then
                    SB.section_move(sec.name, 1)
                end
                ImGui.Separator(ctx)
                -- Nothing on disk is touched, so this needs no warning.
                if ImGui.MenuItem(ctx, 'Delete section') then
                    SB.section_remove(sec.name)
                    if S.tsec == sec.name then pick('all') end
                    S.dirty = true
                end
                ImGui.EndPopup(ctx)
            end
            pop_menu_style()
        end
        ImGui.PopID(ctx)
    end
    if S.naming == '' then section_editor() end
    if #list == 0 and S.naming == nil then
        ImGui.TextColored(ctx, C.text_faint, 'None yet')
    end
    ImGui.PopStyleVar(ctx)
end

local function take_root(path)
    local added, why = SB.root_add(path)
    if added then
        set_status('Added ' .. SB.dir_name(path))
        SB.scan_start(SB.cfg.roots, SB.cfg.depth)
        S.dirty = true
    elseif why then
        set_status(why)
    end
    return added
end

-- One click, one picker. Typing a path is the fallback for anyone without
-- js_ReaScriptAPI, not a step everyone else has to walk through.
local function add_root()
    if reaper.JS_Dialog_BrowseForFolder then
        local ok, folder = reaper.JS_Dialog_BrowseForFolder(
            'Folder with REAPER projects', '')
        if ok == 1 and folder ~= '' then take_root(folder) end
        return
    end
    S.adding_root, S.new_root, S.root_focus = true, '', true
end

-- The typed fallback, in place in the rail.
local function root_editor()
    ImGui.SetNextItemWidth(ctx, -1)
    local first = S.root_focus
    if first then
        ImGui.SetKeyboardFocusHere(ctx)
        S.root_focus = false
    end
    local commit, text = ImGui.InputTextWithHint(ctx, '##newroot',
        'Paste a folder path', S.new_root or '',
        ImGui.InputTextFlags_EnterReturnsTrue)
    S.new_root = text
    local active = ImGui.IsItemActive(ctx)
    local cancel = (active and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape))
        or (not active and not first)

    if commit then take_root(S.new_root) end
    if commit or cancel then
        S.adding_root, S.new_root, S.root_focus = nil, '', false
    end
end

local function draw_folder_rail()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(7), PX(2))
    if rail_head('FOLDERS', '##addroot', 'Add a folder to scan') then
        add_root()
    end

    if #SB.cfg.roots == 0 and not S.adding_root then
        ImGui.PopStyleVar(ctx)
        ImGui.TextColored(ctx, C.text_dim, 'No folders yet.')
        ImGui.Dummy(ctx, 1, PX(6))
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0, 0.5)
        if ImGui.Button(ctx, 'Add a folder', -1) then add_root() end
        hint('Point it at a folder and it lists the projects in it')
        ImGui.PopStyleVar(ctx)
        return
    end

    if rail_row('##f_all', 'All', #S.items, S.froot == nil) then
        S.froot = nil
        S.sel, S.sel_path = 1, nil
        S.dirty = true
    end
    local counts = {}
    for _, item in ipairs(S.items) do
        if item.root then counts[item.root] = (counts[item.root] or 0) + 1 end
    end

    local drop_root
    for _, root in ipairs(SB.cfg.roots) do
        local base = SB.root_base(root)
        ImGui.PushID(ctx, base)
        if rail_row('##root', SB.dir_name(base),
                counts[base] or 0, S.froot == base) then
            S.froot = base
            S.sel, S.sel_path = 1, nil
            S.dirty = true
        end
        hint(base .. '   right click to rescan or remove')
        push_menu_style()
        if ImGui.BeginPopupContextItem(ctx) then
            if ImGui.MenuItem(ctx, 'Rescan this folder') then
                -- A scan replaces the whole list and the cache with what it
                -- finds, so everything from the other folders is carried
                -- into it first. Without this, rescanning one folder would
                -- delete the rest, on disk too.
                SB.scan_start({ root }, SB.cfg.depth)
                for _, it in ipairs(S.items) do
                    if it.root and SB.root_key(it.root) ~= SB.root_key(base) then
                        SB.scan.found[#SB.scan.found + 1] = it
                        SB.scan.seen[SB.path_key(it.path)] = true
                    end
                end
                set_status('Scanning ' .. SB.dir_name(base) .. '...')
            end
            ImGui.Separator(ctx)
            -- Removing a folder from the list is not touching the folder.
            if ImGui.MenuItem(ctx, 'Remove from the list') then
                drop_root = root
            end
            ImGui.EndPopup(ctx)
        end
        pop_menu_style()
        ImGui.PopID(ctx)
    end
    if drop_root then
        SB.root_remove(drop_root)
        if S.froot == SB.root_base(drop_root) then S.froot = nil end
        if #SB.cfg.roots == 0 then
            -- A scan that finds nothing does not overwrite the cache, on
            -- purpose. With no folders left there is nothing to find, so
            -- the cache has to be emptied here or the projects of the
            -- folder just removed would come back on the next launch.
            SB.scan.queue = {}
            SB.scan.running = false
            SB.scan.aborted = true
            SB.cache_save({})
            S.items = {}
        else
            SB.scan_start(SB.cfg.roots, SB.cfg.depth)
        end
        set_status('Removed ' .. SB.dir_name(drop_root) .. ' from the list')
        S.dirty = true
    end
    if S.adding_root then root_editor() end
    ImGui.PopStyleVar(ctx)

    -- No Hide missing here: everything in this list was put there by the
    -- scan, so a file that is gone is a stale cache entry and Rescan is the
    -- answer to it.
    ImGui.Dummy(ctx, 1, PX(10))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0, 0.5)
    if SB.scan.running then
        if ImGui.Button(ctx, 'Stop scan', -1) then
            SB.scan.queue = {}
            SB.scan.aborted = true
            SB.scan_step(1)
            set_status('Scan stopped')
        end
        hint('Stops the scan and keeps the old list')
    else
        if ImGui.Button(ctx, 'Rescan', -1) then
            SB.scan_start(SB.cfg.roots, SB.cfg.depth)
            set_status('Scanning...')
        end
        hint('Looks through your folders again')
    end
    ImGui.PopStyleVar(ctx)
end

local function draw_rail(height)
    panel('rail', PX(RAIL_W), height, PX(10), PX(9), function()
        if S.view == 'templates' then
            draw_template_rail()
        elseif S.view == 'folders' then
            draw_folder_rail()
        else
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(7), PX(2))
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0, 0.5)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.clear)
        rail_head('START')
        if ImGui.Button(ctx, 'New project', -1) then
            reaper.Main_OnCommand(CMD_NEW_PROJECT, 0)
            if not SB.cfg.keep_open then S.quit = true end
        end
        hint('Empty project. ' .. SHORTCUT .. 'N')
        if ImGui.Button(ctx, 'New tab', -1) then
            reaper.Main_OnCommand(CMD_NEW_TAB_NO_TEMPLATE, 0)
            if not SB.cfg.keep_open then S.quit = true end
        end
        hint('New tab, no template')
        if ImGui.Button(ctx, 'Open file...', -1) then
            reaper.Main_OnCommand(CMD_OPEN_PROJECT, 0)
            if not SB.cfg.keep_open then S.quit = true end
        end
        hint('Pick a project file. ' .. SHORTCUT .. 'O')
        ImGui.PopStyleColor(ctx)
        ImGui.PopStyleVar(ctx, 2)

        ImGui.Dummy(ctx, 1, PX(8))

        if pill_toggle('Hide missing', SB.cfg.hide_missing, -1) then
            SB.cfg.hide_missing = not SB.cfg.hide_missing
            set_bool('hide_missing', SB.cfg.hide_missing)
            S.dirty = true
        end
        hint('Hides projects whose file is gone')
        end

        -- The shortcuts, pinned to the bottom of whatever room is left.
        ImGui.PushFont(ctx, nil, FS(11))
        local lines = {
            'Enter  ' .. (S.query ~= '' and 'open top match' or 'open'),
            SHORTCUT .. 'Enter  new tab',
            SHORTCUT .. 'F  search',
            SHORTCUT .. 'D  favorite',
            'Esc  ' .. (S.query ~= '' and 'clear search' or 'close'),
        }
        local line_h = ImGui.GetTextLineHeightWithSpacing(ctx)
        local need   = line_h * (#lines + 1)
        local rail_w, rail_h = ImGui.GetContentRegionAvail(ctx)
        -- These lines do not wrap and the rail does not scroll, so a wider
        -- system font would run them off the edge. Better to say nothing.
        local widest = 0
        for _, line in ipairs(lines) do
            -- Bind the width to a local first. A ReaImGui getter in the
            -- last argument slot expands to ALL of its return values, and
            -- the trailing ones can be nil - which is how math.max ended
            -- up comparing a number with nil.
            local line_w = ImGui.CalcTextSize(ctx, line)
            widest = math.max(widest, line_w)
        end
        if rail_h > need and rail_w >= widest then
            ImGui.SetCursorPosY(ctx,
                ImGui.GetCursorPosY(ctx) + rail_h - need)
            ImGui.TextColored(ctx, C.text_faint, 'KEYS')
            for _, line in ipairs(lines) do
                ImGui.TextColored(ctx, C.text_faint, line)
            end
        end
        ImGui.PopFont(ctx)
    end)
end

-- The scrollbar shows itself while the list is being scrolled, or while the
-- pointer is near it, and fades out after that. Pure state machine so it can
-- be tested without a frame.
SB.SCROLL_HOLD, SB.SCROLL_FADE = 0.9, 0.35
SB.scroll_state = {}

function SB.scroll_alpha(st, now, scroll_y, near)
    if st.y == nil then st.y = scroll_y end
    if scroll_y ~= st.y or near then
        st.y, st.at = scroll_y, now
    end
    local age = now - (st.at or -1e9)
    if age <= SB.SCROLL_HOLD then return 1 end
    return math.max(0, 1 - (age - SB.SCROLL_HOLD) / SB.SCROLL_FADE)
end

local function fade(col, alpha)
    return (col & 0xFFFFFF00) | math.floor((col & 0xFF) * alpha + 0.5)
end

-- How many columns the track list should use. Two only when one will not
-- hold the list anyway, and only when each column still has room for a name
-- worth reading: half of a narrow panel is worse than a scrollbar.
function SB.track_columns(n, line_h, avail_h, avail_w, num_w, min_name)
    if n <= 0 or line_h <= 0 then return 1 end
    if n * line_h <= avail_h then return 1 end
    if avail_w / 2 >= num_w + min_name then return 2 end
    return 1
end

-- Cuts a string down to a pixel width, keeping whole UTF-8 characters.
-- `from_left` trims the front instead of the back, which is what a path
-- wants: the folder you are in matters more than the volume it sits on.
function SB.fit_text(txt, max_w, from_left)
    if max_w <= 0 then return '' end
    local w = ImGui.CalcTextSize(ctx, txt)
    if w <= max_w then return txt end
    local dots = '...'
    local room = max_w - ImGui.CalcTextSize(ctx, dots)
    -- Not even one character plus the ellipsis: nothing is better than
    -- something that spills over whatever sits beside it.
    if room <= 0 then return '' end
    -- Start from a proportional guess rather than one byte at a time.
    local keep = math.max(1, math.floor(#txt * room / w))
    local cut = function(n)
        return from_left and txt:sub(#txt - n + 1) or txt:sub(1, n)
    end
    while keep > 1 and ImGui.CalcTextSize(ctx, cut(keep)) > room do
        keep = keep - 1
    end
    while keep < #txt and ImGui.CalcTextSize(ctx, cut(keep + 1)) <= room do
        keep = keep + 1
    end
    local out = cut(keep)
    -- Never end (or start) on half a character.
    if from_left then
        while #out > 1 and out:byte(1) >= 0x80 and out:byte(1) < 0xC0 do
            out = out:sub(2)
        end
        return dots .. out
    end
    while #out > 1 and out:byte(#out) >= 0x80 and out:byte(#out) < 0xC0 do
        out = out:sub(1, #out - 1)
    end
    if (out:byte(#out) or 0) >= 0xC0 then out = out:sub(1, #out - 1) end
    return out .. dots
end

-- Numbers read better flush right, which a table cell will not do by itself.
local function right_text(txt, col)
    local avail = ImGui.GetContentRegionAvail(ctx)
    local w = ImGui.CalcTextSize(ctx, txt)
    if avail > w then
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - w)
    end
    ImGui.TextColored(ctx, col, txt)
end

-- PushFont(nil, size) only sets a size, and ImGui loses that size for the
-- rest of the frame as soon as a nested window is submitted - a tooltip, or
-- the table's own column menu. The list then falls back to the window's base
-- size, which is why hovering the header star or showing the BPM column made
-- every row change size. Reapplying it per row is what keeps it steady.
local function list_font()
    ImGui.PopFont(ctx)
    ImGui.PushFont(ctx, nil, LFS(BASE_FONT))
end

local function draw_list(width, height)
    panel('list', width, height, PX(10), PX(8), function()
        ImGui.PushFont(ctx, nil, LFS(BASE_FONT))

        if #S.shown == 0 then
            S.scroll_to = false
            ImGui.PopFont(ctx)
            ImGui.PushFont(ctx, nil, FS(BASE_FONT))
            ImGui.Dummy(ctx, 1, PX(8))
            if S.view == 'folders' and #SB.cfg.roots == 0 then
                ImGui.TextColored(ctx, C.text_dim,
                    'Add a folder and this lists the projects in it.')
                ImGui.Dummy(ctx, 1, PX(4))
                if ImGui.Button(ctx, 'Add a folder') then
                    S.adding_root, S.new_root = true, ''
                    S.root_focus = true
                end
            elseif S.view == 'templates' and S.tmode ~= 'all' then
                ImGui.TextColored(ctx, C.text_dim, 'Nothing here yet.')
                ImGui.Dummy(ctx, 1, PX(4))
                if ImGui.Button(ctx, 'Show all templates') then
                    S.tmode, S.tsec = 'all', nil
                    S.dirty = true
                end
            elseif S.favs_only then
                -- The star that turns this filter off lives in the table header,
                -- and the table is not drawn when the list is empty. Without
                -- this button the filter would have no way out.
                ImGui.TextColored(ctx, C.text_dim, 'No favorites yet.')
                ImGui.Dummy(ctx, 1, PX(4))
                if ImGui.Button(ctx, 'Show all') then
                    S.favs_only = false
                    S.dirty = true
                end
            else
                ImGui.TextColored(ctx, C.text_dim, 'Nothing matches.')
            end
            ImGui.PopFont(ctx)
            return
        end

        local _, table_h = ImGui.GetContentRegionAvail(ctx)

        local list_w = ImGui.GetContentRegionAvail(ctx)
        local mx = ImGui.GetMousePos(ctx)
        local list_x = ImGui.GetCursorScreenPos(ctx)
        local near = ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows)
            and mx > list_x + list_w - PX(26)
        local alpha = SB.scroll_alpha(SB.scroll_state, reaper.time_precise(),
            S.list_scroll or 0, near)
        ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrab,
            fade(rgba(0xFFFFFF, 0x24), alpha))
        ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabHovered,
            fade(rgba(0xFFFFFF, 0x38), alpha))
        ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabActive,
            fade(rgba(0xFFFFFF, 0x4C), alpha))

        local flags = ImGui.TableFlags_ScrollY |
            ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_Resizable |
            ImGui.TableFlags_Reorderable | ImGui.TableFlags_Hideable |
            ImGui.TableFlags_Sortable | ImGui.TableFlags_SortTristate
        -- ImGui remembers per-column pixel widths against the table id. Keying
        -- the id to the current size makes it re-apply the defaults below when
        -- the user changes the interface or text size, instead of keeping the
        -- widths it measured at the old one forever.
        -- Templates want different columns from projects, so they get
        -- their own remembered layout rather than fighting over one.
        local table_id = ('items_v2#%s_%d_%d'):format(tostring(S.view),
            math.floor(SB.ui.scale * 100 + 0.5), math.floor(SB.ui.font * 100 + 0.5))
        if ImGui.BeginTable(ctx, table_id, 7, flags, 0, table_h) then
            -- Inside a scrolling table the cells belong to an inner window, so
            -- the draw list has to be fetched here, not before BeginTable.
            local dl = ImGui.GetWindowDrawList(ctx)
            S.list_scroll = ImGui.GetScrollY(ctx)
            ImGui.TableSetupColumn(ctx, '##fav',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_NoHide |
                ImGui.TableColumnFlags_NoHeaderLabel |
                ImGui.TableColumnFlags_NoResize |
                ImGui.TableColumnFlags_NoReorder |
                ImGui.TableColumnFlags_NoSort, LPX(FAV_COL_W))
            ImGui.TableSetupColumn(ctx, '#',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_DefaultHide, LPX(26))
            ImGui.TableSetupColumn(ctx, 'NAME',
                ImGui.TableColumnFlags_WidthStretch |
                ImGui.TableColumnFlags_NoHide, 55)
            local tpl = S.view == 'templates'
            ImGui.TableSetupColumn(ctx,
                S.view == 'folders' and 'FOLDER' or 'PATH',
                ImGui.TableColumnFlags_WidthStretch |
                (tpl and ImGui.TableColumnFlags_DefaultHide or 0), 38)
            ImGui.TableSetupColumn(ctx, 'MODIFIED',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_PreferSortDescending |
                ((HAS_JS and not tpl) and 0
                    or ImGui.TableColumnFlags_DefaultHide), LPX(92))
            ImGui.TableSetupColumn(ctx, 'SIZE',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_DefaultHide |
                ImGui.TableColumnFlags_PreferSortDescending, LPX(66))
            ImGui.TableSetupColumn(ctx, 'BPM',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_DefaultHide, LPX(46))
            ImGui.TableSetupScrollFreeze(ctx, 0, 1)

            ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text_faint)
            ImGui.PushFont(ctx, nil, LFS(11))
            ImGui.TableHeadersRow(ctx)
            ImGui.PopFont(ctx)
            ImGui.PopStyleColor(ctx)

            -- The star column has no label, so its header cell is ours: click
            -- it to see only the favorites.
            if ImGui.TableSetColumnIndex(ctx, 0) then
                local hx, hy = ImGui.GetCursorScreenPos(ctx)
                local hw = ImGui.GetContentRegionAvail(ctx)
                local hh = ImGui.GetTextLineHeight(ctx)
                if ImGui.InvisibleButton(ctx, '##favheader', hw, hh) then
                    S.favs_only = not S.favs_only
                    S.dirty = true
                end
                local hot = ImGui.IsItemHovered(ctx)
                draw_star(dl, hx + hw / 2, hy + hh / 2,
                    math.min(hh * 0.46, LPX(FAV_COL_W) * 0.42),
                    S.favs_only and C.accent
                    or (hot and C.text_dim or C.text_faint))
            end

            -- Sorting follows whatever header the user clicked.
            local specs_dirty, has_specs = ImGui.TableNeedSort(ctx)
            if has_specs then
                local ok, col, _, dir = ImGui.TableGetColumnSortSpecs(ctx, 0)
                local desc = dir == ImGui.SortDirection_Descending
                if S.sort_refused ~= nil and S.sort_refused ~= col then
                    S.sort_refused = nil
                end
                if ok and S.sort_refused == nil and
                        (specs_dirty or S.sort_col ~= col or
                        S.sort_dir ~= desc) then
                    S.sort_col = col
                    S.sort_dir = dir == ImGui.SortDirection_Descending
                    if not SB.sort_list(S.shown, S.sort_col, S.sort_dir) then
                        S.sort_col, S.sort_dir = nil, nil
                        -- ImGui keeps the header's sort arrow, so without this
                        -- the refusal would be retried on every single frame.
                        S.sort_refused = col
                        set_status(('Too many entries to sort by that (over %d)')
                            :format(SB.SORT_IO_LIMIT))
                    end
                    SB.restore_sel()
                end
            elseif S.sort_col then
                S.sort_col, S.sort_dir = nil, nil
                S.dirty = true
            end

            ImGui.ListClipper_Begin(SB.clipper, #S.shown)
            if S.scroll_to and rawget(ImGui, 'ListClipper_IncludeItemByIndex') then
                ImGui.ListClipper_IncludeItemByIndex(SB.clipper, S.sel - 1)
            end
            while ImGui.ListClipper_Step(SB.clipper) do
                local first, last = ImGui.ListClipper_GetDisplayRange(SB.clipper)
                for row = first, last - 1 do
                    local i = row + 1
                    local item = S.shown[i]
                    if item then
                        ImGui.TableNextRow(ctx)
                        list_font()
                        ImGui.TableSetColumnIndex(ctx, 0)

                        local is_fav = SB.fav_set[item.path] and true or false
                        local star_x, star_y = ImGui.GetCursorScreenPos(ctx)
                        -- Center on the cell ImGui actually gave us: a column
                        -- width remembered from an older layout would put a
                        -- hardcoded offset off-center.
                        local cell_w = ImGui.GetContentRegionAvail(ctx)
                        local star_cx = star_x + cell_w / 2
                        local sel_flags = ImGui.SelectableFlags_SpanAllColumns |
                            ImGui.SelectableFlags_AllowDoubleClick
                        if ImGui.Selectable(ctx, '##' .. item.path, S.sel == i,
                                sel_flags) then
                            -- A click on the star toggles instead of selecting.
                            -- the whole first column counts as the star
                            if ImGui.GetMousePos(ctx) <
                                    star_x + cell_w + PX(CELL_PAD_X) then
                                SB.fav_toggle(item.path)
                                S.dirty = true
                            else
                                set_sel(i)
                                if ImGui.IsMouseDoubleClicked(ctx, 0) then
                                    do_open(ImGui.GetKeyMods(ctx) & MOD_CMD ~= 0
                                        and 'tab' or 'current')
                                end
                            end
                        end
                        local row_hot = ImGui.IsItemHovered(ctx)
                        if S.sel == i then
                            local line_h = ImGui.GetTextLineHeight(ctx)
                            ImGui.DrawList_AddRectFilled(dl,
                                star_x - PX(CELL_PAD_X), star_y - PX(3),
                                star_x - PX(CELL_PAD_X) + PX(2),
                                star_y + line_h + PX(3), C.accent)
                        end
                        if is_fav or row_hot then
                            local lh = ImGui.GetTextLineHeight(ctx)
                            draw_star(dl, star_cx, star_y + lh / 2,
                                math.min(lh * 0.46, LPX(FAV_COL_W) * 0.42),
                                is_fav and C.accent or C.text_faint)
                        end

                        push_menu_style()
                        if ImGui.BeginPopupContextItem(ctx) then
                            set_sel(i)
                            if ImGui.MenuItem(ctx, 'Open') then do_open('current') end
                            if ImGui.MenuItem(ctx, 'Open in new tab') then do_open('tab') end
                            if item.kind == 'project' then
                                if ImGui.MenuItem(ctx, 'Open as new version') then
                                    do_open('copy')
                                end
                            elseif item.kind == 'template' then
                                if ImGui.MenuItem(ctx, 'Edit template file') then
                                    do_open('edit')
                                end
                            end
                            ImGui.Separator(ctx)
                            if ImGui.MenuItem(ctx, is_fav and 'Remove favorite'
                                    or 'Add to favorites') then
                                SB.fav_toggle(item.path)
                                S.dirty = true
                            end
                            if item.kind == 'template' then
                                if ImGui.BeginMenu(ctx, 'Move to') then
                                    local here = SB.section_of(item)
                                    for _, sec in ipairs(SB.cfg.sections) do
                                        if ImGui.MenuItem(ctx, sec, nil,
                                                sec == here) then
                                            SB.file_under(item.path, sec)
                                            S.dirty = true
                                        end
                                    end
                                    if #SB.cfg.sections > 0 then
                                        ImGui.Separator(ctx)
                                    end
                                    if ImGui.MenuItem(ctx, SB.UNSORTED, nil,
                                            here == SB.UNSORTED) then
                                        SB.file_under(item.path, SB.UNSORTED)
                                        S.dirty = true
                                    end
                                    if S.rail_shown ~= false and
                                            ImGui.MenuItem(ctx, 'New section...') then
                                        S.naming, S.name_draft = '', ''
                                        S.name_focus = true
                                        S.file_after = item.path
                                    end
                                    ImGui.EndMenu(ctx)
                                end
                                ImGui.Separator(ctx)
                            end
                            if ImGui.MenuItem(ctx, 'Show in folder') then
                                SB.reveal(item.path)
                            end
                            ImGui.EndPopup(ctx)
                            -- the popup ate the pushed size again
                            list_font()
                        end
                        pop_menu_style()

                        -- Last, on purpose: the label drawn inside a drag
                        -- source becomes ImGui's last item, and anything
                        -- after it that needs the row's own id - the
                        -- context menu, IsItemHovered - would get 0.
                        if item.kind == 'template' and
                                ImGui.BeginDragDropSource(ctx) then
                            ImGui.SetDragDropPayload(ctx, SB.DND, item.path)
                            ImGui.Text(ctx, item.name)
                            ImGui.EndDragDropSource(ctx)
                        end

                        if S.scroll_to and S.sel == i then
                            ImGui.SetScrollHereY(ctx, 0.5)
                            S.scroll_to = false
                        end

                        if ImGui.TableSetColumnIndex(ctx, 1) then
                            right_text(('%d'):format(item.order or i), C.text_faint)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 2) then
                            if item.missing then
                                ImGui.TextColored(ctx, C.warn, '! ' .. item.name)
                            elseif S.sel == i then
                                ImGui.TextColored(ctx, C.accent, item.name)
                            else
                                ImGui.TextColored(ctx, C.text_bright, item.name)
                            end
                        end

                        if ImGui.TableSetColumnIndex(ctx, 3) then
                            local where
                            if S.view == 'folders' then
                                where = SB.folder_label(item)
                            elseif item.group ~= nil and item.group ~= '' then
                                where = item.group
                            else
                                where = SB.short_dir(item.dir, 2)
                            end
                            ImGui.TextColored(ctx, C.text_dim, where)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 4) then
                            local when = not item.missing and SB.value_of(item, 4)
                            right_text(when and when ~= 0
                                and SB.relative_date(when) or '-', C.text_dim)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 5) then
                            SB.value_of(item, 5)
                            right_text(item.size and SB.human_size(item.size)
                                or '-', C.text_dim)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 6) then
                            SB.value_of(item, 6)
                            right_text(item.bpm and ('%g'):format(item.bpm)
                                or '-', C.text_dim)
                        end
                    end
                end
            end
            ImGui.EndTable(ctx)
        end
        ImGui.PopStyleColor(ctx, 3)

        ImGui.PopFont(ctx)
    end)
end

local function kv(key, value)
    value = tostring(value)
    local w = ImGui.GetWindowWidth(ctx)
    local tw = ImGui.CalcTextSize(ctx, value)
    -- Measure the label rather than reserving a fixed 90px for it: at 200%,
    -- or in another language, "Sample rate" is far wider than that and the
    -- value used to be drawn straight over it.
    local kw = ImGui.CalcTextSize(ctx, key)
    ImGui.TextColored(ctx, C.text_faint, key)
    if tw > w - kw - PX(30) then
        -- No room beside the label: give the value its own line.
        ImGui.TextColored(ctx, C.text, value)
        return
    end
    ImGui.SameLine(ctx, w - tw - PX(16))
    ImGui.TextColored(ctx, C.text, value)
end

local function draw_detail(width, height)
    panel('detail', width, height, PX(12), PX(9), function()
        local item = selected()
        if not item then
            ImGui.TextColored(ctx, C.text_dim, 'Nothing selected.')
            return
        end

        -- The four actions are the point of this panel, so their strip is
        -- reserved first and everything above it lives in a box that scrolls.
        -- Before this, a long name plus a full set of metadata simply pushed
        -- the buttons past the bottom edge, where they could not be clicked.
        local tpl = item.kind == 'template'
        local avail_h   = select(2, ImGui.GetContentRegionAvail(ctx))
        local gap       = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
        -- A template puts Open on its own line and the other three on one
        -- row underneath: two rows instead of four, which is most of the
        -- height the track list needed.
        local rows = tpl and 2 or 4
        local buttons_h = ImGui.GetFrameHeight(ctx) * rows + gap * (rows - 1)
        local info_h    = avail_h - buttons_h - gap

        local room = info_h > ImGui.GetTextLineHeight(ctx)
        if room and ImGui.BeginChild(ctx, 'info', 0, info_h) then
            ImGui.PushFont(ctx, nil, FS(15))
            ImGui.TextWrapped(ctx, item.name)
            ImGui.PopFont(ctx)

            ImGui.PushFont(ctx, nil, FS(11))
            if tpl then
                -- One line, trimmed from the front: the folder it is in is
                -- the part that identifies it. The whole path is one hover
                -- away in the status bar.
                local w = ImGui.GetContentRegionAvail(ctx)
                ImGui.TextColored(ctx, C.text_faint,
                    SB.fit_text(item.dir, w, true))
                hint(item.dir)
            else
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text_faint)
                ImGui.TextWrapped(ctx, item.dir)
                ImGui.PopStyleColor(ctx)
            end
            ImGui.PopFont(ctx)

            ImGui.Dummy(ctx, 1, PX(4))
            ImGui.Separator(ctx)
            ImGui.Dummy(ctx, 1, PX(2))

            if item.when == nil then item.when = SB.file_mtime(item.path) or false end

            local settled = SB.meta_cache[item.path] ~= nil or
                reaper.time_precise() - (S.sel_at or 0) > 0.12

            if item.missing then
                ImGui.TextColored(ctx, C.warn, 'File is missing.')
            elseif not settled then
                ImGui.TextColored(ctx, C.text_dim, 'Reading...')
            else
                local meta = SB.meta_for(item.path)
                if meta then
                    if tpl then
                        -- Five labelled rows cost more height than the
                        -- fourteen track names they were sitting on top of.
                        local bits = {}
                        if meta.tempo then
                            bits[#bits + 1] = ('%g BPM'):format(meta.tempo)
                            bits[#bits + 1] = ('%d/%d')
                                :format(meta.num or 4, meta.den or 4)
                        end
                        if meta.srate then
                            bits[#bits + 1] = ('%.1f kHz')
                                :format(meta.srate / 1000)
                        end
                        if meta.length and meta.length > 0 then
                            bits[#bits + 1] = SB.human_time(meta.length)
                        end
                        if #bits > 0 then
                            -- U+00B7 is Latin-1, so the default ReaImGui
                            -- font has it; a bullet would be an empty box.
                            ImGui.TextColored(ctx, C.text_dim,
                                table.concat(bits, '  \194\183  '))
                        end
                    else
                    if meta.tempo then
                        kv('Tempo', ('%g BPM'):format(meta.tempo))
                        kv('Time', ('%d/%d'):format(meta.num or 4, meta.den or 4))
                    end
                    if meta.srate then
                        kv('Sample rate', ('%.1f kHz'):format(meta.srate / 1000))
                    end
                    kv('Tracks', tostring(meta.tracks))
                    kv('Items', tostring(meta.items))
                    if meta.length and meta.length > 0 then
                        kv('Length', SB.human_time(meta.length))
                    end
                    end


                    -- What the template actually sets up. Every other
                    -- launcher makes you open it to find out.
                    if tpl and meta.names and #meta.names > 0 then
                        local n = #meta.names
                        ImGui.Dummy(ctx, 1, PX(7))
                        ImGui.TextColored(ctx, C.text_faint,
                            ('%d TRACKS'):format(meta.tracks))
                        ImGui.Dummy(ctx, 1, PX(2))

                        local x0 = ImGui.GetCursorPosX(ctx)
                        local col_avail = ImGui.GetContentRegionAvail(ctx)
                        local line_h = ImGui.GetTextLineHeightWithSpacing(ctx)
                        local left_h = select(2,
                            ImGui.GetContentRegionAvail(ctx))
                        local num_w = ImGui.CalcTextSize(ctx, tostring(n))
                            + PX(7)

                        -- Two columns only when one will not hold the list
                        -- and each column still has room for a name worth
                        -- reading. Otherwise one column stays easier to scan.
                        local cols = SB.track_columns(n, line_h, left_h,
                            col_avail, num_w, PX(64))
                        local col_w = col_avail / cols
                        local per = math.ceil(n / cols)

                        for row = 1, per do
                            for c = 0, cols - 1 do
                                local i = c * per + row
                                if i <= n then
                                    if c > 0 then
                                        ImGui.SameLine(ctx, x0 + c * col_w)
                                    end
                                    local x = ImGui.GetCursorPosX(ctx)
                                    ImGui.TextColored(ctx, C.text_faint,
                                        tostring(i))
                                    ImGui.SameLine(ctx, x + num_w)
                                    local name = meta.names[i]
                                    if name == '' then name = 'Track ' .. i end
                                    ImGui.TextColored(ctx, C.text_dim,
                                        SB.fit_text(name,
                                            col_w - num_w - PX(8)))
                                end
                            end
                        end
                        if meta.tracks > n then
                            ImGui.TextColored(ctx, C.text_faint,
                                ('and %d more'):format(meta.tracks - n))
                        end
                    end
                else
                    ImGui.TextColored(ctx, C.text_dim, 'Could not read this file.')
                end
            end

        end
        if room then ImGui.EndChild(ctx) end

        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
        if ImGui.Button(ctx, 'Open', -1) then do_open('current') end
        hint('Opens it. Enter')
        ImGui.PopStyleColor(ctx, 3)

        if tpl then
            -- Three short buttons on one row: the words are shorter than
            -- the height a second and third full row would cost.
            local gap_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
            local third = (ImGui.GetContentRegionAvail(ctx) - gap_x * 2) / 3
            if ImGui.Button(ctx, 'New tab', third) then do_open('tab') end
            hint('Opens it in a new tab. ' .. SHORTCUT .. 'Enter')
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, 'Edit', third) then do_open('edit') end
            hint('Opens the template file itself, to change it')
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, 'Folder', third) then SB.reveal(item.path) end
            hint('Shows the file in Finder')
        else
            if ImGui.Button(ctx, 'Open in new tab', -1) then do_open('tab') end
            hint(SHORTCUT .. 'Enter')
            if item.kind == 'project' then
                if ImGui.Button(ctx, 'Open as new version', -1) then
                    do_open('copy')
                end
                hint('Opens a copy, saved as the next version. Alt+Enter')
            else
                -- Keeps the strip exactly four buttons tall at every size.
                ImGui.Dummy(ctx, 1, ImGui.GetFrameHeight(ctx))
            end
            if ImGui.Button(ctx, 'Show in folder', -1) then SB.reveal(item.path) end
            hint('Shows the file in Finder')
        end
    end)
end

local function draw_status()
    local content_w = ImGui.GetContentRegionAvail(ctx)
    ImGui.PushFont(ctx, nil, FS(11))
    local shown, total = #S.shown, #S.items
    local text
    if S.hint and S.hint ~= '' then
        text = S.hint
    elseif SB.scan.running then
        text = ('Scanning: %d folders, %d projects found')
            :format(SB.scan.dirs, #SB.scan.found)
    elseif S.status ~= '' and
            reaper.time_precise() - (S.status_at or 0) < 5 then
        text = S.status
    elseif shown == total then
        text = ('%d %s'):format(total, total == 1 and 'project' or 'projects')
    else
        text = ('%d of %d'):format(shown, total)
    end
    if not S.hint and SB.cfg.hide_missing and S.view == 'recent' then
        local gone = 0
        for _, item in ipairs(S.items) do
            if item.missing then gone = gone + 1 end
        end
        if gone > 0 then
            text = ('%s   %d missing hidden'):format(text, gone)
        end
    end
    -- SameLine takes an absolute offset, so a status line wider than the
    -- space left over would make the cursor jump backwards and the size
    -- buttons would be painted on top of the text. Trim the text instead.
    local pct = ('%d%%'):format(math.floor(SB.ui.scale * 100 + 0.5))
    local bar_w = PX(16) * 6 + ImGui.CalcTextSize(ctx, '|')
        + ImGui.CalcTextSize(ctx, '-') + ImGui.CalcTextSize(ctx, '+')
        + ImGui.CalcTextSize(ctx, pct)
        + ImGui.CalcTextSize(ctx, 'A') * (10 / 12 + 16 / 12)
    text = SB.fit_text(text, content_w - bar_w - PX(10))
    -- The buttons on the right are frame-height; the text is not. Drop it
    -- by half the difference so the whole row reads as one line.
    local drop = (ImGui.GetFrameHeight(ctx) - ImGui.GetTextLineHeight(ctx)) / 2
    local text_y = ImGui.GetCursorPosY(ctx)
    ImGui.SetCursorPosY(ctx, text_y + drop)
    ImGui.TextColored(ctx, C.text_faint, text)
    ImGui.SetCursorPosY(ctx, text_y)

    ImGui.PopFont(ctx)

    -- Interface size and text size, right where the eye ends up anyway.
    ImGui.PushFont(ctx, nil, FS(12))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, PX(7), PX(4))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.clear)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_hov)

    ImGui.SameLine(ctx, math.max(0, content_w - bar_w))

    local function tiny(label, id, tip, color)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, color or C.text_faint)
        local hit = ImGui.Button(ctx, label .. '##' .. id)
        ImGui.PopStyleColor(ctx)
        if tip then hint(tip) end
        ImGui.SameLine(ctx, 0, PX(1))
        return hit
    end

    -- Both A's are the same button height, so the small one is centered on
    -- the big one instead of hanging from the top of the row.
    local big, small = FS(16), FS(10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding,
        PX(7), PX(4) + (big - small) / 2)
    ImGui.PushFont(ctx, nil, small)
    if tiny('A', 'fontdown', 'Smaller list text') then
        SB.set_ui(SB.ui.scale, SB.ui.font - 0.1)
    end
    ImGui.PopFont(ctx)
    ImGui.PopStyleVar(ctx)

    ImGui.PushFont(ctx, nil, big)
    if tiny('A', 'fontup', 'Bigger list text') then
        SB.set_ui(SB.ui.scale, SB.ui.font + 0.1)
    end
    ImGui.PopFont(ctx)

    ImGui.TextColored(ctx, C.line, '|')
    ImGui.SameLine(ctx, 0, PX(1))

    if tiny('-', 'scaledown', 'Smaller window and text') then
        SB.set_ui(SB.ui.scale - 0.1, SB.ui.font)
    end
    local stock = SB.ui.scale == SB.UI_DEFAULT.scale
        and SB.ui.font == SB.UI_DEFAULT.font
    if tiny(pct, 'scalereset', 'Back to the default size',
            (not stock) and C.text_dim or nil) then
        SB.set_ui(SB.UI_DEFAULT.scale, SB.UI_DEFAULT.font)
    end
    if tiny('+', 'scaleup', 'Bigger window and text') then
        SB.set_ui(SB.ui.scale + 0.1, SB.ui.font)
    end

    ImGui.PopStyleColor(ctx, 3)
    ImGui.PopStyleVar(ctx)
    ImGui.PopFont(ctx)
end

local function draw_settings()
    if not S.show_settings then return end
    ImGui.OpenPopup(ctx, 'Settings##sb')
    S.show_settings = false
    S.settings_open = true
    S.startup_cached = nil
    S.js_ok = nil
    S.settings_tab = 'general'
end

-- The tabs are the same pill the main window uses, not ImGui's tab bar:
-- the bar comes with its own frame, its own underline and its own idea of
-- padding, none of which match anything else here.
local function settings_tab(label, key)
    local on = S.settings_tab == key
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, on and C.tab_on or C.clear)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
        on and C.tab_on or C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text,
        on and C.text_bright or C.text_dim)
    if ImGui.Button(ctx, label) then S.settings_tab = key end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.SameLine(ctx)
end

-- A label on the left, its control flush right, the way the detail panel
-- lays out its rows.
local function setting_row(label, width)
    local x = ImGui.GetCursorPosX(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, C.text, label)
    ImGui.SameLine(ctx, x + avail - width)
    ImGui.SetNextItemWidth(ctx, width)
end

local function settings_general()
    ImGui.TextColored(ctx, C.text_faint, 'STARTUP')
    ImGui.Dummy(ctx, 1, PX(2))

    if S.startup_cached == nil then
        S.startup_cached = SB.startup_enabled()
    end
    local rv, want = ImGui.Checkbox(ctx, 'Open this when REAPER starts',
        S.startup_cached)
    if rv then
        SB.startup_set(want)
        S.startup_cached = SB.startup_enabled()
    end
    hint('Adds a line to __startup.lua. Nothing else is touched')

    local rv2, skip = ImGui.Checkbox(ctx,
        'Stay hidden if a project was already opened', SB.cfg.skip_if_open)
    if rv2 then
        SB.cfg.skip_if_open = skip
        set_bool('skip_if_open', skip)
    end
    hint('REAPER reopening your last project counts as already opened')

    if SB.startup_prompt_conflict() then
        ImGui.Dummy(ctx, 1, PX(2))
        ImGui.TextColored(ctx, C.warn,
            'REAPER also shows its own project prompt at startup.')
        if ImGui.Button(ctx, 'Turn REAPER\'s prompt off') then
            SB.fix_startup_prompt()
        end
    end

    ImGui.Dummy(ctx, 1, PX(10))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(4))
    ImGui.TextColored(ctx, C.text_faint, 'WHEN IT OPENS')
    ImGui.Dummy(ctx, 1, PX(2))

    local at = 1
    for i, key in ipairs(SB.OPEN_ON) do
        if key == SB.cfg.open_on then at = i end
    end
    setting_row('Start on', PX(150))
    local rvo, pick_at = ImGui.Combo(ctx, '##starton', at - 1,
        SB.OPEN_ON_LABEL)
    if rvo then
        SB.cfg.open_on = SB.OPEN_ON[pick_at + 1] or 'last'
        set_ext('open_on', SB.cfg.open_on)
    end
    hint('Which tab is showing when the window opens')

    ImGui.Dummy(ctx, 1, PX(2))
    local rvk, keep = ImGui.Checkbox(ctx,
        'Keep the window open after opening a project', SB.cfg.keep_open)
    if rvk then
        SB.cfg.keep_open = keep
        set_bool('keep_open', keep)
    end
    hint('Off means it closes as soon as a project opens')

    ImGui.Dummy(ctx, 1, PX(10))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(4))
    ImGui.TextColored(ctx, C.text_faint, 'APPEARANCE')
    ImGui.Dummy(ctx, 1, PX(2))

    setting_row('Accent', PX(24))
    local rva, picked = ImGui.ColorEdit3(ctx, '##accent',
        SB.accent_rgb or 0, ImGui.ColorEditFlags_NoInputs)
    if rva then
        SB.set_accent_override(SB.theme, picked)
        SB.build_palette()
    end
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, C.text_faint, ({
        theme      = 'From your theme',
        reapertips = 'Theme default',
        default    = 'Theme default',
        fallback   = 'Default, theme color too dark',
        custom     = 'Custom',
    })[SB.accent_source] or '')
    if SB.accent_source == 'custom' then
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, 'Reset') then
            SB.clear_accent_override(SB.theme)
            SB.build_palette()
        end
    end
    hint('Pick a custom accent color for the current theme')
end

local function settings_about()
    ImGui.Text(ctx, ('Project Launcher %s'):format(SB.VERSION))
    local accent_line
    if SB.accent_source == 'custom' then
        accent_line = ('Accent: custom for the "%s" theme')
            :format(SB.theme or '?')
    elseif SB.accent_source == 'theme' then
        accent_line = ('Accent: razor edit outline of the "%s" theme')
            :format(SB.theme or '?')
    elseif SB.accent_source == 'fallback' then
        accent_line = ('Accent: default, the "%s" theme color is too dark')
            :format(SB.theme or '?')
    else
        accent_line = ('Accent: built in for the "%s" theme')
            :format(SB.theme or '?')
    end
    ImGui.TextColored(ctx, C.text_dim, accent_line)

    ImGui.Dummy(ctx, 1, PX(10))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(4))
    ImGui.TextColored(ctx, C.text_faint, 'EXTENSIONS')
    ImGui.Dummy(ctx, 1, PX(2))
    ImGui.TextColored(ctx, C.text_dim, ('ReaImGui   %s   %s')
        :format(HAS_JS and 'js_ReaScriptAPI' or 'no js_ReaScriptAPI',
                HAS_SWS and 'SWS' or 'no SWS'))
    if not HAS_JS then
        ImGui.TextColored(ctx, C.text_dim,
            'js_ReaScriptAPI would add file dates and a folder picker.')
    else
        local item = selected()
        if S.js_ok == nil then
            S.js_ok = item and SB.file_mtime(item.path) ~= nil or item == nil
        end
        if item and not S.js_ok then
            ImGui.TextColored(ctx, C.warn,
                'File dates are not coming through:')
            ImGui.TextWrapped(ctx, SB.js_probe(item.path))
        end
    end
    if not HAS_SWS then
        ImGui.TextColored(ctx, C.text_dim,
            'SWS would let it turn REAPER\'s own prompt off.')
    end
end

local function settings_popup()
    -- Centered on the window it belongs to, not wherever ImGui last left a
    -- popup. Fixed width; the height follows whichever tab is open.
    if S.win_x then
        ImGui.SetNextWindowPos(ctx, S.win_x + (S.win_w or 0) / 2,
            S.win_y + (S.win_h or 0) / 2, ImGui.Cond_Appearing, 0.5, 0.5)
    end
    ImGui.SetNextWindowSizeConstraints(ctx, PX(430), 0, PX(430), 6000)
    if not ImGui.BeginPopupModal(ctx, 'Settings##sb', nil,
            ImGui.WindowFlags_AlwaysAutoResize) then
        S.settings_open = false
        return
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, PX(14), PX(12))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, PX(9), PX(4))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(8), PX(7))

    settings_tab('General', 'general')
    settings_tab('About', 'about')
    ImGui.NewLine(ctx)
    ImGui.Dummy(ctx, 1, PX(4))

    if S.settings_tab == 'about' then
        settings_about()
    else
        settings_general()
    end

    ImGui.Dummy(ctx, 1, PX(10))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(2))

    local w = PX(96)
    ImGui.SetCursorPosX(ctx,
        ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx) - w)
    local close = ImGui.Button(ctx, 'Close', w)
    ImGui.PopStyleVar(ctx, 3)
    if close or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        ImGui.CloseCurrentPopup(ctx)
        S.settings_open = false
    end
    ImGui.EndPopup(ctx)
end

local function handle_keys()
    -- While the settings dialog is up, or a section is being named, the
    -- keys belong there: Enter would otherwise open a project and Escape
    -- would close the window out from under the field.
    if S.settings_open or S.naming ~= nil or S.adding_root then return end

    -- Escape closes (or clears the filter first).
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        if S.query ~= '' then
            S.query = ''
            S.dirty = true
            S.focus_search = true
        else
            S.quit = true
        end
        return
    end

    if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) then move_sel(1) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) then move_sel(-1) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageDown) then move_sel(10) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageUp) then move_sel(-10) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Home) then move_sel(-#S.shown) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_End) then move_sel(#S.shown) end

    local mods = ImGui.GetKeyMods(ctx)
    local enter = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or
        ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
    if enter then
        if mods & MOD_CMD ~= 0 then
            do_open('tab')
        elseif mods & ImGui.Mod_Alt ~= 0 then
            do_open('copy')
        else
            do_open('current')
        end
    end

    if ImGui.IsKeyPressed(ctx, ImGui.Key_F5) then
        SB.meta_cache = {}
        SB.reload()
        set_status('Refreshed')
    end

    if mods & MOD_CMD ~= 0 then
        if ImGui.IsKeyPressed(ctx, ImGui.Key_N) then
            reaper.Main_OnCommand(CMD_NEW_PROJECT, 0)
            if not SB.cfg.keep_open then S.quit = true end
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_O) then
            reaper.Main_OnCommand(CMD_OPEN_PROJECT, 0)
            if not SB.cfg.keep_open then S.quit = true end
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_F) then
            S.focus_search = true
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Comma) then
            S.show_settings = true
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_D) then
            local item = selected()
            if item then
                SB.fav_toggle(item.path)
                S.dirty = true
            end
        end
    end
end

function SB.frame()
    draw_surface()

    if SB.scan.running then
        local more = SB.scan_step(4)
        if not more then
            if S.view == 'folders' then
                S.items = SB.tag_roots(SB.scan.found, SB.cfg.roots)
                S.dirty = true
            end
            set_status(('Found %d projects in %d folders')
                :format(#SB.scan.found, SB.scan.dirs))
        end
    end

    -- Follow the theme accent if the user switches themes.
    local now = reaper.time_precise()
    if now - (S.theme_checked_at or 0) > 0.5 then
        S.theme_checked_at = now
        if SB.theme_key() ~= SB.theme then SB.build_palette() end
    end

    if S.dirty then SB.refilter() end

    handle_keys()

    local content_w = ImGui.GetContentRegionAvail(ctx)
    draw_header(content_w)
    draw_top_bar()

    -- The three zones are separated by lines, not by boxes. The horizontal
    -- one is drawn first and the two verticals start exactly on it.
    local dl = ImGui.GetWindowDrawList(ctx)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    y0 = math.floor(y0) + 0.5
    ImGui.DrawList_AddLine(dl, x0, y0, x0 + content_w, y0, C.line, PX(1))
    ImGui.Dummy(ctx, 1, 1)

    local avail_h  = select(2, ImGui.GetContentRegionAvail(ctx))
    local status_h = ImGui.GetTextLineHeightWithSpacing(ctx) + PX(10)
    local body_h   = math.max(PX(60), avail_h - status_h)

    -- The two side panels have fixed widths, so on a narrow window (or at
    -- 200% on a laptop screen) they would leave the list nothing at all.
    -- They step aside instead of squeezing it: the rail first, since its
    -- actions all have keyboard shortcuts, then the detail panel.
    local rail_w, gap = PX(RAIL_W), PX(BODY_GAP)
    -- A template's track list needs more room than a project's numbers, and
    -- two columns need enough width that a name is still worth reading:
    -- half of the old 230 left about nine characters a column.
    local detail_w = PX(S.view == 'templates' and DETAIL_W + 74 or DETAIL_W)
    local list_min = PX(220)
    local show_rail = content_w >= rail_w + gap + list_min + gap + detail_w
    local show_detail = content_w >=
        (show_rail and rail_w + gap or 0) + list_min + gap + detail_w

    S.rail_shown = show_rail
    if not show_rail then
        if S.naming ~= nil then
            S.naming, S.name_draft, S.file_after = nil, nil, nil
        end
        S.adding_root, S.new_root = nil, ''
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, PX(BODY_GAP), PX(7))
    local _, body_top = ImGui.GetCursorScreenPos(ctx)
    if show_rail then
        draw_rail(body_h)
        ImGui.SameLine(ctx)
    end
    draw_list(show_detail and -(detail_w + gap) or 0, body_h)
    if show_detail then
        ImGui.SameLine(ctx)
        draw_detail(0, body_h)
    end
    ImGui.PopStyleVar(ctx)

    local y1 = body_top + body_h
    if show_rail then
        local xr1 = math.floor(x0 + rail_w + gap / 2) + 0.5
        ImGui.DrawList_AddLine(dl, xr1, y0, xr1, y1, C.line, PX(1))
    end
    if show_detail then
        local xr2 = math.floor(x0 + content_w - detail_w - gap / 2) + 0.5
        ImGui.DrawList_AddLine(dl, xr2, y0, xr2, y1, C.line, PX(1))
    end

    draw_status()

    draw_settings()
    settings_popup()

    -- Cleared last, not first: the size buttons at the bottom right are
    -- submitted after draw_status, and wiping it at the top of the frame
    -- meant their hints were thrown away before anything could show them.
    S.hint = nil
end

local function loop()
    reaper.SetExtState(SB.EXTNAME, 'heartbeat',
        tostring(reaper.time_precise()), false)
    if reaper.GetExtState(SB.EXTNAME, 'show_ui') == '1' then
        reaper.DeleteExtState(SB.EXTNAME, 'show_ui', false)
        ImGui.SetNextWindowFocus(ctx)
    end

    push_style()
    ImGui.SetNextWindowSize(ctx, math.min(PX(940), 1500),
        math.min(PX(580), 950), ImGui.Cond_FirstUseEver)
    -- Deliberately NOT scaled. A minimum of PX(640) is 1280 at 200%, which
    -- is the whole screen on a 1280-wide laptop - and since ImGui pushes a
    -- window up to the minimum but never back down, that trap would stick
    -- even after turning the size back down. The layout collapses its side
    -- panels instead, so a small window is a supported shape.
    ImGui.SetNextWindowSizeConstraints(ctx, 440, 280, 6000, 4000)
    if SB.ui.resize then
        -- Measured inside Begin last frame: out here the current window is
        -- ImGui's own fallback one, which is always 400x400.
        local w, h = S.win_w, S.win_h
        if w and w > 0 then
            ImGui.SetNextWindowSize(ctx,
                math.floor(w * SB.ui.resize + 0.5),
                math.floor(h * SB.ui.resize + 0.5))
        end
        SB.ui.resize = nil
    end
    local visible = ImGui.Begin(ctx, SB.NAME .. '##main', nil,
        ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoCollapse |
        ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
    if visible then
        S.win_w, S.win_h = ImGui.GetWindowSize(ctx)
        S.win_x, S.win_y = ImGui.GetWindowPos(ctx)
        ImGui.PushFont(ctx, nil, FS(BASE_FONT))
        SB.guard('frame', SB.frame)
        ImGui.PopFont(ctx)
    end
    ImGui.End(ctx)
    pop_style()

    if not S.quit then
        reaper.defer(loop)
    end
end

------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------

function SB.main()
    local missing = SB.check_api()
    if #missing > 0 then
        reaper.MB('This version of ReaImGui is missing:\n\n' ..
            table.concat(missing, ', ') ..
            '\n\nUpdate ReaImGui with ReaPack (Extensions > ReaPack > ' ..
            'Synchronize packages) and try again.', 'Project Launcher', 0)
        return
    end

    SB.cfg_load()
    SB.build_palette()
    reaper.atexit(function()
        reaper.DeleteExtState(SB.EXTNAME, 'heartbeat', false)
        reaper.DeleteExtState(SB.EXTNAME, 'show_ui', false)
        -- Toolbar toggle off. REAPER 7.03+ only.
        if reaper.set_action_options then reaper.set_action_options(8) end
    end)

    -- Launched from __startup.lua with a project already loaded? Stay away.
    if SB.cfg.skip_if_open and SB.launched_at_startup then
        local _, name = reaper.EnumProjects(0)
        if name and name ~= '' then return end
    end

    -- The UI loop is really starting now, so light up the toolbar toggle.
    -- 1 = re-running the action terminates this instance instead of asking;
    -- 4 = toggle state on. REAPER 7.03+ only.
    if reaper.set_action_options then reaper.set_action_options(1 | 4) end

    SB.clipper = ImGui.CreateListClipper(ctx)
    ImGui.Attach(ctx, SB.clipper)
    -- No title bar to grab, so let the window be dragged from any gap.
    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 0)

    -- 'last' means whatever tab was open when the window last closed,
    -- which is what it has always done and stays the default.
    local start_on = SB.cfg.open_on
    if start_on == nil or start_on == 'last' or SB.VIEWS[start_on] == nil then
        start_on = SB.cfg.view or 'recent'
    end
    S.view = start_on
    SB.reload(S.view)
    if S.view == 'folders' and #SB.cfg.roots > 0 and #S.items == 0 then
        SB.scan_start(SB.cfg.roots, SB.cfg.depth)
    end
    reaper.defer(loop)
end

if LAUNCHER_TEST then return SB end

-- REAPER < 7.03 has no set_action_options, so flag 1 above never applies and
-- a second run does not terminate this instance: bring the open window to
-- the front instead. On 7.03+ REAPER terminates the running instance first,
-- so this branch is the old-REAPER fallback only.
local beat = tonumber(reaper.GetExtState(SB.EXTNAME, 'heartbeat'))
if beat and reaper.time_precise() - beat < 2 then
    reaper.SetExtState(SB.EXTNAME, 'show_ui', '1', false)
    return SB
end

-- Only __startup.lua sets this flag, so a manual run always shows up.
SB.launched_at_startup = reaper.GetExtState(SB.EXTNAME, 'startup') == '1'
    or reaper.GetExtState(SB.OLD_EXTNAME, 'startup') == '1'
reaper.DeleteExtState(SB.EXTNAME, 'startup', false)
reaper.DeleteExtState(SB.OLD_EXTNAME, 'startup', false)
SB.main()
