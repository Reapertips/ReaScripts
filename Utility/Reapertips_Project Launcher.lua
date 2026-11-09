--[[
  @description Project Launcher
  @author Reapertips (Alejandro Hernandez)
  @version 1.3.0
  @license MIT
  @changelog
    - New: Tree view. In Folders, turn on Tree view under Rescan to see your folders as a tree, like Finder. Click a folder to open or close it.
    - New: a preview player. If a project has an .RPP-PROX file, press Play under its name, and click the bar to jump. No SWS needed.
    - New: when it opens, the launcher checks your folders for new or removed projects and rescans only if something changed. Turn it off in Settings, Check folders for changes on open.
    - Search ignores accents ("reka" finds "Řeka") and matches capital letters outside A to Z.
    - Project details are more compact: two columns, and the tempo shows at most 2 decimals.
    - Fixed Recent projects whose path in reaper.ini had stray NUL characters.
    - Fixed long names cutting their last letter in half.
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
    - `Ctrl/Cmd` + `Enter` opens it in a new tab. If `Settings` > `Open
      projects in` is set to `New tab`, it opens in the current tab instead.
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
    VERSION = '1.2.1',
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

-- Everything ImGui expects to be closed again (windows, tables, popups,
-- pushed styles and fonts) is remembered here as it opens. If a frame throws
-- halfway through, SB.guard closes whatever is still open, newest first, so
-- ReaImGui never sees an unbalanced stack and raises a second error on top
-- of the real one ("Missing PopStyleVar", "Missing EndChild").
SB.scopes = {}
do
    local scopes = SB.scopes
    local function opener(name, close, always)
        local f = rawget(ImGui, name)
        local c = rawget(ImGui, close)
        if not f or not c then return end
        ImGui[name] = function(ctx_, ...)
            local a, b = f(ctx_, ...)
            if always or a then scopes[#scopes + 1] = { close, c, ctx_ } end
            return a, b
        end
    end
    local function closer(name, counted)
        local f = rawget(ImGui, name)
        if not f then return end
        ImGui[name] = function(ctx_, ...)
            local n = counted and (... or 1) or 1
            for _ = 1, n do
                for i = #scopes, 1, -1 do
                    if scopes[i][1] == name then
                        table.remove(scopes, i)
                        break
                    end
                end
            end
            return f(ctx_, ...)
        end
    end
    opener('Begin', 'End', true)
    opener('BeginChild', 'EndChild', true)
    opener('BeginTable', 'EndTable', false)
    opener('BeginPopupContextItem', 'EndPopup', false)
    opener('BeginPopupModal', 'EndPopup', false)
    opener('BeginMenu', 'EndMenu', false)
    opener('BeginDragDropSource', 'EndDragDropSource', false)
    opener('BeginDragDropTarget', 'EndDragDropTarget', false)
    opener('BeginDisabled', 'EndDisabled', true)
    opener('PushStyleVar', 'PopStyleVar', true)
    opener('PushStyleColor', 'PopStyleColor', true)
    opener('PushFont', 'PopFont', true)
    opener('PushID', 'PopID', true)
    for _, name in ipairs({ 'End', 'EndChild', 'EndTable', 'EndPopup',
            'EndMenu', 'EndDragDropSource', 'EndDragDropTarget',
            'EndDisabled', 'PopID', 'PopFont' }) do
        closer(name, false)
    end
    closer('PopStyleVar', true)
    closer('PopStyleColor', true)
end

function SB.unwind(mark)
    local scopes = SB.scopes
    while #scopes > mark do
        local s = table.remove(scopes)
        pcall(s[2], s[3])
    end
end

local HAS_JS  = reaper.JS_File_Stat ~= nil
local HAS_SWS = reaper.CF_LocateInExplorer ~= nil or reaper.BR_Win32_GetPrivateProfileString ~= nil

local OS      = reaper.GetOS()
local IS_WIN  = OS:find('Win') ~= nil
local IS_MAC  = OS:find('OSX') ~= nil or OS:find('macOS') ~= nil
local IS_LINUX = not IS_WIN and not IS_MAC
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
    'ColorEditFlags_NoTooltip',
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
    'CreateListClipper', 'DrawList_AddLine', 'DrawList_AddRectFilled', 'DrawList_AddCircleFilled',
    'DrawList_AddTriangleFilled',
    'DrawList_PathArcTo', 'DrawList_PathLineTo', 'DrawList_PathStroke', 'DrawList_PathClear', 'DrawList_PathFillConcave',
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
    'Key_DownArrow', 'Key_LeftArrow', 'Key_End', 'Key_Enter', 'Key_Escape', 'Key_F',
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
    'TextWrapped', 'WindowFlags_AlwaysAutoResize', 'WindowFlags_NoCollapse', 'WindowFlags_NoDocking', 'WindowFlags_NoScrollWithMouse', 'WindowFlags_NoScrollbar',
    'WindowFlags_NoTitleBar', 'IsItemClicked', 'MouseButton_Middle',
    'Key_W', 'Key_Q', 'Key_A', 'Key_Delete', 'Mod_Shift',
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

-- string.lower only folds ASCII, so "Řeka" never matched a search for "řeka"
-- and accented names sorted by byte value. This also folds the two-byte
-- UTF-8 letters of Latin-1, Latin Extended-A, Greek and Cyrillic.
function SB.lower(s)
    s = s:lower()
    if not s:find('[\xC3-\xD1]') then return s end
    return (s:gsub('[\xC3-\xD1][\x80-\xBF]', function(ch)
        local cp = ((ch:byte(1) & 0x1F) << 6) | (ch:byte(2) & 0x3F)
        local lo
        if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then lo = cp + 0x20
        elseif cp >= 0x100 and cp <= 0x137 and cp % 2 == 0 then lo = cp + 1
        elseif cp >= 0x139 and cp <= 0x148 and cp % 2 == 1 then lo = cp + 1
        elseif cp >= 0x14A and cp <= 0x177 and cp % 2 == 0 then lo = cp + 1
        elseif cp == 0x178 then lo = 0xFF
        elseif cp >= 0x179 and cp <= 0x17E and cp % 2 == 1 then lo = cp + 1
        elseif cp >= 0x391 and cp <= 0x3A9 and cp ~= 0x3A2 then lo = cp + 0x20
        elseif cp >= 0x410 and cp <= 0x42F then lo = cp + 0x20
        elseif cp >= 0x400 and cp <= 0x40F then lo = cp + 0x50
        end
        if not lo then return ch end
        return string.char(0xC0 | (lo >> 6), 0x80 | (lo & 0x3F))
    end))
end

-- Search folding: SB.lower, then the accent taken off, so "reka" finds
-- "Řeka", "cafe" finds "Café" and "nino" finds "Niño". Covers Latin-1
-- Supplement and Latin Extended-A, plus loose combining marks (macOS can
-- hand back names with the accent as a separate character). Only for
-- matching: sorting and display keep the real letters.
SB.FOLD_MAP = {}
do
    local spec = {
        a = { 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0x101, 0x103, 0x105 },
        c = { 0xE7, 0x107, 0x109, 0x10B, 0x10D },
        d = { 0xF0, 0x10F, 0x111 },
        e = { 0xE8, 0xE9, 0xEA, 0xEB, 0x113, 0x115, 0x117, 0x119, 0x11B },
        g = { 0x11D, 0x11F, 0x121, 0x123 },
        h = { 0x125, 0x127 },
        i = { 0xEC, 0xED, 0xEE, 0xEF, 0x129, 0x12B, 0x12D, 0x12F, 0x131 },
        j = { 0x135 },
        k = { 0x137, 0x138 },
        l = { 0x13A, 0x13C, 0x13E, 0x140, 0x142 },
        n = { 0xF1, 0x144, 0x146, 0x148, 0x149, 0x14B },
        o = { 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF8, 0x14D, 0x14F, 0x151 },
        r = { 0x155, 0x157, 0x159 },
        s = { 0x15B, 0x15D, 0x15F, 0x161, 0x17F },
        t = { 0x163, 0x165, 0x167 },
        u = { 0xF9, 0xFA, 0xFB, 0xFC, 0x169, 0x16B, 0x16D, 0x16F, 0x171, 0x173 },
        w = { 0x175 },
        y = { 0xFD, 0xFF, 0x177 },
        z = { 0x17A, 0x17C, 0x17E },
        ae = { 0xE6 }, oe = { 0x153 }, ss = { 0xDF }, th = { 0xFE },
        ij = { 0x133 },
    }
    for base, cps in pairs(spec) do
        for _, cp in ipairs(cps) do
            SB.FOLD_MAP[string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))] = base
        end
    end
end

function SB.fold(s)
    s = SB.lower(s)
    if not s:find('[\xC3-\xC5\xCC\xCD]') then return s end
    s = s:gsub('[\xC3-\xC5][\x80-\xBF]', SB.FOLD_MAP)
    s = s:gsub('\xCC[\x80-\xBF]', ''):gsub('\xCD[\x80-\xAF]', '')
    return s
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

function SB.clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return ('%d:%02d'):format(seconds // 60, seconds % 60)
end

-- Tempo with at most 2 decimals, trailing zeros dropped: 90.0001 is "90",
-- 92.5 is "92.5". A raw %g could print 90.0001 and break the two columns.
function SB.fmt_tempo(bpm)
    local s = ('%.2f'):format(bpm or 0):gsub('0+$', ''):gsub('%.$', '')
    if s == '-0' then s = '0' end
    return s
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

-- The system's short date pattern, as each OS spells it: "dd/MM/y" (Mac),
-- "dd/MM/yyyy" (Windows), "%d/%m/%Y" (Linux). Lua's os.date can't tell: REAPER
-- runs in the C locale, and a Mac app gets no LANG at all. Nil when unreadable.
function SB.read_date_pattern()
    if not reaper.ExecProcess then return nil end
    local cmd
    if IS_MAC then
        cmd = '/usr/bin/osascript -l JavaScript -e "ObjC.import(\'Foundation\');'
            .. 'var f=$.NSDateFormatter.alloc.init;f.dateStyle=1;f.dateFormat.js"'
    elseif IS_WIN then
        cmd = 'reg query "HKCU\\Control Panel\\International" /v sShortDate'
    else
        cmd = 'locale d_fmt'
    end
    local out = reaper.ExecProcess(cmd, 2000)
    if not out then return nil end
    local code, text = out:match('^(%-?%d+)\r?\n(.*)$')
    if code ~= '0' or not text then return nil end
    if IS_WIN then return text:match('REG_SZ%s+([^\r\n]+)') end
    return text:match('[^\r\n]+')
end

-- A system pattern to an os.date format, keeping only its order and separator.
-- Day and month are always two digits so the column stays even. Year first
-- gets all four: 26-11-04 reads like nothing. Nil when it isn't a plain date.
function SB.date_shape(pattern)
    if type(pattern) ~= 'string' then return nil end
    local p = pattern:gsub('%%D', 'm/d/y'):gsub('%%F', 'y-m-d')
    p = p:gsub('%%[eb]', { ['%e'] = 'd', ['%b'] = 'm' }):gsub('%%B', 'm')
    p = p:gsub('%%', ''):lower()
    -- dddd is the weekday's name in Windows patterns.
    p = p:gsub('d+', function(run) return #run > 2 and '' or 'd' end)
    local order, seen = {}, {}
    for part in p:gmatch('[dmy]+') do
        local c = part:sub(1, 1)
        if part:find('[^' .. c .. ']') or seen[c] then return nil end
        seen[c] = true
        order[#order + 1] = c
    end
    if #order ~= 3 then return nil end
    local sep = p:match('[dmy]+([^dmy])') or '/'
    if not sep:find('[/.%-]') then sep = '/' end
    local code = { d = '%d', m = '%m', y = order[1] == 'y' and '%Y' or '%y' }
    return code[order[1]] .. sep .. code[order[2]] .. sep .. code[order[3]]
end

-- Read once, on the first date drawn. If the system won't say, a month name
-- can't be read the wrong way round.
function SB.date_format()
    if not SB.date_fmt then
        SB.date_fmt = SB.date_shape(SB.read_date_pattern()) or '%d %b %y'
    end
    return SB.date_fmt
end

-- One shape for every date in the column, in the system's order: 08/20/26, or
-- 08/20/26 14:05 with the time on. Relative words like "yesterday" read nicely
-- on their own but wreck a column you scan.
function SB.relative_date(stamp, with_time)
    if not stamp or stamp <= 0 then return '' end
    local fmt = SB.date_format()
    return os.date(with_time and fmt .. ' %H:%M' or fmt, stamp)
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
SB.OPEN_ON_LABEL = 'Last tab\0Recent\0Templates\0Folders\0'
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

SB.cfg = { tree_state = {} }

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
    SB.cfg.show_time     = get_bool('show_time', false)
    SB.cfg.look          = get_ext('look', 'dark')
    SB.cfg.skip_if_open  = get_bool('skip_if_open', true)
    SB.cfg.check_open    = get_bool('check_open', true)
    SB.cfg.watch_tabs    = get_bool('watch_tabs', false)
    SB.cfg.view          = get_ext('view', 'recent')
    SB.cfg.open_on       = get_ext('open_on', 'last')
    SB.cfg.open_in       = get_ext('open_in', 'current')
    SB.cfg.tree          = get_bool('tree', false)
    SB.cfg.tree_state    = SB.map_decode(get_ext('tree_state', ''))
    SB.cfg.sections      = SB.list_decode(get_ext('sections', ''))
    SB.cfg.filed         = SB.map_decode(get_ext('filed', ''))
    SB.cfg.used          = SB.map_decode(get_ext('used', ''))
    SB.cfg.hidden        = SB.map_decode(get_ext('hidden', ''))
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
    table.sort(extra, function(a, b) return SB.lower(a) < SB.lower(b) end)
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
                -- REAPER trims ini values. A trailing space kept here made
                -- Main_openProject fail on Windows and leave a template tab.
                -- Stray NUL bytes count as padding too.
                value = value:gsub('\0', ''):match('^%s*(.-)%s*$')
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

-- Same file, even if one side came back with the other slash on Windows.
function SB.same_path(a, b)
    if IS_WIN then
        a, b = a:gsub('/', '\\'), b:gsub('/', '\\')
    end
    return SB.path_key(a) == SB.path_key(b)
end

function SB.read_file(path, max_bytes)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read(max_bytes or 'a')
    f:close()
    return data
end

-- Projects taken out of Recent from here. REAPER's own list cannot be edited
-- while it runs, so they are hidden instead: path -> the rank they had when
-- they were removed. A better rank later means REAPER moved the project up
-- again, which only happens when it was opened, so it comes back by itself.
-- File > Recent projects is untouched.
function SB.hidden_save()
    set_ext('hidden', SB.map_encode(SB.cfg.hidden or {}))
end

function SB.hide_recent(items)
    SB.cfg.hidden = SB.cfg.hidden or {}
    local n = 0
    for _, item in ipairs(items) do
        if item.kind == 'project' and item.order then
            SB.cfg.hidden[SB.path_key(item.path)] = tostring(item.order)
            n = n + 1
        end
    end
    if n > 0 then SB.hidden_save() end
    return n
end

function SB.unhide_recent(path)
    local hidden = SB.cfg.hidden
    local key = SB.path_key(path)
    if hidden and hidden[key] then
        hidden[key] = nil
        SB.hidden_save()
        return true
    end
    return false
end

function SB.unhide_all()
    SB.cfg.hidden = {}
    SB.hidden_save()
end

function SB.load_recents()
    local ini = reaper.get_ini_file()
    local text = ini and SB.read_file(ini)
    if not text then return {} end
    local list = {}
    local hidden = SB.cfg.hidden or {}
    local still_there, changed = {}, false
    SB.removed_n = 0
    for order, path in ipairs(SB.parse_recent_ini(text)) do
        local key = SB.path_key(path)
        local rank = tonumber(hidden[key])
        if rank and order < rank then
            hidden[key] = nil
            changed = true
            rank = nil
        elseif rank and order > rank then
            -- Pushed down by newer projects. Following it keeps the rank
            -- honest, so a project hidden at the top comes back once it is
            -- opened again after something else.
            hidden[key] = tostring(order)
            changed = true
        end
        if rank then
            still_there[key] = true
            SB.removed_n = SB.removed_n + 1
        else
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
    end
    -- A project REAPER has dropped from its list has nothing left to hide.
    -- An empty read (file busy or half written) says nothing about that.
    if next(still_there) ~= nil or #list > 0 then
        for key in pairs(hidden) do
            if not still_there[key] then
                hidden[key] = nil
                changed = true
            end
        end
    end
    if changed then SB.hidden_save() end
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
        return SB.lower(a.name) < SB.lower(b.name)
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

-- Is `dir` the folder `base` or somewhere inside it?
function SB.under_dir(dir, base)
    local dk, bk = SB.path_key(dir), SB.path_key(base)
    if dk == bk then return true end
    local c = dk:sub(#bk + 1, #bk + 1)
    return dk:sub(1, #bk) == bk and (c == '/' or c == '\\')
end

-- Roots of the scan that cannot be reached right now (unplugged drive, NAS
-- off). Their old projects stay listed, as missing, instead of vanishing.
function SB.unreachable_roots(roots)
    local down = {}
    for _, base in ipairs(roots or {}) do
        if not SB.is_dir(base) then down[#down + 1] = base end
    end
    return down
end

function SB.scan_start(roots, depth)
    SB.scan.running = true
    SB.scan.found   = {}
    SB.scan.seen    = {}
    SB.scan.dirs    = 0
    SB.scan.queue   = {}
    SB.scan.walked  = {}
    SB.scan.aborted = false
    SB.scan.sig     = {}
    SB.scan.partial = nil
    SB.scan.roots   = {}
    for _, r in ipairs(roots) do
        -- SB.join never leaves a trailing separator, so roots must not
        -- either, or the loop guard would not recognize the same folder.
        local dir = SB.root_base(r)
        if dir ~= '' then
            SB.scan.roots[#SB.scan.roots + 1] = dir
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

        local block = { dir = job.dir, files = {} }
        SB.scan.sig[#SB.scan.sig + 1] = block
        local i, file = 0, reaper.EnumerateFiles(job.dir, 0)
        while file do
            if SB.ext(file) == 'rpp' then
                local full = SB.join(job.dir, file)
                local key = SB.path_key(full)
                block.files[#block.files + 1] = { path = full, mt = SB.raw_mtime(full) }
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
            block.nsub = 0
            local j, sub = 0, reaper.EnumerateSubdirectories(job.dir, 0)
            while sub do
                if not SKIP_DIRS[sub:lower()] and sub:sub(1, 1) ~= '.' then
                    block.nsub = block.nsub + 1
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
        SB.scan.down = SB.unreachable_roots(SB.scan.roots)
        if #SB.scan.down > 0 and not SB.scan.aborted then
            for _, it in ipairs(SB.cache_load()) do
                local key = SB.path_key(it.path)
                if not SB.scan.seen[key] then
                    for _, base in ipairs(SB.scan.down) do
                        if SB.under_dir(it.dir, base) then
                            SB.scan.seen[key] = true
                            SB.scan.found[#SB.scan.found + 1] = it
                            break
                        end
                    end
                end
            end
        end
        table.sort(SB.scan.found, function(a, b)
            return SB.lower(a.name) < SB.lower(b.name)
        end)
        for k, it in ipairs(SB.scan.found) do it.order = k end
        -- An empty result usually means an unplugged drive or a bad path.
        -- Keep the last good cache instead of wiping it.
        -- A stopped scan only saw part of the disk; keeping the last full
        -- cache is better than replacing it with a fragment.
        if #SB.scan.found > 0 and not SB.scan.aborted then
            SB.cache_save(SB.scan.found)
            SB.sig_save(SB.scan.sig, SB.scan.partial, SB.scan.down)
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

------------------------------------------------------------------------------
-- Folders as a tree
--
-- build_tree turns projects tagged by tag_roots (item.root, item.rel) into
-- nested folder nodes, one top node per added folder. Only folders that lead
-- to a project exist. REAPER's own "Name/Name.rpp" folder is folded into its
-- parent so each project is one row, not a folder holding one row.
-- tree_flatten walks that into the visible rows (folders and projects) and
-- the list of visible projects, which stays the keyboard's list (S.shown).
------------------------------------------------------------------------------

SB.TREE_INDENT = 22

function SB.build_tree(items)
    local tops, top_by_key = {}, {}
    local part_pat = IS_WIN and '[^/\\]+' or '[^/]+'
    local function node_for(parent_list, by_key, key, name)
        local node = by_key[key]
        if not node then
            node = { name = name, key = key, folders = {}, by_key = {},
                     items = {}, count = 0 }
            by_key[key] = node
            parent_list[#parent_list + 1] = node
        end
        return node
    end
    for _, item in ipairs(items) do
        local root = item.root or ''
        local top = node_for(tops, top_by_key, SB.path_key(root),
            item.root and (item.root_name or item.root) or 'Other')
        top.path = root
        local node, key = top, top.key
        for part in (item.rel or ''):gmatch(part_pat) do
            key = key .. '/' .. SB.path_key(part)
            node = node_for(node.folders, node.by_key, key, part)
        end
        node.items[#node.items + 1] = item
    end
    local function finish(node, depth)
        node.depth = depth
        local kept = {}
        for _, child in ipairs(node.folders) do
            finish(child, depth + 1)
            local only = child.items[1]
            if #child.folders == 0 and #child.items == 1
                    and SB.path_key(child.name) == SB.path_key(only.name) then
                node.items[#node.items + 1] = only
            else
                kept[#kept + 1] = child
            end
        end
        table.sort(kept, function(a, b)
            local la, lb = SB.lower(a.name), SB.lower(b.name)
            if la == lb then return a.name < b.name end
            return la < lb
        end)
        node.folders, node.by_key = kept, nil
        local n = #node.items
        for _, child in ipairs(kept) do n = n + child.count end
        node.count = n
    end
    for _, top in ipairs(tops) do finish(top, 0) end
    table.sort(tops, function(a, b)
        local la, lb = SB.lower(a.name), SB.lower(b.name)
        if la == lb then return a.key < b.key end
        return la < lb
    end)
    return tops
end

-- Folders start closed except the added ones; a click is remembered.
function SB.tree_is_open(node)
    local v = SB.cfg.tree_state[node.key]
    if v == nil then return node.depth == 0 end
    return v == '1'
end

function SB.tree_toggle(node)
    local state = SB.tree_is_open(node) and '0' or '1'
    -- Back at its default the folder needs no entry, so the saved list only
    -- holds folders the user really changed.
    if state == (node.depth == 0 and '1' or '0') then state = nil end
    SB.cfg.tree_state[node.key] = state
    -- A newline in a folder name would split the ini line; keep those
    -- folders for this session only.
    local keep = {}
    for k, v in pairs(SB.cfg.tree_state) do
        if not k:find('[\r\n\30\31]') then keep[k] = v end
    end
    set_ext('tree_state', SB.map_encode(keep))
end

-- rows: { folder = node, depth, open } or { item, idx, depth, parent }.
-- visible: projects in row order (idx points into it). skip_top hides the
-- added folder's own row, for the rail view of a single folder.
function SB.tree_flatten(tops, skip_top)
    local rows, visible, row_of = {}, {}, {}
    local function walk(node, depth, hide_self)
        local open = hide_self or SB.tree_is_open(node)
        if not hide_self then
            rows[#rows + 1] = { folder = node, depth = depth, open = open }
        end
        if not open then return end
        local d = hide_self and depth or depth + 1
        for _, child in ipairs(node.folders) do walk(child, d, false) end
        for _, item in ipairs(node.items) do
            visible[#visible + 1] = item
            row_of[#visible] = #rows + 1
            rows[#rows + 1] = { item = item, idx = #visible, depth = d,
                                parent = (not hide_self) and node or nil }
        end
    end
    for _, top in ipairs(tops) do walk(top, 0, skip_top and true or false) end
    return rows, visible, row_of
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
-- .RPP-PROX preview. REAPER keeps a rendered copy of a project next to it
-- (a WAV, named like the project plus -PROX). It plays through REAPER's own
-- source preview (Xen_StartSourcePreview), so SWS is not needed. REAPER has
-- no seek on that call, so the launcher copies the part still to play into a
-- small temp WAV and previews that. Opening the .RPP-PROX itself as a source
-- would make REAPER re-render (overwrite) it, so a file that is not a plain
-- WAV is not played at all.
------------------------------------------------------------------------------

SB.px = {}
SB.px_n = 0
SB.px_found = {}

function SB.prox_available()
    return reaper.Xen_StartSourcePreview ~= nil
        and reaper.Xen_StopSourcePreview ~= nil
        and reaper.PCM_Source_CreateFromFile ~= nil
end

-- The .RPP-PROX that belongs to a project, or nil. Looked up once per project.
function SB.prox_for(path)
    local cached = SB.px_found[path]
    if cached ~= nil then return cached or nil end
    -- REAPER appends -PROX to the project's file name, so that is the name
    -- tried first and it matches however the extension is cased (song.rpp
    -- gives song.rpp-PROX). The rest are variants of the suffix's case, for
    -- case-sensitive file systems. One lookup per project, cached below.
    local base = path:gsub('%.[rR][pP][pP]$', '')
    local found = false
    local tries = { path .. '-PROX', path .. '-prox' }
    for _, ext in ipairs({ '.RPP-PROX', '.rpp-PROX', '.RPP-prox', '.rpp-prox',
                           '.Rpp-Prox' }) do
        tries[#tries + 1] = base .. ext
    end
    for _, try in ipairs(tries) do
        if reaper.file_exists(try) then found = try break end
    end
    SB.px_found[path] = found
    return found or nil
end

-- Format and data position of a plain WAV, or nil.
function SB.wav_info(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local head = f:read(12)
    if not head or #head < 12 or head:sub(1, 4) ~= 'RIFF'
            or head:sub(9, 12) ~= 'WAVE' then
        f:close()
        return nil
    end
    local flen = f:seek('end') or 0
    local info, pos = {}, 12
    for _ = 1, 64 do
        f:seek('set', pos)
        local h = f:read(8)
        if not h or #h < 8 then break end
        local id, size = h:sub(1, 4), string.unpack('<I4', h, 5)
        if id == 'fmt ' then
            local fm = f:read(math.min(size, 40))
            if not fm or #fm < 16 then break end
            info.fmt = fm
            info.rate = string.unpack('<I4', fm, 5)
            info.block = string.unpack('<I2', fm, 13)
        elseif id == 'data' then
            info.data_off = pos + 8
            info.data_size = math.min(size, flen - (pos + 8))
            break
        end
        pos = pos + 8 + size + (size % 2)
    end
    f:close()
    if not (info.fmt and info.data_off and info.rate and info.rate > 0
            and info.block and info.block > 0) then
        return nil
    end
    info.frames = info.data_size // info.block
    info.seconds = info.frames / info.rate
    if info.frames < 1 then return nil end
    return info
end

-- Windows of audio copied to the temp WAVs. The first one is small so Play
-- starts at once; the next one is copied a little per frame while the
-- current one plays, and started when the current one ends. A long PROX is
-- never copied in one go, whatever the seek position.
SB.PX_FIRST  = 15      -- seconds in the window that starts playing
SB.PX_WINDOW = 45      -- seconds in every window after it
SB.PX_CHUNK  = 2 << 20 -- bytes copied per frame for the next window
SB.PX_SLOTS  = 3

-- Temp files that could not be removed yet (REAPER may still hold them).
-- They are retried on later frames, and at exit.
SB.px_pending = {}
SB.px_sweep_at = 0

function SB.px_delete(path)
    if not path then return end
    os.remove(path)
    if reaper.file_exists(path) then SB.px_pending[path] = true
    else SB.px_pending[path] = nil end
end

-- force: retry now. Otherwise at most twice a second.
function SB.px_sweep(force)
    if next(SB.px_pending) == nil then return end
    local now = reaper.time_precise()
    if not force and now - SB.px_sweep_at < 0.5 then return end
    SB.px_sweep_at = now
    for path in pairs(SB.px_pending) do
        os.remove(path)
        if not reaper.file_exists(path) then SB.px_pending[path] = nil end
    end
end

-- A temp path that is free to write: not one still waiting to be deleted.
function SB.px_slot()
    local dir = SB.cache_path()
    reaper.RecursiveCreateDirectory(dir, 0)
    for _ = 1, SB.PX_SLOTS do
        SB.px_n = SB.px_n + 1
        local p = SB.join(dir, ('prox-preview-%d.wav'):format(SB.px_n % SB.PX_SLOTS))
        if not SB.px_pending[p] then return p end
    end
    return nil
end

-- Opens a copy of `nframes` frames starting at frame `skip`: the WAV header
-- is written now, the audio by wav_copy. Returns a job, or nil.
function SB.wav_begin(path, info, skip, nframes, out)
    local fi = io.open(path, 'rb')
    if not fi then return nil end
    local fo = io.open(out, 'wb')
    if not fo then fi:close() return nil end
    local fmt = info.fmt
    local pad = (#fmt % 2 == 1) and '\0' or ''
    local n = nframes * info.block
    fo:write('RIFF', string.pack('<I4', 4 + 8 + #fmt + #pad + 8 + n), 'WAVE',
        'fmt ', string.pack('<I4', #fmt), fmt, pad,
        'data', string.pack('<I4', n))
    fi:seek('set', info.data_off + skip * info.block)
    return { fi = fi, fo = fo, left = n, out = out }
end

-- Copies up to `bytes`. Returns true when the job is done (or failed:
-- job.failed), closing both files.
function SB.wav_copy(job, bytes)
    while job.left > 0 and bytes > 0 do
        local chunk = job.fi:read(math.min(job.left, bytes, 1 << 20))
        if not chunk or #chunk == 0 then job.failed = true break end
        job.fo:write(chunk)
        job.left = job.left - #chunk
        bytes = bytes - #chunk
    end
    if job.left <= 0 or job.failed then
        SB.wav_close(job)
        return true
    end
    return false
end

function SB.wav_close(job)
    if job.fi then job.fi:close() job.fi = nil end
    if job.fo then job.fo:close() job.fo = nil end
end

-- Writes `nframes` frames (default: all that is left) from `skip` into a
-- WAV, all at once. Returns true when done.
function SB.wav_tail(path, info, skip, out, nframes)
    nframes = math.min(nframes or math.huge, info.frames - skip)
    local job = SB.wav_begin(path, info, skip, nframes, out)
    if not job then return false end
    SB.wav_copy(job, math.huge)
    return not job.failed
end

-- Length in seconds of a playable PROX, or nil. Read once per file, so the
-- time can show before Play and nothing moves when it starts.
SB.px_len = {}
function SB.prox_len(prox)
    local cached = SB.px_len[prox]
    if cached ~= nil then return cached or nil end
    local info = SB.wav_info(prox)
    SB.px_len[prox] = info and info.seconds or false
    return info and info.seconds or nil
end

-- Drops the next window that was being prepared.
function SB.px_drop_next(px)
    local nx = px.nxt
    if not nx then return end
    SB.wav_close(nx)
    -- Never started, so the source is still ours to free.
    if nx.src and reaper.PCM_Source_Destroy then
        pcall(reaper.PCM_Source_Destroy, nx.src)
    end
    SB.px_delete(nx.out)
    px.nxt = nil
end

function SB.prox_stop()
    local px = SB.px
    if px.id then pcall(reaper.Xen_StopSourcePreview, px.id) end
    -- A source REAPER is previewing belongs to REAPER once the preview has
    -- started: destroying it after Xen_StopSourcePreview crashed REAPER
    -- 7.81 (Windows). Only a source that never started is ours to free.
    if px.src and not px.id and reaper.PCM_Source_Destroy then
        pcall(reaper.PCM_Source_Destroy, px.src)
    end
    SB.px_drop_next(px)
    SB.px_delete(px.tmp)
    SB.px = {}
end

-- Starts (or restarts) the preview of `item_path` at `frac` of its length.
-- Returns true when it is playing.
function SB.prox_start(item_path, prox, frac)
    SB.prox_stop()
    if not SB.prox_available() then return false end
    frac = math.max(0, math.min(0.999, frac or 0))
    local info = SB.wav_info(prox)
    -- Not a plain WAV: opening a .RPP-PROX as a source makes REAPER
    -- re-render (overwrite) it from the project, so never do it.
    if not info then return false end
    local skip = math.min(info.frames - 1, math.floor(frac * info.frames))
    local nframes = math.max(1, math.min(info.frames - skip,
        math.floor(SB.PX_FIRST * info.rate)))
    local src
    local tmp = SB.px_slot()
    if tmp and SB.wav_tail(prox, info, skip, tmp, nframes) then
        src = reaper.PCM_Source_CreateFromFile(tmp)
    end
    local id
    if src then
        local ok, rv = pcall(reaper.Xen_StartSourcePreview, src, 1.0, false)
        if ok and type(rv) == 'number' and rv >= 0 then id = rv end
    end
    if not id then
        SB.px = { src = src, tmp = tmp }
        SB.prox_stop()
        return false
    end
    local stop_at = skip + nframes
    SB.px = {
        item = item_path, prox = prox, id = id, src = src, tmp = tmp,
        offset = skip / info.rate, dur = info.seconds,
        started = reaper.time_precise(), seekable = true,
        info = info, win_end = stop_at / info.rate,
        next_skip = stop_at < info.frames and stop_at or nil,
    }
    return true
end

-- Prepares the next window a little each frame, and starts it when the
-- current one ends. Returns false when the preview had to stop.
function SB.px_pump(px, now)
    local info = px.info
    if px.next_skip and not px.nxt then
        local out = SB.px_slot()
        local n = math.min(info.frames - px.next_skip,
            math.floor(SB.PX_WINDOW * info.rate))
        local job = out and SB.wav_begin(px.prox, info, px.next_skip, n, out)
        if job then
            job.skip, job.frames = px.next_skip, n
            px.nxt = job
        else
            SB.px_delete(out)
            px.next_skip = nil -- plays to the end of this window, then stops
        end
    end
    local nx = px.nxt
    if nx and not nx.ready then
        if SB.wav_copy(nx, SB.PX_CHUNK) then
            if nx.failed then
                SB.px_drop_next(px)
                px.next_skip = nil
            else
                nx.src = reaper.PCM_Source_CreateFromFile(nx.out)
                if nx.src then nx.ready = true
                else
                    SB.px_drop_next(px)
                    px.next_skip = nil
                end
            end
        end
    end
    nx = px.nxt
    if nx and nx.ready and now - px.started >= px.win_end - px.offset then
        local ok, rv = pcall(reaper.Xen_StartSourcePreview, nx.src, 1.0, false)
        if not (ok and type(rv) == 'number' and rv >= 0) then
            return false
        end
        pcall(reaper.Xen_StopSourcePreview, px.id)
        SB.px_delete(px.tmp)
        -- On time, the clock stays on the ideal line so the display does
        -- not jump; if the copy was slow, it restarts from now.
        local ideal = px.started + (px.win_end - px.offset)
        px.started = (now - ideal > 0.25) and now or ideal
        px.offset = nx.skip / info.rate
        px.id, px.src, px.tmp = rv, nx.src, nx.out
        local stop_at = nx.skip + nx.frames
        px.win_end = stop_at / info.rate
        px.next_skip = stop_at < info.frames and stop_at or nil
        px.nxt = nil
    end
    return true
end

-- Where the playhead is, in seconds. Stops by itself at the end.
function SB.prox_pos()
    local px = SB.px
    if not px.id then return 0 end
    local now = reaper.time_precise()
    if not SB.px_pump(px, now) then
        SB.prox_stop()
        return 0
    end
    local pos = px.offset + (now - px.started)
    if pos >= px.dur or (pos >= px.win_end and not px.next_skip) then
        SB.prox_stop()
        return 0
    end
    -- The next window is not ready yet: wait at the end of this one.
    return math.min(pos, px.win_end)
end

------------------------------------------------------------------------------
-- Folder change check. A scan leaves a small fingerprint next to the cache:
-- for every folder it walked, its project files (with their modified time
-- when js_ReaScriptAPI is there) and how many subfolders it had. Opening the
-- launcher compares that with the disk, a few folders per frame, and starts
-- a rescan only if something differs.
------------------------------------------------------------------------------

-- The modified time as one comparable string, or '' without js_ReaScriptAPI.
function SB.raw_mtime(path)
    if not HAS_JS then return '' end
    local ok, rv, _, _, mtime = pcall(reaper.JS_File_Stat, path)
    if not ok or type(rv) ~= 'number' or rv < 0 or mtime == nil then return '' end
    return tostring(mtime)
end

function SB.sig_path()
    local dir = SB.cache_path()
    return SB.join(dir, 'folder-sig.txt')
end

local function sig_clean(text)
    return not text:find('[\t\r\n]')
end

function SB.sig_load()
    local text = SB.read_file(SB.sig_path())
    if not text then return nil end
    local blocks, cur = {}, nil
    for line in text:gmatch('[^\r\n]+') do
        local kind, a, rest = line:match('^(%u)\t([^\t]*)\t(.*)$')
        if kind == 'D' then
            cur = { dir = rest, files = {}, nsub = tonumber(a) }
            blocks[#blocks + 1] = cur
        elseif kind == 'F' and cur then
            cur.files[#cur.files + 1] = { path = rest, mt = a }
        end
    end
    return blocks
end

-- partial: a root that was rescanned alone; the other roots keep their
-- entries from the last full scan.
function SB.sig_save(blocks, partial, down)
    local keep = {}
    if partial or (down and #down > 0) then
        for _, b in ipairs(SB.sig_load() or {}) do
            local old_down = false
            for _, base in ipairs(down or {}) do
                if SB.under_dir(b.dir, base) then old_down = true end
            end
            if old_down or (partial and not SB.under_dir(b.dir, partial)) then
                keep[#keep + 1] = b
            end
        end
    end
    local dir = SB.cache_path()
    reaper.RecursiveCreateDirectory(dir, 0)
    local f = io.open(SB.sig_path(), 'wb')
    if not f then return end
    local function put(b)
        if not sig_clean(b.dir) then return end
        f:write('D\t', b.nsub and tostring(b.nsub) or '-', '\t', b.dir, '\n')
        for _, e in ipairs(b.files) do
            if sig_clean(e.path) then f:write('F\t', e.mt or '', '\t', e.path, '\n') end
        end
    end
    for _, b in ipairs(keep) do put(b) end
    for _, b in ipairs(blocks or {}) do put(b) end
    f:close()
end

-- Is this folder still the way the fingerprint saw it?
function SB.sig_block_same(b)
    local known, n = {}, 0
    for _, e in ipairs(b.files) do
        known[SB.path_key(e.path)] = e
    end
    local i, file = 0, reaper.EnumerateFiles(b.dir, 0)
    while file do
        if SB.ext(file) == 'rpp' then
            n = n + 1
            local e = known[SB.path_key(SB.join(b.dir, file))]
            if not e then return false end
            if e.mt ~= '' and SB.raw_mtime(e.path) ~= e.mt then return false end
        end
        i = i + 1
        file = reaper.EnumerateFiles(b.dir, i)
    end
    if n ~= #b.files then return false end
    if b.nsub then
        local c, j, sub = 0, 0, reaper.EnumerateSubdirectories(b.dir, 0)
        while sub do
            if not SKIP_DIRS[sub:lower()] and sub:sub(1, 1) ~= '.' then c = c + 1 end
            j = j + 1
            sub = reaper.EnumerateSubdirectories(b.dir, j)
        end
        if c ~= b.nsub then return false end
    end
    return true
end

SB.chk = { running = false, changed = false, spent = 0, steps = 0 }

-- Starts the check. Without a fingerprint (first run of this version) the
-- answer is simply "changed": one scan builds it.
function SB.chk_start()
    SB.chk = { running = false, changed = false, spent = 0, steps = 0, i = 1 }
    if not SB.cfg.check_open or #SB.cfg.roots == 0 or SB.scan.running then
        return false
    end
    local blocks = SB.sig_load()
    if not blocks then
        SB.chk.changed = true
        return true
    end
    -- A root that is not there (unplugged drive, NAS off) is not "changed":
    -- it is skipped, so its projects stay listed.
    local down = SB.unreachable_roots((function()
        local bases = {}
        for _, r in ipairs(SB.cfg.roots) do bases[#bases + 1] = SB.root_base(r) end
        return bases
    end)())
    local have = {}
    for _, b in ipairs(blocks) do have[SB.path_key(b.dir)] = true end
    for _, r in ipairs(SB.cfg.roots) do
        local base = SB.root_base(r)
        local is_down = false
        for _, d in ipairs(down) do if d == base then is_down = true end end
        if not is_down and not have[SB.path_key(base)] then
            SB.chk.changed = true
            return true
        end
    end
    local live = {}
    for _, b in ipairs(blocks) do
        local skip = false
        for _, d in ipairs(down) do
            if SB.under_dir(b.dir, d) then skip = true end
        end
        if not skip then live[#live + 1] = b end
    end
    SB.chk.blocks, SB.chk.running = live, #live > 0
    return true
end

-- Walks folders for about `seconds`, so a big library never stalls a frame.
-- Returns true while there is more to compare.
function SB.chk_step(seconds)
    local c = SB.chk
    if not c.running then return false end
    local t0 = reaper.time_precise()
    while c.i <= #c.blocks do
        if not SB.sig_block_same(c.blocks[c.i]) then
            c.changed, c.running = true, false
            break
        end
        c.i = c.i + 1
        if reaper.time_precise() - t0 >= seconds then break end
    end
    if c.i > #c.blocks then c.running = false end
    c.steps = c.steps + 1
    c.spent = c.spent + (reaper.time_precise() - t0)
    return c.running
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
            -- The second field is the "Project sample rate" checkbox. When
            -- it is off the project follows the audio device, and the stored
            -- rate is just a leftover default: show nothing rather than it.
            local sr, use = line:match('^%s*SAMPLERATE%s+(%d+)%s+(%d+)')
            if sr then meta.srate = use ~= '0' and tonumber(sr) or false end
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
    if col == 2 then return SB.lower(item.name) end
    if col == 3 then return SB.lower(item.dir) end
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
        if va == vb then return SB.lower(a.name) < SB.lower(b.name) end
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
-- Backups of a project
--
-- REAPER writes timestamped copies, "Name-2026-10-30_1844.rpp-bak", into the
-- project folder, a Backups folder next to it, or the folder set under
-- Preferences > Project > Backups (autosavedir in reaper.ini). Each folder
-- is listed once and grouped by project name; a project then looks itself up
-- in that, so selecting a row never walks a big folder again.
------------------------------------------------------------------------------

SB.bk_dirs, SB.bk_cache = {}, {}
SB.BK_MAX_FILES = 20000

function SB.autosave_dir()
    if SB.autosave == nil then
        SB.autosave = false
        local ini = reaper.get_ini_file()
        local text = ini and SB.read_file(ini)
        local dir = text and text:match('\n%s*autosavedir=([^\r\n]*)')
        if dir then
            dir = dir:match('^%s*(.-)%s*$')
            if dir ~= '' then SB.autosave = dir end
        end
    end
    return SB.autosave
end

local function is_absolute(path)
    return path:sub(1, 1) == '/' or path:sub(1, 1) == '\\'
        or path:match('^%a:') ~= nil
end

function SB.backup_dirs(path)
    local dir = SB.split_path(path)
    local list = { dir, SB.join(dir, 'Backups') }
    local auto = SB.autosave_dir()
    if auto then
        list[#list + 1] = is_absolute(auto) and auto or SB.join(dir, auto)
    end
    return list
end

-- Name and time out of a backup's file name. A name with no time in it is
-- the copy REAPER keeps of the previous save.
function SB.parse_backup_name(file)
    local name, y, mo, d, h, mi, sec = file:match(
        '^(.*)%-(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)(%d%d)(%d?%d?)%.[Rr][Pp][Pp]%-[Bb][Aa][Kk]$')
    if name and name ~= '' then
        local ok, t = pcall(os.time, { year = tonumber(y), month = tonumber(mo),
            day = tonumber(d), hour = tonumber(h), min = tonumber(mi),
            sec = tonumber(sec) or 0 })
        return name, ok and t or nil
    end
    name = file:match('^(.*)%.[Rr][Pp][Pp]%-[Bb][Aa][Kk]$')
    if name and name ~= '' then return name, nil end
end

function SB.dir_index(dir)
    local cached = SB.bk_dirs[dir]
    if cached then return cached end
    local index = {}
    reaper.EnumerateFiles(dir, -1) -- forget REAPER's cached listing
    local i, file = 0, reaper.EnumerateFiles(dir, 0)
    while file and i < SB.BK_MAX_FILES do
        local name, t = SB.parse_backup_name(file)
        if name then
            local key = SB.path_key(name)
            index[key] = index[key] or {}
            local list = index[key]
            list[#list + 1] = { path = SB.join(dir, file), file = file, t = t }
        end
        i = i + 1
        file = reaper.EnumerateFiles(dir, i)
    end
    SB.bk_dirs[dir] = index
    return index
end

-- Newest first. Cached per project; F5 forgets it.
function SB.backups_of(path)
    -- A backup made while the window stays open turns up when another
    -- project is picked after a minute. A static selection never lists
    -- folders from inside the frame.
    if path ~= SB.bk_last then
        SB.bk_last = path
        local now = reaper.time_precise()
        if now - (SB.bk_at or 0) > 60 then
            SB.bk_dirs, SB.bk_cache, SB.bk_at = {}, {}, now
        end
    end
    local cached = SB.bk_cache[path]
    if cached then return cached end
    local _, file = SB.split_path(path)
    local key = SB.path_key(SB.strip_ext(file))
    local out, seen, dirs = {}, {}, {}
    for _, dir in ipairs(SB.backup_dirs(path)) do
        if not dirs[dir] then
            dirs[dir] = true
            for _, e in ipairs(SB.dir_index(dir)[key] or {}) do
                if not seen[e.path] then
                    seen[e.path] = true
                    -- The previous-save copy has no time in its name.
                    if not e.t then e.t = SB.file_mtime(e.path) end
                    out[#out + 1] = e
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    SB.bk_cache[path] = out
    return out
end

-- "Today 14:30", "Yesterday 09:12", "Oct 30 18:44".
function SB.when_label(t, now)
    if not t then return 'Last save' end
    now = now or os.time()
    local hm = os.date('%H:%M', t)
    local day = os.date('%Y%m%d', t)
    if day == os.date('%Y%m%d', now) then return 'Today ' .. hm end
    if day == os.date('%Y%m%d', now - 86400) then return 'Yesterday ' .. hm end
    return os.date('%b %d', t) .. ' ' .. hm
end

------------------------------------------------------------------------------
-- Filtering
------------------------------------------------------------------------------

-- Every space separated word must appear in the name or the folder.
function SB.matches(item, words)
    if #words == 0 then return true end
    local hay = SB.fold(item.name .. ' ' .. item.dir)
    for _, w in ipairs(words) do
        if not hay:find(w, 1, true) then return false end
    end
    return true
end

function SB.split_words(query)
    local words = {}
    for w in SB.fold(tostring(query or '')):gmatch('%S+') do
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
local CMD_CLOSE_TAB           = 40860 -- File: Close current project tab

-- GUIDs of the FX the .rpp saved as online. Each FX is a BYPASS line
-- (bypass, offline, ...) before its plug-in block and an FXID line after
-- it, at the same block depth, so containers pair up their own children.
function SB.rpp_online_fx(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local online, pending, depth = {}, {}, 0
    local ok = pcall(function()
        for line in f:lines() do
            local s = line:match('^%s*(.-)%s*$')
            if s:sub(1, 1) == '<' then
                depth = depth + 1
            elseif s == '>' then
                pending[depth] = nil
                depth = depth - 1
            else
                local off = s:match('^BYPASS%s+%S+%s+(%S+)')
                if off then
                    pending[depth] = off == '0'
                else
                    local guid = s:match('^FXID%s+(%b{})')
                    if guid then
                        if pending[depth] then online[guid:upper()] = true end
                        pending[depth] = nil
                    end
                end
            end
        end
    end)
    f:close()
    return ok and online or nil
end

-- Lists every FX in `proj` whose GUID is in `online`, in REAPER's order
-- (master, tracks, input FX, takes). Anything not listed (offline in the
-- .rpp, or not in the .rpp at all, like monitoring FX) is left alone.
-- Nothing is loaded here: SB.fx_online_step brings one online per frame,
-- the way REAPER's own "Bring FX online after load" does.
-- Calls fn(idx, guid) for every FX of a track (chain, then input FX at
-- 0x1000000 + i) or a take, container children included. A true return
-- from fn stops the walk and is passed back.
local function walk_fx(obj, is_take, fn)
    local api = is_take and 'TakeFX_' or 'TrackFX_'
    local function visit(idx)
        if fn(idx, reaper[api .. 'GetFXGUID'](obj, idx)) then return true end
        local _, n = reaper[api .. 'GetNamedConfigParm'](obj, idx,
            'container_count')
        for j = 0, (tonumber(n) or 0) - 1 do
            local _, child = reaper[api .. 'GetNamedConfigParm'](obj, idx,
                'container_item.' .. j)
            if tonumber(child) and visit(tonumber(child)) then return true end
        end
    end
    local function chain(count, base)
        for i = 0, count - 1 do
            if visit(base + i) then return true end
        end
    end
    if is_take then return chain(reaper.TakeFX_GetCount(obj), 0) end
    return chain(reaper.TrackFX_GetCount(obj), 0)
        or chain(reaper.TrackFX_GetRecCount(obj), 0x1000000)
end

function SB.fx_online_job(online, proj)
    local list = {}
    local function add(obj, is_take)
        local api = is_take and 'TakeFX_' or 'TrackFX_'
        walk_fx(obj, is_take, function(idx, g)
            -- Only what this load left offline: after a cancelled save
            -- prompt nothing is, and nothing gets touched.
            if g and online[g:upper()]
                    and reaper[api .. 'GetOffline'](obj, idx) then
                list[#list + 1] = { proj = proj, obj = obj, take = is_take,
                    idx = idx, guid = g:upper() }
            end
        end)
    end

    add(reaper.GetMasterTrack(proj), false)
    for t = 0, reaper.CountTracks(proj) - 1 do
        add(reaper.GetTrack(proj, t), false)
    end
    for it = 0, reaper.CountMediaItems(proj) - 1 do
        local item = reaper.GetMediaItem(proj, it)
        for k = 0, reaper.CountTakes(item) - 1 do
            local take = reaper.GetTake(item, k)
            if take then add(take, true) end
        end
    end
    if #list == 0 then return nil end
    return { list = list, i = 0, name = '' }
end

-- A second "Bring FX online" open while one is still running joins the
-- queue instead of dropping what was left of the first.
function SB.fx_online_add(job)
    if not job then return end
    if not SB.fx_job then SB.fx_job = job return end
    for _, fx in ipairs(job.list) do
        SB.fx_job.list[#SB.fx_job.list + 1] = fx
    end
end

-- Brings the next FX of `job` online. Returns true once there is nothing
-- left. A closed project or a deleted track or take is skipped rather than
-- touched, and an FX that moved in its chain since the job was built is
-- found again by its GUID, so the index never hits a different plug-in.
function SB.fx_online_step(job)
    if job.i >= #job.list then return true end
    job.i = job.i + 1
    local fx = job.list[job.i]
    local api = fx.take and 'TakeFX_' or 'TrackFX_'
    local kind = fx.take and 'MediaItem_Take*' or 'MediaTrack*'
    if reaper.ValidatePtr(fx.proj, 'ReaProject*')
            and reaper.ValidatePtr2(fx.proj, fx.obj, kind) then
        local idx = fx.idx
        local g = reaper[api .. 'GetFXGUID'](fx.obj, idx)
        if not g or g:upper() ~= fx.guid then
            idx = nil
            walk_fx(fx.obj, fx.take, function(i, guid)
                if guid and guid:upper() == fx.guid then idx = i return true end
            end)
        end
        if idx then
            local _, name = reaper[api .. 'GetFXName'](fx.obj, idx)
            job.name = name or ''
            reaper[api .. 'SetOffline'](fx.obj, idx, false)
        end
    end
    return job.i >= #job.list
end

-- Brings everything left online at once. Used when the script is stopped
-- mid-job (the toolbar button clicked again), so no FX is left offline
-- without the user asking for it.
function SB.fx_online_finish()
    local job = SB.fx_job
    SB.fx_job = nil
    if not job then return end
    reaper.PreventUIRefresh(1)
    while not SB.fx_online_step(job) do end
    reaper.PreventUIRefresh(-1)
end

-- The open that Enter, double-click and the big button do, and the one
-- Cmd+Enter does. Settings decides which of the two is the default.
function SB.main_open() return SB.cfg.open_in == 'tab' and 'tab' or 'current' end
function SB.alt_open() return SB.cfg.open_in == 'tab' and 'current' or 'tab' end

-- A tab nobody has used: never saved, no changes, no tracks. REAPER starts
-- with one, and with New tab as the default it would be left behind next to
-- every project opened from here.
function SB.current_tab_empty()
    local proj, path = reaper.EnumProjects(-1)
    if not proj or (path or '') ~= '' then return false end
    return reaper.IsProjectDirty(proj) == 0 and reaper.CountTracks(proj) == 0
end

-- The tab that already has this file open, if any.
function SB.open_tab_of(path)
    local i = 0
    while true do
        local proj, fn = reaper.EnumProjects(i)
        if not proj then return nil end
        if fn and fn ~= '' and SB.same_path(fn, path) then return proj end
        i = i + 1
    end
end

-- Tabs the launcher makes itself must not wake it up again: the watcher
-- ignores any tab that appears within a few seconds of this.
function SB.own_tab()
    SB.own_until = reaper.time_precise() + 3
end

function SB.tab_count()
    local n = 0
    while reaper.EnumProjects(n) do n = n + 1 end
    return n
end

-- True when the current tab holds this file. Compared by path first, then
-- by file name, so a mapped drive or a symlink does not look like a failure.
function SB.project_loaded(path)
    local _, now = reaper.EnumProjects(-1)
    if not now or now == '' then return false end
    if SB.same_path(now, path) then return true end
    -- Same name elsewhere: only a mapped drive or a link to the very same
    -- file counts, which shows as the same size and time. A different
    -- project with the same name is not the one asked for.
    local _, a = SB.split_path(now)
    local _, b = SB.split_path(path)
    if SB.path_key(a) ~= SB.path_key(b) then return false end
    local sa, sb = SB.file_size(now), SB.file_size(path)
    if not sa or sa ~= sb then return false end
    local ta, tb = SB.file_mtime(now), SB.file_mtime(path)
    return ta ~= nil and ta == tb
end

-- opts: tab (always a new tab), offline (every FX loads offline), online
-- (bring them back afterwards, needs offline), readonly. The mode strings
-- 'offline', 'online' and 'readonly' are the same flags, one at a time.
-- Returns true when the project is open, false plus a reason when it is not.
function SB.open(item, mode, opts)
    if not item then return end
    opts = opts or {}
    if item.missing then
        reaper.MB('This file is not there any more:\n\n' .. item.path,
            'Project Launcher', 0)
        return
    end

    if item.kind == 'tracktemplate' then
        reaper.Main_openProject(item.path)
        return true
    end

    local online = opts.online or mode == 'online'
    local offline = opts.offline or online or mode == 'offline'
    local readonly = opts.readonly or mode == 'readonly'

    -- The project at the top of Recent is usually the one already open.
    -- Loading it again into a new tab left an empty tab (or the default
    -- template) in front of it, so a plain open just goes to its tab.
    if item.kind == 'project' and not offline and not readonly
            and (mode == nil or mode == 'tab' or mode == 'current') then
        local proj = SB.open_tab_of(item.path)
        if proj then
            reaper.SelectProjectInstance(proj)
            SB.unhide_recent(item.path)
            return true
        end
    end

    -- With New tab as the default, the special opens follow it too.
    local default_tab = SB.cfg.open_in == 'tab'
    local new_tab = opts.tab or mode == 'tab' or mode == 'copy'
        or (default_tab and mode ~= 'current')
    local made_tab = false
    if new_tab and not (default_tab and SB.current_tab_empty()) then
        SB.own_tab()
        reaper.Main_OnCommand(CMD_NEW_TAB_NO_TEMPLATE, 0)
        made_tab = true
    end

    local online_fx
    -- Reopening the open project with unsaved changes asks to save first.
    -- A real load comes back clean; still dirty means the prompt was
    -- cancelled, and read-only must not lock that unsaved session.
    local _, cur = reaper.EnumProjects(-1)
    local was_dirty = cur and SB.same_path(cur, item.path)
        and reaper.IsProjectDirty(0) == 1
    local dirty_before = reaper.IsProjectDirty(0) == 1
    local tabs_before = SB.tab_count()

    if item.kind == 'template' and mode ~= 'edit' then
        reaper.Main_openProject((offline and 'fxoffline:' or '')
            .. 'template:' .. item.path)
    elseif offline then
        -- REAPER's own recovery mode: every FX loads offline, so a plug-in
        -- that crashes on load can be found and removed. To bring them back
        -- afterwards, read the file first so a failed read falls back to a
        -- plain open instead of leaving everything offline.
        if online then online_fx = SB.rpp_online_fx(item.path) end
        reaper.Main_openProject((online and not online_fx and '' or 'fxoffline:')
            .. item.path)
    else
        reaper.Main_openProject(item.path)
    end

    -- A project that did not load leaves nothing behind but the empty tab
    -- made for it. A cancelled save prompt is not a failure: the old
    -- project is still there, untouched.
    if item.kind == 'project' and not opts.noverify
            and not SB.project_loaded(item.path) then
        local _, now = reaper.EnumProjects(-1)
        if dirty_before and not made_tab and reaper.IsProjectDirty(0) == 1
                and (cur or '') == (now or '') then
            return false, 'cancelled'
        end
        -- The tab made for it, or one REAPER opened on its own when the
        -- load failed, whichever left an empty tab in front.
        if (made_tab or SB.tab_count() > tabs_before)
                and SB.current_tab_empty() then
            reaper.Main_OnCommand(CMD_CLOSE_TAB, 0)
        end
        return false, 'not_loaded'
    end

    -- Read-only has no open prefix. Flag the project once it is loaded, the
    -- same state the Open dialog's "Open as read-only" leaves behind, but
    -- only if the project that loaded is the one asked for: a cancelled
    -- save prompt must not lock whatever was open before.
    if (readonly and reaper.GetSetProjectInfo) or online_fx then
        local proj, now = reaper.EnumProjects(-1)
        if now and ((opts.noverify and (mode ~= 'current' or now ~= cur))
                    or SB.same_path(now, item.path))
                and not (readonly and was_dirty
                    and reaper.IsProjectDirty(0) == 1) then
            if online_fx then
                SB.fx_online_add(SB.fx_online_job(online_fx, proj))
            end
            if readonly and reaper.GetSetProjectInfo then
                reaper.GetSetProjectInfo(0, 'READONLY', 1, true)
            end
        end
    end

    if mode == 'copy' then
        reaper.Main_OnCommand(CMD_SAVE_NEW_VERSION, 0)
    end
    if item.kind == 'template' then SB.mark_used(item.path) end
    if item.kind == 'project' then SB.unhide_recent(item.path) end
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

-- ReaImGui swaps Cmd and Ctrl on macOS, so Mod_Ctrl is Cmd there and Ctrl
-- everywhere else. Mod_Super on a Mac is the physical Control key.
local MOD_CMD = ImGui.Mod_Ctrl

local C = {}

SB.LOOKS = { 'dark', 'light', 'match' }
SB.LOOK_LABEL = 'Dark\0Light\0Match REAPER\0'

-- 'match' reads the REAPER theme's own window background, so a light theme
-- gets a light launcher without anyone opening Settings.
function SB.is_light()
    local look = SB.cfg.look
    if look == 'light' then return true end
    if look ~= 'match' or not reaper.GetThemeColor then return false end
    local native = reaper.GetThemeColor('col_main_bg2', 0)
    if not native or native < 0 then return false end
    local r, g, b = reaper.ColorFromNative(native)
    return 0.299 * r + 0.587 * g + 0.114 * b > 140
end

-- An accent picked for a dark background is too pale to read as text on a
-- light one. Step it darker until it is, keeping the hue.
function SB.ink_accent(rgb)
    local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    for _ = 1, 12 do
        if 0.299 * r + 0.587 * g + 0.114 * b <= 110 then break end
        r, g, b = math.floor(r * 0.9), math.floor(g * 0.9), math.floor(b * 0.9)
    end
    return (r << 16) | (g << 8) | b
end

function SB.build_palette()
    SB.style_dirty = true
    SB.theme = SB.theme_key()
    local a, source = SB.accent_for_theme(SB.theme)
    SB.accent_rgb = a
    SB.accent_source = source
    SB.light = SB.is_light()
    if SB.light then
        -- Same structure as dark, washes in black instead of white.
        SB.ink = 0x000000
        C.accent      = rgba(SB.ink_accent(a))
        C.accent_dim  = rgba(a, 0x33)
        C.accent_soft = rgba(a, 0x4D)
        C.text        = rgba(0x2B2C31)
        C.text_bright = rgba(0x111215)
        C.text_dim    = rgba(0x5E6069)
        C.text_faint  = rgba(0x8A8C94)
        C.win         = rgba(0xF3F3F5)
        C.child       = rgba(0xF3F3F5)
        C.popup       = rgba(0xFFFFFF)
        C.line        = rgba(0xDCDCE2)
        C.border      = rgba(0x000000, 0x30)
        C.dim_bg      = rgba(0x1E1E23, 0x40)
        C.warn        = rgba(0xC23B3B)
        C.folder      = rgba(0x3E8FDB)
    else
        -- Values below are the approved mockup, one for one.
        SB.ink = 0xFFFFFF
        C.accent      = rgba(a)
        C.accent_dim  = rgba(a, 0x29)   -- selected row / primary button, 16%
        C.accent_soft = rgba(a, 0x3D)
        C.text        = rgba(0xD2D4DA)
        C.text_bright = rgba(0xEFF1F4)
        C.text_dim    = rgba(0x9A9CA4)
        C.text_faint  = rgba(0x7C7E86)
        C.win         = rgba(0x232326)   -- one surface: window, rail, list, detail
        C.child       = rgba(0x232326)
        C.popup       = rgba(0x232326)
        C.line        = rgba(0x33333A)
        C.border      = rgba(0x000000, 0x8C)
        C.dim_bg      = rgba(0x000000, 0x88)
        C.warn        = rgba(0xFF8A8A)
        C.folder      = rgba(0x5AA9F0)
    end
    local ink = SB.ink
    C.frame       = rgba(ink, 0x0D)   -- search field, 5%
    C.frame_hover = rgba(ink, 0x14)
    C.button      = rgba(ink, 0x0F)   -- 6%
    C.button_hov  = rgba(ink, 0x18)
    C.tab_on      = rgba(ink, 0x12)   -- 7%
    C.ghost       = rgba(ink, 0x2E)   -- only while dragging a column edge
    C.row_hover   = rgba(ink, 0x0C)
    C.clear       = rgba(0x000000, 0x00)
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
    msel       = {},      -- paths of a multi-selection (empty = just S.sel)
    msel_n     = 0,
    chk_offline  = false, -- detail panel checks, cleared after each open
    chk_readonly = false,
    chk_online   = false,
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
    -- A search always shows the flat list of matches, tree or not.
    S.rows, S.row_of, S.flat = nil, nil, nil
    if SB.cfg.tree and S.view == 'folders' and S.query == '' then
        S.flat = S.shown
        S.rows, S.shown, S.row_of = SB.tree_flatten(
            SB.build_tree(S.flat), S.froot ~= nil)
    end
    local kept = SB.restore_sel()
    if S.rows and S.sel_path and kept == false then
        -- The selected project sits in a folder that is folded now. The
        -- number alone would land on an unrelated row: select nothing, and
        -- the project comes back selected when its folder opens again.
        S.sel = 0
    else
        if S.sel > #S.shown then S.sel = #S.shown end
        if S.sel < 1 then S.sel = 1 end
    end
    SB.sel_prune()
    S.dirty = false
end

local function selected()
    return S.shown[S.sel]
end

local function sel_reset()
    S.msel, S.msel_n = {}, 0
end

local function set_sel(index)
    S.sel = index
    S.sel_at = reaper.time_precise()
    local item = S.shown[index]
    S.sel_path = item and item.path or nil
end

-- One row, no multi-selection: what a plain click or arrow key does.
local function select_one(index)
    sel_reset()
    set_sel(index)
    S.anchor = index
end

-- Cmd/Ctrl+click: add the row to the selection, or take it out again.
local function sel_toggle(index)
    local item = S.shown[index]
    if not item then return end
    if S.msel_n == 0 then
        local cur = selected()
        if cur then S.msel[cur.path], S.msel_n = true, 1 end
    end
    if S.msel[item.path] then
        S.msel[item.path] = nil
        S.msel_n = S.msel_n - 1
    else
        S.msel[item.path] = true
        S.msel_n = S.msel_n + 1
    end
    set_sel(index)
    S.anchor = index
    if S.msel_n < 2 then
        -- One left is just the selection.
        local keep = next(S.msel)
        sel_reset()
        if keep then
            for j, it in ipairs(S.shown) do
                if it.path == keep then select_one(j) break end
            end
        end
    end
end

-- Shift+click and Shift+arrows: everything from the anchor to this row.
local function sel_range(index)
    local from = S.anchor or S.sel
    local lo, hi = math.min(from, index), math.max(from, index)
    sel_reset()
    for i = lo, hi do
        local item = S.shown[i]
        if item then S.msel[item.path], S.msel_n = true, S.msel_n + 1 end
    end
    set_sel(index)
    if S.msel_n < 2 then sel_reset() end
end

local function sel_all()
    sel_reset()
    if #S.shown < 2 then return end
    for _, item in ipairs(S.shown) do S.msel[item.path] = true end
    S.msel_n = #S.shown
end

-- The rows an action applies to, in list order.
function SB.sel_items()
    if S.msel_n < 2 then
        local item = selected()
        return item and { item } or {}
    end
    local out = {}
    for _, item in ipairs(S.shown) do
        if S.msel[item.path] then out[#out + 1] = item end
    end
    return out
end

-- Rows a filter or a reload took away are not selected any more.
function SB.sel_prune()
    if S.msel_n == 0 then return end
    local live, n = {}, 0
    for _, item in ipairs(S.shown) do
        if S.msel[item.path] then live[item.path], n = true, n + 1 end
    end
    S.msel, S.msel_n = live, n
    if n < 2 then sel_reset() end
end

-- After a filter or a sort the same project should stay selected.
function SB.restore_sel()
    if not S.sel_path then return end
    for i, item in ipairs(S.shown) do
        if item.path == S.sel_path then
            S.sel = i
            return true
        end
    end
    return false
end

local function move_sel(delta, extend)
    if #S.shown == 0 then return end
    local to = math.max(1, math.min(#S.shown, S.sel + delta))
    if extend then
        S.anchor = S.anchor or S.sel
        sel_range(to)
    else
        select_one(to)
    end
    S.scroll_to = true
end

-- Menu and button words for the default open and the other one.
local function open_labels()
    if SB.cfg.open_in == 'tab' then
        return 'Open in new tab', 'Open in current tab'
    end
    return 'Open', 'Open in new tab'
end

-- Anything that can open a REAPER dialog (Open, Save changes?, a missing
-- file box) waits until the frame is closed. On Windows REAPER keeps running
-- deferred scripts inside a modal dialog, so calling it mid-frame starts the
-- next frame while this one still has its child windows and styles open:
-- "ImGui_EndChild: Missing PopStyleVar()".
SB.queue = {}
function SB.later(fn) SB.queue[#SB.queue + 1] = fn end

local function run_later()
    local queue = SB.queue
    SB.queue = {}
    for _, fn in ipairs(queue) do fn() end
end

-- A REAPER dialog (Open file, a save prompt) must not find the launcher
-- still on screen, or both sit there stuck. The window is simply not drawn
-- for a couple of frames, then the command runs; see the loop.
local function run_command(cmd)
    SB.later(function() S.pending = { cmd = cmd, frames = 0 } end)
end

-- A plain open takes the two checks from the detail panel with it, and
-- clears them: nobody should stay stuck opening everything offline.
local function open_item(item, mode, forced)
    if not item then return end
    local opts = forced
    local plain = mode == nil or mode == 'current' or mode == 'tab'
    if item.kind == 'template' and plain and not forced then
        if S.chk_offline then opts = { offline = true } end
        S.chk_offline, S.chk_readonly, S.chk_online = false, false, false
    elseif item.kind == 'project' and plain and not forced then
        if S.chk_offline or S.chk_readonly then
            opts = { offline = S.chk_offline, readonly = S.chk_readonly,
                online = S.chk_offline and S.chk_online }
        end
        S.chk_offline, S.chk_readonly, S.chk_online = false, false, false
    end
    SB.later(function()
        local ok, why = SB.open(item, mode, opts)
        if ok then
            if not SB.cfg.keep_open then S.quit = true end
        elseif why == 'not_loaded' then
            local _, file = SB.split_path(item.path)
            S.dialog = {
                title = 'Could not open this project',
                line = file,
                buttons = {
                    { 'Show in folder', function()
                        SB.later(function() SB.reveal(item.path) end)
                    end },
                    { 'Close' },
                },
            }
        end
    end)
end

SB.MANY_ASK = 8
SB.UNDO_SECONDS = 8

-- Several projects always open in new tabs. The first one takes the empty
-- tab REAPER starts with, if that is what is in front of the user.
local function open_many(items, opts)
    opts = opts or {}
    local list = {}
    for _, item in ipairs(items) do
        if not item.missing then list[#list + 1] = item end
    end
    if #list == 0 then
        set_status('Nothing to open')
        return
    end
    local function go()
        SB.later(function()
            local opened, failed = 0, 0
            for n, item in ipairs(list) do
                local first = n == 1 and SB.current_tab_empty()
                local ok = SB.open(item, first and 'current' or 'tab', {
                    offline = opts.offline, readonly = opts.readonly,
                    online = opts.online })
                if ok then opened = opened + 1 else failed = failed + 1 end
            end
            if failed > 0 then
                set_status(('Could not open %d of %d'):format(failed, #list))
            end
            if opened > 0 and not SB.cfg.keep_open then S.quit = true end
        end)
    end
    if #list > SB.MANY_ASK then
        S.dialog = {
            title = ('Open %d projects?'):format(#list),
            line = 'Each one opens in its own tab.',
            buttons = { { ('Open %d'):format(#list), go, primary = true },
                { 'Cancel' } },
        }
    else
        go()
    end
end

local function do_open(mode)
    if S.msel_n > 1 then
        open_many(SB.sel_items())
        return
    end
    open_item(selected(), mode)
end

-- Taking projects out of Recent. They stay in REAPER's own list.
local function remove_recent(items)
    local list = {}
    for _, item in ipairs(items) do
        if item.kind == 'project' then list[#list + 1] = item end
    end
    if SB.hide_recent(list) == 0 then return end
    local paths = {}
    for i, item in ipairs(list) do paths[i] = item.path end
    S.undo = {
        paths = paths, at = reaper.time_precise(),
        label = #list == 1 and list[1].name or ('%d projects'):format(#list),
    }
    sel_reset()
    S.sel_path = nil
    SB.reload('recent')
end

local function undo_remove()
    local undo = S.undo
    if not undo then return end
    for _, path in ipairs(undo.paths) do SB.unhide_recent(path) end
    S.undo = nil
    SB.reload('recent')
end

local function restore_removed()
    SB.unhide_all()
    S.undo = nil
    SB.reload('recent')
end

-- Favorites for a whole selection: all of them on, or all of them off.
local function fav_many(items, want)
    for _, item in ipairs(items) do
        if (SB.fav_set[item.path] and true or false) ~= want then
            SB.fav_toggle(item.path)
        end
    end
    S.dirty = true
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------

local ctx = ImGui.CreateContext(SB.NAME)

-- ReaImGui drops a context that goes unused for a while, which is what
-- happens while the launcher sits in the background waiting for a new tab.
-- A fresh one is made when the window comes back.
function SB.new_context()
    ctx = ImGui.CreateContext(SB.NAME)
    SB.ctx_made = (SB.ctx_made or 0) + 1
    SB.clipper = ImGui.CreateListClipper(ctx)
    ImGui.Attach(ctx, SB.clipper)
    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 0)
end

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
        rgba(SB.ink, SB.light and 0x00 or 0x12), 1)
end

local function build_style()
    STYLE_C = {
        { ImGui.Col_WindowBg,        C.win },
        { ImGui.Col_ChildBg,         C.child },
        { ImGui.Col_PopupBg,         C.popup },
        { ImGui.Col_Text,            C.text },
        { ImGui.Col_TextDisabled,    C.text_dim },
        { ImGui.Col_Border,          C.border },
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
        -- ImGui dims with a square rect over the whole viewport, which pokes
        -- out past the rounded corners. settings_popup paints its own.
        { ImGui.Col_ModalWindowDimBg,  C.clear },
        { ImGui.Col_CheckMark,       C.accent },
        { ImGui.Col_TitleBgActive,   C.child },
        { ImGui.Col_ScrollbarGrab,   rgba(SB.ink, 0x1A) },
        { ImGui.Col_ScrollbarGrabHovered, rgba(SB.ink, 0x2A) },
        { ImGui.Col_ScrollbarBg,     C.clear },
        -- Back on the real corner of the window, where it can be grabbed.
        { ImGui.Col_ResizeGrip,        rgba(SB.ink, 0x16) },
        { ImGui.Col_ResizeGripHovered, rgba(SB.ink, 0x2E) },
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
    local mark = #SB.scopes
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then SB.unwind(mark) end
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

-- A rail toggle is the same filled button as Rescan, so it never reads as
-- loose text. On only turns the label blue.
local function pill_toggle(label, on, width)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0.5, 0.5)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, on and C.accent or C.text)
    local clicked = ImGui.Button(ctx, label, width or 0)
    ImGui.PopStyleColor(ctx, 2)
    ImGui.PopStyleVar(ctx)
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

-- Folder tree icons, drawn so there are no image assets to ship.
local function draw_chevron(dl, cx, cy, r, col, open)
    -- One stroked path, not two lines: two separate lines left a notch
    -- at the tip where their square ends met.
    ImGui.DrawList_PathClear(dl)
    if open then
        ImGui.DrawList_PathLineTo(dl, cx - r, cy - r * 0.5)
        ImGui.DrawList_PathLineTo(dl, cx, cy + r * 0.5)
        ImGui.DrawList_PathLineTo(dl, cx + r, cy - r * 0.5)
    else
        ImGui.DrawList_PathLineTo(dl, cx - r * 0.5, cy - r)
        ImGui.DrawList_PathLineTo(dl, cx + r * 0.5, cy)
        ImGui.DrawList_PathLineTo(dl, cx - r * 0.5, cy + r)
    end
    ImGui.DrawList_PathStroke(dl, col, 0, PX(1.8))
end

local function draw_folder_icon(dl, x, y, w, h, col)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w * 0.45, y + h * 0.4, col, PX(2))
    ImGui.DrawList_AddRectFilled(dl, x, y + h * 0.18, x + w, y + h, col, PX(2))
end

local function draw_doc_icon(dl, x, y, w, h, col)
    ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, col, PX(2), 0, PX(1.2))
    ImGui.DrawList_AddLine(dl, x + w * 0.25, y + h * 0.4, x + w * 0.75,
        y + h * 0.4, col, PX(1))
    ImGui.DrawList_AddLine(dl, x + w * 0.25, y + h * 0.65, x + w * 0.75,
        y + h * 0.65, col, PX(1))
end

-- Start of the NAME cell in the tree: indent, chevron (folders), icon.
-- Leaves the cursor where the text goes.
local function tree_lead(dl, depth, folder, open, hot)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local lh = ImGui.GetTextLineHeight(ctx)
    local x0 = x + PX(SB.TREE_INDENT * depth)
    local cy = y + lh / 2
    if folder then
        draw_chevron(dl, x0 + PX(8), cy, PX(3.6),
            hot and C.text_bright or C.text_dim, open)
        draw_folder_icon(dl, x0 + PX(22), cy - PX(6), PX(16), PX(12.5),
            C.folder)
    else
        draw_doc_icon(dl, x0 + PX(24), cy - PX(7), PX(11), PX(14),
            C.text_faint)
    end
    ImGui.Dummy(ctx, PX(SB.TREE_INDENT * depth + 50), 1)
    ImGui.SameLine(ctx, 0, 0)
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
        ('Type to search %d %s...'):format(
            S.flat and #S.flat or #S.shown, what), S.query)
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
        SB.later(function()
            local ok, folder = reaper.JS_Dialog_BrowseForFolder(
                'Folder with REAPER projects', '')
            if ok == 1 and folder ~= '' then take_root(folder) end
        end)
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
                SB.scan.partial = base
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
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0.5, 0.5)
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

    -- Lives here, always in the same place, instead of in the column
    -- header where it moved with the columns and covered them.
    if pill_toggle('Tree view', SB.cfg.tree, -1) then
        SB.cfg.tree = not SB.cfg.tree
        set_bool('tree', SB.cfg.tree)
        S.dirty = true
    end
    hint('Shows your folders as a tree')
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
            run_command(CMD_NEW_PROJECT)
        end
        hint('Empty project. ' .. SHORTCUT .. 'N')
        if ImGui.Button(ctx, 'New tab', -1) then
            run_command(CMD_NEW_TAB_NO_TEMPLATE)
        end
        hint('New tab, no template')
        if ImGui.Button(ctx, 'Open file...', -1) then
            run_command(CMD_OPEN_PROJECT)
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
            'Enter  ' .. (S.query ~= '' and 'open top match'
                or SB.main_open() == 'tab' and 'new tab' or 'open'),
            SHORTCUT .. 'Enter  '
                .. (SB.alt_open() == 'tab' and 'new tab' or 'current tab'),
            'Middle click  new tab',
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
    -- Find where the last character starts and drop it only if the cut left
    -- it incomplete. A whole accented letter at the end stays.
    local i = #out
    while i > 1 and out:byte(i) >= 0x80 and out:byte(i) < 0xC0 do
        i = i - 1
    end
    local lead = out:byte(i) or 0
    local need = lead >= 0xF0 and 4 or lead >= 0xE0 and 3
        or lead >= 0xC0 and 2 or 1
    if #out - i + 1 < need then out = out:sub(1, i - 1) end
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

-- The context menu for a selection of several rows.
local function draw_multi_menu()
    local items = SB.sel_items()
    local n = #items
    if ImGui.MenuItem(ctx, ('Open %d in new tabs'):format(n)) then
        open_many(items)
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, 'Open with FX offline') then
        open_many(items, { offline = true })
    end
    if items[1] and items[1].kind ~= 'template'
            and ImGui.MenuItem(ctx, 'Open read-only') then
        open_many(items, { readonly = true })
    end
    ImGui.Separator(ctx)
    local all = true
    for _, item in ipairs(items) do
        if not SB.fav_set[item.path] then all = false end
    end
    if ImGui.MenuItem(ctx, all and 'Remove from favorites'
            or 'Add to favorites') then
        fav_many(items, not all)
    end
    if S.view == 'recent' then
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, 'Remove from Recent', 'Delete') then
            SB.later(function() remove_recent(items) end)
        end
    end
end

-- One folder row of the tree. The whole row is the click target.
local function draw_tree_folder(dl, trow)
    local node = trow.folder
    ImGui.TableNextRow(ctx)
    list_font()
    ImGui.TableSetColumnIndex(ctx, 0)
    local clicked = ImGui.Selectable(ctx, '##dir' .. node.key, false,
        ImGui.SelectableFlags_SpanAllColumns)
    local hot = ImGui.IsItemHovered(ctx)
    if clicked then
        SB.tree_toggle(node)
        S.dirty = true
    end
    if ImGui.TableSetColumnIndex(ctx, 2) then
        tree_lead(dl, trow.depth, true, trow.open, hot)
        ImGui.TextColored(ctx, C.text_bright, node.name)
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, C.text_faint, ('%d'):format(node.count))
    end
end

local function draw_list(width, height)
    panel('list', width, height, PX(10), PX(8), function()
        ImGui.PushFont(ctx, nil, LFS(BASE_FONT))

        if #S.shown == 0 and not (S.rows and #S.rows > 0) then
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
            fade(rgba(SB.ink, 0x24), alpha))
        ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabHovered,
            fade(rgba(SB.ink, 0x38), alpha))
        ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabActive,
            fade(rgba(SB.ink, 0x4C), alpha))

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
        -- The time toggle is in the key too, so MODIFIED gets the width that
        -- fits what it shows.
        -- The tree has its own layout (no FOLDER column), so its own id.
        local tree_cols = SB.cfg.tree and S.view == 'folders'
        local table_id = ('items_v2#%s_%d_%d%s%s'):format(tostring(S.view),
            math.floor(SB.ui.scale * 100 + 0.5), math.floor(SB.ui.font * 100 + 0.5),
            SB.cfg.show_time and '_t' or '', tree_cols and '_tree' or '')
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
                ((tpl or tree_cols) and ImGui.TableColumnFlags_DefaultHide or 0), 38)
            ImGui.TableSetupColumn(ctx, 'MODIFIED',
                ImGui.TableColumnFlags_WidthFixed |
                ImGui.TableColumnFlags_PreferSortDescending |
                ((HAS_JS and not tpl) and 0
                    or ImGui.TableColumnFlags_DefaultHide),
                -- A year-first date has two more digits to fit.
                LPX((SB.cfg.show_time and 132 or 92)
                    + (SB.date_format():find('%Y', 1, true) and 16 or 0)))
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
                    if S.flat then S.dirty = true end
                    if not SB.sort_list(S.flat or S.shown, S.sort_col, S.sort_dir) then
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

            ImGui.ListClipper_Begin(SB.clipper, S.rows and #S.rows or #S.shown)
            if S.scroll_to and rawget(ImGui, 'ListClipper_IncludeItemByIndex') then
                ImGui.ListClipper_IncludeItemByIndex(SB.clipper,
                    (S.row_of and S.row_of[S.sel] or S.sel) - 1)
            end
            while ImGui.ListClipper_Step(SB.clipper) do
                local first, last = ImGui.ListClipper_GetDisplayRange(SB.clipper)
                for row = first, last - 1 do
                    local i = row + 1
                    local trow = S.rows and S.rows[i]
                    if trow then
                        i = trow.idx
                        if trow.folder then
                            draw_tree_folder(dl, trow)
                        end
                    end
                    local item = i and S.shown[i]
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
                        local is_sel = S.sel == i or S.msel[item.path] ~= nil
                        if ImGui.Selectable(ctx, '##' .. item.path, is_sel,
                                sel_flags) then
                            -- A click on the star toggles instead of selecting.
                            -- the whole first column counts as the star
                            if ImGui.GetMousePos(ctx) <
                                    star_x + cell_w + PX(CELL_PAD_X) then
                                SB.fav_toggle(item.path)
                                S.dirty = true
                            else
                                local mods = ImGui.GetKeyMods(ctx)
                                if mods & MOD_CMD ~= 0 then
                                    sel_toggle(i)
                                elseif mods & ImGui.Mod_Shift ~= 0 then
                                    sel_range(i)
                                else
                                    select_one(i)
                                    if ImGui.IsMouseDoubleClicked(ctx, 0) then
                                        do_open(SB.main_open())
                                    end
                                end
                            end
                        end
                        local row_hot = ImGui.IsItemHovered(ctx)
                        -- Middle click always means a new tab, whatever
                        -- Settings says about Enter.
                        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Middle) then
                            select_one(i)
                            open_item(item, 'tab')
                        end
                        if is_sel then
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
                        if S.msel_n > 1 and S.msel[item.path] then
                            -- Right click inside a selection acts on all of it.
                            if ImGui.BeginPopupContextItem(ctx) then
                                draw_multi_menu()
                                ImGui.EndPopup(ctx)
                                list_font()
                            end
                        elseif ImGui.BeginPopupContextItem(ctx) then
                            select_one(i)
                            local main_label, alt_label = open_labels()
                            if ImGui.MenuItem(ctx, main_label) then
                                do_open(SB.main_open())
                            end
                            if ImGui.MenuItem(ctx, alt_label) then
                                do_open(SB.alt_open())
                            end
                            if item.kind == 'project' then
                                if ImGui.MenuItem(ctx, 'Open as new version') then
                                    do_open('copy')
                                end
                                ImGui.Separator(ctx)
                                if ImGui.MenuItem(ctx, 'Open with FX offline') then
                                    do_open('offline')
                                end
                                if ImGui.MenuItem(ctx, 'Bring FX online after load') then
                                    do_open('online')
                                end
                                if ImGui.MenuItem(ctx, 'Open read-only') then
                                    do_open('readonly')
                                end
                            elseif item.kind == 'template' then
                                if ImGui.MenuItem(ctx, 'Open with FX offline') then
                                    do_open('offline')
                                end
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
                                SB.later(function() SB.reveal(item.path) end)
                            end
                            if S.view == 'recent' and item.kind == 'project' then
                                ImGui.Separator(ctx)
                                if ImGui.MenuItem(ctx, 'Remove from Recent',
                                        'Delete') then
                                    SB.later(function() remove_recent({ item }) end)
                                end
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
                            if trow then tree_lead(dl, trow.depth, false) end
                            if item.missing then
                                ImGui.TextColored(ctx, C.warn, '! ' .. item.name)
                            elseif is_sel then
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
                                and SB.relative_date(when, SB.cfg.show_time)
                                or '-', C.text_dim)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 5) then
                            SB.value_of(item, 5)
                            right_text(item.size and SB.human_size(item.size)
                                or '-', C.text_dim)
                        end

                        if ImGui.TableSetColumnIndex(ctx, 6) then
                            SB.value_of(item, 6)
                            right_text(item.bpm and SB.fmt_tempo(item.bpm)
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

-- The panel while several rows are selected.
local function draw_multi_detail()
    local items = SB.sel_items()
    local n = #items
    local tpl = items[1] and items[1].kind == 'template'
    local rows = S.view == 'recent' and 3 or 2
    local avail_h = select(2, ImGui.GetContentRegionAvail(ctx))
    local gap = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
    local buttons_h = ImGui.GetFrameHeight(ctx) * rows + gap * (rows - 1)
    local info_h = avail_h - buttons_h - gap

    local room = info_h > ImGui.GetTextLineHeight(ctx)
    if room and ImGui.BeginChild(ctx, 'selected', 0, info_h) then
        ImGui.PushFont(ctx, nil, FS(15))
        ImGui.TextWrapped(ctx, ('%d %s selected'):format(n,
            tpl and 'templates' or 'projects'))
        ImGui.PopFont(ctx)
        ImGui.Dummy(ctx, 1, PX(4))
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 1, PX(2))
        local w = ImGui.GetContentRegionAvail(ctx)
        for _, item in ipairs(items) do
            ImGui.TextColored(ctx, C.text_dim, SB.fit_text(item.name, w))
        end
    end
    if room then ImGui.EndChild(ctx) end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
    if ImGui.Button(ctx, ('Open %d in new tabs'):format(n), -1) then
        open_many(items)
    end
    hint('Enter')
    ImGui.PopStyleColor(ctx, 3)

    local all = true
    for _, item in ipairs(items) do
        if not SB.fav_set[item.path] then all = false end
    end
    if ImGui.Button(ctx, all and 'Remove from favorites' or 'Add to favorites',
            -1) then
        fav_many(items, not all)
    end
    hint(SHORTCUT .. 'D')
    if S.view == 'recent' then
        if ImGui.Button(ctx, 'Remove from Recent', -1) then
            SB.later(function() remove_recent(items) end)
        end
        hint('Delete. Stays in File > Recent projects')
    end
end

-- One row that opens something: the label on the left, a count on the right.
local function link_row(key, value, id)
    local w = ImGui.GetWindowWidth(ctx)
    local tw = ImGui.CalcTextSize(ctx, value)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text_faint)
    local hit = ImGui.Selectable(ctx, key .. '##' .. id)
    ImGui.PopStyleColor(ctx)
    ImGui.SameLine(ctx, w - tw - PX(16))
    ImGui.TextColored(ctx, C.accent, value)
    return hit
end

-- Label/value pairs in two columns. An entry is { key, value } or
-- { key, value, id, tip } for a row that opens something; returns the id of
-- the one clicked. When any pair would not fit its half, falls back to the
-- one-column rows so nothing is drawn over its label.
local function kv_grid(left, right)
    local avail = ImGui.GetContentRegionAvail(ctx)
    -- What each column needs: its widest label + value, plus a small gap.
    local need = {}
    for c, list in ipairs({ left, right }) do
        need[c] = 0
        for _, e in ipairs(list) do
            need[c] = math.max(need[c], ImGui.CalcTextSize(ctx, e[1])
                + ImGui.CalcTextSize(ctx, e[2]) + PX(10))
        end
    end
    -- Two equal halves when both fit. Otherwise the wider column takes what
    -- it needs and the other gets the rest: a long tempo or time signature
    -- no longer drops the whole grid to one column. One column only when
    -- the panel truly cannot hold both.
    local gap = PX(14)
    local col_ws = { (avail - gap) / 2, (avail - gap) / 2 }
    local fits = need[1] <= col_ws[1] and need[2] <= col_ws[2]
    if not fits then
        gap = PX(8)
        local extra = avail - gap - need[1] - need[2]
        if extra >= 0 then
            col_ws = { need[1] + extra / 2, need[2] + extra / 2 }
            fits = true
        end
    end
    local hit
    if not fits then
        for _, list in ipairs({ left, right }) do
            for _, e in ipairs(list) do
                if e[3] then
                    if link_row(e[1], e[2], e[3]) then hit = e[3] end
                    if e[4] then hint(e[4]) end
                else
                    kv(e[1], e[2])
                end
            end
        end
        return hit
    end
    local x0 = ImGui.GetCursorPosX(ctx)
    for i = 1, math.max(#left, #right) do
        for c, list in ipairs({ left, right }) do
            local e = list[i]
            local col_w = col_ws[c]
            local cx = x0 + (c - 1) * (col_ws[1] + gap)
            if e then
                if c == 2 and left[i] then
                    ImGui.SameLine(ctx, cx)
                else
                    ImGui.SetCursorPosX(ctx, cx)
                end
                local vw = ImGui.CalcTextSize(ctx, e[2])
                if e[3] then
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text_faint)
                    if ImGui.Selectable(ctx, e[1] .. '##' .. e[3], false, 0,
                            col_w, 0) then
                        hit = e[3]
                    end
                    ImGui.PopStyleColor(ctx)
                    if e[4] then hint(e[4]) end
                else
                    ImGui.TextColored(ctx, C.text_faint, e[1])
                end
                ImGui.SameLine(ctx, cx + col_w - vw)
                ImGui.TextColored(ctx, e[3] and C.accent or C.text, e[2])
            end
        end
    end
    return hit
end

-- The panel while the list of a project's backups is showing.
local function draw_backups(item)
    local list = SB.backups_of(item.path)
    local bk = S.bk
    local chosen
    if bk.sel > #list then bk.sel = math.max(1, #list) end
    local avail_h = select(2, ImGui.GetContentRegionAvail(ctx))
    local gap = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
    local buttons_h = ImGui.GetFrameHeight(ctx)
    local info_h = avail_h - buttons_h - gap

    local room = info_h > ImGui.GetTextLineHeight(ctx)
    if room and ImGui.BeginChild(ctx, 'backups', 0, info_h) then
        if ImGui.SmallButton(ctx, 'Back') then S.bk = nil end
        ImGui.PushFont(ctx, nil, FS(15))
        ImGui.TextWrapped(ctx, item.name)
        ImGui.PopFont(ctx)
        ImGui.TextColored(ctx, C.text_faint,
            ('%d %s'):format(#list, #list == 1 and 'backup' or 'backups'))
        ImGui.Dummy(ctx, 1, PX(2))
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 1, PX(2))
        local w = ImGui.GetWindowWidth(ctx)
        for i, e in ipairs(list) do
            if e.size == nil then e.size = SB.file_size(e.path) or false end
            local label = SB.when_label(e.t)
            if ImGui.Selectable(ctx, label .. '##bk' .. i, bk.sel == i,
                    ImGui.SelectableFlags_AllowDoubleClick) then
                bk.sel = i
                if ImGui.IsMouseDoubleClicked(ctx, 0) then bk.open = true end
            end
            push_menu_style()
            if ImGui.BeginPopupContextItem(ctx) then
                bk.sel = i
                if ImGui.MenuItem(ctx, 'Open in new tab') then
                    chosen = { e, 'tab' }
                end
                if ImGui.MenuItem(ctx, 'Open in current tab') then
                    chosen = { e, 'current' }
                end
                ImGui.Separator(ctx)
                if ImGui.MenuItem(ctx, 'Open with FX offline') then
                    chosen = { e, 'tab', true }
                end
                if ImGui.MenuItem(ctx, 'Bring FX online after load') then
                    chosen = { e, 'tab', true, true }
                end
                ImGui.Separator(ctx)
                if ImGui.MenuItem(ctx, 'Show in folder') then
                    local path = e.path
                    SB.later(function() SB.reveal(path) end)
                end
                ImGui.EndPopup(ctx)
            end
            pop_menu_style()
            local size = e.size and SB.human_size(e.size) or ''
            ImGui.SameLine(ctx, w - ImGui.CalcTextSize(ctx, size) - PX(16))
            ImGui.TextColored(ctx, C.text_faint, size)
        end
    end
    if room then ImGui.EndChild(ctx) end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
    local go = ImGui.Button(ctx, 'Open in new tab', -1)
    ImGui.PopStyleColor(ctx, 3)
    hint('Opens read-only, so the backup is never overwritten')
    local e = list[bk.sel]
    if (go or bk.open) and e then chosen = { e, 'tab' } end
    if chosen then
        -- Every way in stays read-only: a backup is never saved over.
        local _, file = SB.split_path(chosen[1].path)
        open_item({ kind = 'project', path = chosen[1].path, name = file },
            chosen[2], { readonly = true, noverify = true,
                offline = chosen[3], online = chosen[4] })
    end
    bk.open = nil
end

-- Round Play/Stop at the start of the player row, under the name and path.
-- Name and path always sit on top, the same with or without a preview, so
-- they keep the full width. Returns the button size so the bar matches it.
local function draw_prox_button(item, prox)
    local d = PX(26)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, '##proxplay', d, d)
    local hot = ImGui.IsItemHovered(ctx)
    local playing = SB.px.id ~= nil and SB.px.item == item.path
    hint(playing and 'Stops the preview'
        or 'Plays the preview file saved with this project (.RPP-PROX)')
    local dl = ImGui.GetWindowDrawList(ctx)
    local cx, cy, r = x + d / 2, y + d / 2, d / 2
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, r,
        hot and C.button_hov or C.button, 32)
    if playing then
        local q = r * 0.34
        ImGui.DrawList_AddRectFilled(dl, cx - q, cy - q, cx + q, cy + q,
            C.accent, PX(1.5))
    else
        local q = r * 0.42
        ImGui.DrawList_AddTriangleFilled(dl, cx - q * 0.7, cy - q,
            cx - q * 0.7, cy + q, cx + q, cy, C.text)
    end

    if clicked then
        if playing then SB.prox_stop()
        elseif not SB.prox_start(item.path, prox, 0) then
            set_status('Could not play the preview')
        end
    end
    return d
end

-- A bar that jumps where you click, with the time at its end. The time is
-- always there (dim when stopped), so nothing moves when Play starts.
local function draw_prox_bar(item, prox, len, row_h)
    local playing = SB.px.id ~= nil and SB.px.item == item.path
    local pos = playing and SB.prox_pos() or 0
    playing = SB.px.id ~= nil and SB.px.item == item.path
    local dur = len

    ImGui.PushFont(ctx, nil, FS(11))
    -- Every digit sits in a cell as wide as the widest digit, and the
    -- current time is padded to the length of the total: the font's digits
    -- are not all the same width, so plain text shifted as it counted up.
    local total = SB.clock(dur)
    local now = SB.clock(pos)
    now = (' '):rep(math.max(0, #total - #now)) .. now
    local cell = 0
    for d = 0, 9 do
        cell = math.max(cell, (ImGui.CalcTextSize(ctx, tostring(d))))
    end
    local sep = ' / '
    local function width_of(str)
        local w = 0
        for ch in str:gmatch('.') do
            w = w + ((ch:match('[%d ]')) and cell or ImGui.CalcTextSize(ctx, ch))
        end
        return w
    end
    local time_w = width_of(now) + ImGui.CalcTextSize(ctx, sep) + width_of(total)
    -- A little room on the right: the panel edge clipped the last digit.
    local right_pad = PX(6)
    local avail = ImGui.GetContentRegionAvail(ctx)
    local bar_w = math.max(PX(20), avail - time_w - right_pad - PX(10))
    local bar_h = row_h or ImGui.GetTextLineHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, '##proxbar', bar_w, bar_h)
    local hot = ImGui.IsItemHovered(ctx)
    hint('Click to jump to that point')
    local dl = ImGui.GetWindowDrawList(ctx)
    local mid = y + bar_h / 2
    ImGui.DrawList_AddRectFilled(dl, x, mid - PX(2), x + bar_w, mid + PX(2),
        C.button_hov, PX(2))
    local frac = (dur > 0) and math.max(0, math.min(1, pos / dur)) or 0
    ImGui.DrawList_AddRectFilled(dl, x, mid - PX(2), x + bar_w * frac,
        mid + PX(2), C.accent, PX(2))
    if playing or hot then
        ImGui.DrawList_AddRectFilled(dl, x + bar_w * frac - PX(3), mid - PX(5),
            x + bar_w * frac + PX(3), mid + PX(5), C.accent, PX(3))
    end
    local col = playing and C.text_dim or C.text_faint
    local tx = x + avail - right_pad - time_w
    local ty = y + (bar_h - ImGui.GetTextLineHeight(ctx)) / 2
    local function draw_cells(str)
        for ch in str:gmatch('.') do
            if ch:match('[%d ]') then
                if ch ~= ' ' then
                    local cw = ImGui.CalcTextSize(ctx, ch)
                    ImGui.DrawList_AddText(dl, tx + (cell - cw) / 2, ty, col, ch)
                end
                tx = tx + cell
            else
                ImGui.DrawList_AddText(dl, tx, ty, col, ch)
                tx = tx + ImGui.CalcTextSize(ctx, ch)
            end
        end
    end
    draw_cells(now)
    ImGui.DrawList_AddText(dl, tx, ty, col, sep)
    tx = tx + ImGui.CalcTextSize(ctx, sep)
    draw_cells(total)
    ImGui.PopFont(ctx)
    if clicked then
        local mx = ImGui.GetMousePos(ctx)
        local want = math.max(0, math.min(1, (mx - x) / math.max(1, bar_w)))
        if not SB.prox_start(item.path, prox, want) then
            set_status('Could not play the preview')
        end
    end
end

local function draw_detail(width, height)
    panel('detail', width, height, PX(12), PX(9), function()
        if S.msel_n > 1 then
            draw_multi_detail()
            return
        end
        local item = selected()
        if not item then
            ImGui.TextColored(ctx, C.text_dim, 'Nothing selected.')
            return
        end
        if S.bk and S.bk.path ~= item.path then S.bk = nil end
        if S.bk then
            draw_backups(item)
            return
        end

        -- The four actions are the point of this panel, so their strip is
        -- reserved first and everything above it lives in a box that scrolls.
        -- Before this, a long name plus a full set of metadata simply pushed
        -- the buttons past the bottom edge, where they could not be clicked.
        local tpl = item.kind == 'template'
        local CHK_PAD = PX(2)
        local avail_h   = select(2, ImGui.GetContentRegionAvail(ctx))
        local gap       = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
        -- A template puts Open on its own line and the other three on one
        -- row underneath: two rows instead of four, which is most of the
        -- height the track list needed.
        local rows = tpl and 2 or 4
        -- Two checks and a third that follows FX offline, above the buttons.
        -- Side by side when the panel is wide enough, else one to a line.
        local checks = item.kind == 'project' or tpl
        local space_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
        -- Small boxes, the size of the text: full-height frames made the
        -- three checks taller than the buttons under them.
        local chk_h = ImGui.GetTextLineHeight(ctx) + CHK_PAD * 2
        local one_line = false
        local checks_h = 0
        if checks then
            local need = chk_h * 2 + space_x * 4
                + ImGui.CalcTextSize(ctx, 'FX offline')
                + ImGui.CalcTextSize(ctx, 'Read-only')
            one_line = need <= ImGui.GetContentRegionAvail(ctx)
            -- A template opens as a new project: nothing to lock, and no
            -- saved FX state to bring back. FX offline is its only check.
            local n = tpl and 1 or one_line and 2 or 3
            checks_h = (chk_h + gap) * n
        end
        local buttons_h = ImGui.GetFrameHeight(ctx) * rows + gap * (rows - 1)
        local info_h    = avail_h - buttons_h - checks_h - gap

        local room = info_h > ImGui.GetTextLineHeight(ctx)
        if room and ImGui.BeginChild(ctx, 'info', 0, info_h) then
            -- A project with a playable preview gets one row under the
            -- path: round Play, the bar and the time. Name and path stay
            -- on top at full width, with or without a preview.
            -- The lookup waits for the row to settle, like the metadata, so
            -- holding Down through the list does not open every PROX. A
            -- project already looked up shows its player at once. Until then
            -- only name and path draw; the player row appears once, a
            -- moment after the row settles.
            local settled = SB.meta_cache[item.path] ~= nil or
                reaper.time_precise() - (S.sel_at or 0) > 0.12
            local prox = nil
            if item.kind == 'project' and not item.missing
                    and SB.prox_available()
                    and (settled or SB.px_found[item.path] ~= nil) then
                prox = SB.prox_for(item.path)
            end
            local prox_len = prox and (settled or SB.px_len[prox] ~= nil)
                and SB.prox_len(prox)
            if not prox_len then prox = nil end
            ImGui.PushFont(ctx, nil, FS(15))
            ImGui.TextWrapped(ctx, item.name)
            ImGui.PopFont(ctx)

            ImGui.PushFont(ctx, nil, FS(11))
            -- One line, trimmed from the front: the folder it is in is
            -- the part that identifies it. The whole path is one hover
            -- away in the status bar.
            local pw = ImGui.GetContentRegionAvail(ctx)
            ImGui.TextColored(ctx, C.text_faint,
                SB.fit_text(item.dir, pw, true))
            hint(item.dir)
            ImGui.PopFont(ctx)

            -- Player row: round Play, the bar, the time, all on one line.
            if prox then
                ImGui.Dummy(ctx, 1, PX(2))
                local d = draw_prox_button(item, prox)
                ImGui.SameLine(ctx, 0, PX(10))
                draw_prox_bar(item, prox, prox_len, d)
            end

            ImGui.Dummy(ctx, 1, PX(4))
            ImGui.Separator(ctx)
            ImGui.Dummy(ctx, 1, PX(2))

            if item.when == nil then item.when = SB.file_mtime(item.path) or false end

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
                            bits[#bits + 1] = SB.fmt_tempo(meta.tempo) .. ' BPM'
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
                    -- Two columns: the project's shape on the left, what is
                    -- in it on the right. Half the height of one list.
                    local left, right = {}, {}
                    if meta.tempo then
                        left[#left + 1] = { 'Tempo', SB.fmt_tempo(meta.tempo) }
                        left[#left + 1] = { 'Time',
                            ('%d/%d'):format(meta.num or 4, meta.den or 4) }
                    end
                    if meta.length and meta.length > 0 then
                        left[#left + 1] = { 'Length', SB.human_time(meta.length) }
                    end
                    if meta.srate then
                        left[#left + 1] = { 'Rate',
                            ('%gk'):format(math.floor(meta.srate / 100 + 0.5) / 10) }
                    end
                    right[#right + 1] = { 'Tracks', tostring(meta.tracks) }
                    right[#right + 1] = { 'Items', tostring(meta.items) }
                    -- Only listed once the row has settled, and cached per
                    -- project, so moving through the list never lists a folder
                    -- more than once.
                    local backups = item.kind == 'project'
                        and SB.backups_of(item.path) or {}
                    if #backups > 0 then
                        right[#right + 1] = { 'Backups', tostring(#backups), 'bk',
                            'Shows the saved backups of this project' }
                    end
                    if kv_grid(left, right) == 'bk' then
                        S.bk = { path = item.path, sel = 1 }
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

        if checks then
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, CHK_PAD, CHK_PAD)
            local rv1, off = ImGui.Checkbox(ctx, 'FX offline', S.chk_offline)
            if rv1 then
                S.chk_offline = off
                if not off then S.chk_online = false end
            end
            hint('Loads every plug-in offline. For a project that crashes')
            if not tpl then
                if one_line then ImGui.SameLine(ctx) end
                local rv2, ro = ImGui.Checkbox(ctx, 'Read-only', S.chk_readonly)
                if rv2 then S.chk_readonly = ro end
                hint('Opens it locked, so nothing can be saved over it')
                ImGui.BeginDisabled(ctx, not S.chk_offline)
                local rv3, on = ImGui.Checkbox(ctx, 'Bring online after load',
                    S.chk_offline and S.chk_online)
                if rv3 then S.chk_online = on end
                ImGui.EndDisabled(ctx)
                hint('Needs FX offline. The plug-ins come back once it has loaded')
            end
            ImGui.PopStyleVar(ctx)
        end

        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
        local main_label, alt_label = open_labels()
        if ImGui.Button(ctx, main_label, -1) then do_open(SB.main_open()) end
        hint('Enter')
        ImGui.PopStyleColor(ctx, 3)

        if tpl then
            -- Three short buttons on one row: the words are shorter than
            -- the height a second and third full row would cost.
            local gap_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
            local third = (ImGui.GetContentRegionAvail(ctx) - gap_x * 2) / 3
            local short = SB.alt_open() == 'tab' and 'New tab' or 'This tab'
            if ImGui.Button(ctx, short, third) then do_open(SB.alt_open()) end
            hint(alt_label .. '. ' .. SHORTCUT .. 'Enter')
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, 'Edit', third) then do_open('edit') end
            hint('Opens the template file itself, to change it')
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, 'Folder', third) then
                SB.later(function() SB.reveal(item.path) end)
            end
            hint('Shows the file in Finder')
        else
            if ImGui.Button(ctx, alt_label, -1) then do_open(SB.alt_open()) end
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
    local shown, total = S.flat and #S.flat or #S.shown, #S.items
    local text
    local undoing = S.undo and not S.hint
        and reaper.time_precise() - S.undo.at < SB.UNDO_SECONDS
    if S.hint and S.hint ~= '' then
        text = S.hint
    elseif undoing then
        text = 'Removed ' .. S.undo.label
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
    if not S.hint and not undoing and S.msel_n > 1 then
        text = ('%s   %d selected'):format(text, S.msel_n)
    end
    if not S.hint and not undoing and SB.cfg.hide_missing
            and S.view == 'recent' then
        local gone = 0
        for _, item in ipairs(S.items) do
            if item.missing then gone = gone + 1 end
        end
        if gone > 0 then
            text = ('%s   %d missing hidden'):format(text, gone)
        end
    end
    -- Clickable words at the end of the line: Undo right after a removal,
    -- then how many are out of the list, to bring them back.
    local link
    if undoing then
        link = 'Undo'
    elseif not S.hint and S.view == 'recent' and (SB.removed_n or 0) > 0 then
        link = ('%d removed'):format(SB.removed_n)
    end
    -- SameLine takes an absolute offset, so a status line wider than the
    -- space left over would make the cursor jump backwards and the size
    -- buttons would be painted on top of the text. Trim the text instead.
    local pct = ('%d%%'):format(math.floor(SB.ui.scale * 100 + 0.5))
    local bar_w = PX(16) * 6 + ImGui.CalcTextSize(ctx, '|')
        + ImGui.CalcTextSize(ctx, '-') + ImGui.CalcTextSize(ctx, '+')
        + ImGui.CalcTextSize(ctx, pct)
        + ImGui.CalcTextSize(ctx, 'A') * (10 / 12 + 16 / 12)
    local link_w = link and (ImGui.CalcTextSize(ctx, link) + PX(16)) or 0
    text = SB.fit_text(text, content_w - bar_w - PX(10) - link_w)
    -- The buttons on the right are frame-height; the text is not. Drop it
    -- by half the difference so the whole row reads as one line.
    local drop = (ImGui.GetFrameHeight(ctx) - ImGui.GetTextLineHeight(ctx)) / 2
    local text_y = ImGui.GetCursorPosY(ctx)
    ImGui.SetCursorPosY(ctx, text_y + drop)
    ImGui.TextColored(ctx, C.text_faint, text)
    if link then
        ImGui.SameLine(ctx, 0, PX(12))
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.clear)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.clear)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
        if ImGui.SmallButton(ctx, link .. '##restore') then
            SB.later(undoing and undo_remove or restore_removed)
        end
        ImGui.PopStyleColor(ctx, 3)
    end
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

    local rvw, watch = ImGui.Checkbox(ctx, 'Show on every new empty tab',
        SB.cfg.watch_tabs)
    if rvw then
        SB.cfg.watch_tabs = watch
        set_bool('watch_tabs', watch)
    end
    hint('Stays in the background once closed. Run it again to bring it back')

    if SB.startup_prompt_conflict() then
        ImGui.Dummy(ctx, 1, PX(2))
        ImGui.TextColored(ctx, C.warn,
            'REAPER also shows its own project prompt at startup.')
        if ImGui.Button(ctx, 'Turn REAPER\'s prompt off') then
            SB.fix_startup_prompt()
        end
    end

    ImGui.Dummy(ctx, 1, PX(4))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(2))
    ImGui.TextColored(ctx, C.text_faint, 'LAUNCHER')

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

    -- Two words, both always visible: a dropdown would hide the other one.
    local pad_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
    local gap_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local seg = { { 'current', 'Current tab' }, { 'tab', 'New tab' } }
    local seg_w = gap_x
    for _, s in ipairs(seg) do
        s[3] = ImGui.CalcTextSize(ctx, s[2]) + pad_x * 2
        seg_w = seg_w + s[3]
    end
    setting_row('Open projects in', seg_w)
    for n, s in ipairs(seg) do
        if n > 1 then ImGui.SameLine(ctx) end
        local on = SB.main_open() == s[1]
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, on and C.tab_on or C.clear)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
            on and C.tab_on or C.button)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_hov)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text,
            on and C.accent or C.text_dim)
        if ImGui.Button(ctx, s[2], s[3]) then
            SB.cfg.open_in = s[1]
            set_ext('open_in', s[1])
        end
        ImGui.PopStyleColor(ctx, 4)
        hint(s[1] == 'tab'
            and 'Enter opens in a new tab, ' .. SHORTCUT
                .. 'Enter in the current one'
            or 'Enter opens in the current tab, ' .. SHORTCUT
                .. 'Enter in a new one')
    end

    local rvk, keep = ImGui.Checkbox(ctx,
        'Keep the window open after opening a project', SB.cfg.keep_open)
    if rvk then
        SB.cfg.keep_open = keep
        set_bool('keep_open', keep)
    end
    hint('Off means it closes as soon as a project opens')

    local rvc, check = ImGui.Checkbox(ctx,
        'Check folders for changes on open', SB.cfg.check_open)
    if rvc then
        SB.cfg.check_open = check
        set_bool('check_open', check)
    end
    hint('Looks for new, removed or changed projects in your folders and rescans only if it finds any')

    ImGui.Dummy(ctx, 1, PX(4))
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 1, PX(2))
    ImGui.TextColored(ctx, C.text_faint, 'APPEARANCE')

    -- Theme and accent share a row: the swatch sits after the dropdown, and
    -- Reset (only for a custom accent) goes in front of it.
    local custom = SB.accent_source == 'custom'
    local reset_w = custom
        and ImGui.CalcTextSize(ctx, 'Reset') + pad_x * 2 + gap_x or 0
    setting_row('Theme', reset_w + PX(150) + gap_x + PX(24))
    if custom then
        if ImGui.Button(ctx, 'Reset') then
            SB.clear_accent_override(SB.theme)
            SB.build_palette()
        end
        hint('Back to the accent color of the current theme')
        ImGui.SameLine(ctx)
    end
    ImGui.SetNextItemWidth(ctx, PX(150))
    local look_at = 1
    for i, v in ipairs(SB.LOOKS) do
        if v == SB.cfg.look then look_at = i end
    end
    local rvl, pick_look = ImGui.Combo(ctx, '##look', look_at - 1,
        SB.LOOK_LABEL)
    if rvl then
        SB.cfg.look = SB.LOOKS[pick_look + 1] or 'dark'
        set_ext('look', SB.cfg.look)
        SB.build_palette()
    end
    hint('Match REAPER picks light or dark from your REAPER theme')

    ImGui.SameLine(ctx)
    local rva, picked = ImGui.ColorEdit3(ctx, '##accent',
        SB.accent_rgb or 0,
        ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoTooltip)
    if rva then
        SB.set_accent_override(SB.theme, picked)
        SB.build_palette()
    end
    hint('Accent: ' .. (({
        theme      = 'from your theme',
        reapertips = 'theme default',
        default    = 'theme default',
        fallback   = 'default, theme color too dark',
        custom     = 'custom',
    })[SB.accent_source] or '?') .. '. Click to pick another')

    local rvt, show_time = ImGui.Checkbox(ctx,
        'Show the time in the Modified column', SB.cfg.show_time)
    if rvt then
        SB.cfg.show_time = show_time
        set_bool('show_time', show_time)
    end
    hint('Adds the hour and minute next to each date')
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
    -- No background or border of its own: both are painted below, after
    -- the rounded dim, so the dim sits behind the dialog and not on it.
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, C.clear)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
    local open = ImGui.BeginPopupModal(ctx, 'Settings##sb', nil,
        ImGui.WindowFlags_AlwaysAutoResize)
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx)
    if not open then
        S.settings_open = false
        return
    end

    local dl = ImGui.GetWindowDrawList(ctx)
    local round = PX(12)
    if S.win_x then
        local x2, y2 = S.win_x + (S.win_w or 0), S.win_y + (S.win_h or 0)
        ImGui.DrawList_PushClipRect(dl, S.win_x, S.win_y, x2, y2, false)
        ImGui.DrawList_AddRectFilled(dl, S.win_x, S.win_y, x2, y2,
            C.dim_bg, round)
        ImGui.DrawList_PopClipRect(dl)
    end
    local px, py = ImGui.GetWindowPos(ctx)
    local pw, ph = ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddRectFilled(dl, px, py, px + pw, py + ph, C.popup, round)
    ImGui.DrawList_AddRect(dl, px, py, px + pw, py + ph, C.border, round)

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

-- A small message with a few buttons, on top of the window. Escape and
-- clicking any button close it.
local function draw_dialog()
    local d = S.dialog
    if not d then return end
    local id = 'Project Launcher##dialog'
    if not d.shown then
        ImGui.OpenPopup(ctx, id)
        d.shown = true
    end
    if S.win_x then
        ImGui.SetNextWindowPos(ctx, S.win_x + (S.win_w or 0) / 2,
            S.win_y + (S.win_h or 0) / 2, ImGui.Cond_Appearing, 0.5, 0.5)
    end
    ImGui.SetNextWindowSizeConstraints(ctx, PX(330), 0, PX(330), 6000)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, PX(16), PX(14))
    local open = ImGui.BeginPopupModal(ctx, id, nil,
        ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoTitleBar)
    ImGui.PopStyleVar(ctx)
    if not open then
        S.dialog = nil
        return
    end

    ImGui.TextColored(ctx, C.text_bright, d.title)
    if d.line then
        ImGui.Dummy(ctx, 1, PX(2))
        ImGui.TextColored(ctx, C.text_dim, SB.fit_text(d.line,
            (ImGui.GetContentRegionAvail(ctx))))
    end
    ImGui.Dummy(ctx, 1, PX(6))
    local done = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
    for n, b in ipairs(d.buttons) do
        if n > 1 then ImGui.SameLine(ctx) end
        if b.primary then
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent)
        end
        local hit = ImGui.Button(ctx, b[1])
        if b.primary then ImGui.PopStyleColor(ctx, 2) end
        if hit then
            if b[2] then b[2]() end
            done = true
        end
    end
    if done then
        ImGui.CloseCurrentPopup(ctx)
        S.dialog = nil
    end
    ImGui.EndPopup(ctx)
end

local function handle_keys()
    -- A dialog owns the keyboard until it is answered.
    if S.dialog then return end
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

    local mods = ImGui.GetKeyMods(ctx)

    -- Cmd/Ctrl+W closes everywhere. Super+Q too, on Linux only: on a Mac
    -- Cmd+Q quits REAPER itself, so Q is never looked at there.
    if mods & MOD_CMD ~= 0 and ImGui.IsKeyPressed(ctx, ImGui.Key_W) then
        S.quit = true
        return
    end
    if IS_LINUX and mods & ImGui.Mod_Super ~= 0
            and ImGui.IsKeyPressed(ctx, ImGui.Key_Q) then
        S.quit = true
        return
    end

    local extend = mods & ImGui.Mod_Shift ~= 0
    if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) then move_sel(1, extend) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) then move_sel(-1, extend) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageDown) then move_sel(10, extend) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageUp) then move_sel(-10, extend) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Home) then
        move_sel(-#S.shown, extend)
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_End) then move_sel(#S.shown, extend) end
    -- Tree: Left folds the folder the selected project is in.
    if S.rows and S.query == '' and ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow) then
        local row = S.rows[S.row_of[S.sel] or 0]
        if row and row.parent and SB.tree_is_open(row.parent) then
            SB.tree_toggle(row.parent)
            S.dirty = true
        end
    end

    local enter = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or
        ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
    if enter then
        if mods & MOD_CMD ~= 0 then
            do_open(SB.alt_open())
        elseif mods & ImGui.Mod_Alt ~= 0 then
            do_open('copy')
        else
            do_open(SB.main_open())
        end
    end

    -- With text in the search box, Delete belongs to the box.
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Delete) and S.query == ''
            and S.view == 'recent' then
        local items = SB.sel_items()
        SB.later(function() remove_recent(items) end)
    end

    if ImGui.IsKeyPressed(ctx, ImGui.Key_F5) then
        SB.meta_cache = {}
        SB.bk_dirs = {}
        SB.reload()
        set_status('Refreshed')
    end

    if mods & MOD_CMD ~= 0 then
        if ImGui.IsKeyPressed(ctx, ImGui.Key_N) then
            run_command(CMD_NEW_PROJECT)
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_O) then
            run_command(CMD_OPEN_PROJECT)
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_F) then
            S.focus_search = true
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Comma) then
            S.show_settings = true
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_A) and S.query == '' then
            sel_all()
        elseif ImGui.IsKeyPressed(ctx, ImGui.Key_D) then
            local items = SB.sel_items()
            if #items > 1 then
                local all = true
                for _, item in ipairs(items) do
                    if not SB.fav_set[item.path] then all = false end
                end
                fav_many(items, not all)
            elseif items[1] then
                SB.fav_toggle(items[1].path)
                S.dirty = true
            end
        end
    end
end

function SB.frame()
    draw_surface()

    SB.px_sweep()

    -- The preview belongs to the selected project only.
    if SB.px.id then
        local cur = selected()
        if S.msel_n > 1 or not cur or cur.path ~= SB.px.item or S.bk then
            SB.prox_stop()
        else
            SB.prox_pos()
        end
    end

    if SB.chk.running then
        if SB.scan.running then
            SB.chk.running = false
        else
            SB.chk_step(0.004)
        end
    end
    if SB.chk.changed and not SB.chk.running then
        SB.chk.changed = false
        if not SB.scan.running then
            SB.scan_start(SB.cfg.roots, SB.cfg.depth)
            set_status('Folders changed, refreshing...')
        end
    end

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
    draw_dialog()

    -- Cleared last, not first: the size buttons at the bottom right are
    -- submitted after draw_status, and wiping it at the top of the frame
    -- meant their hints were thrown away before anything could show them.
    S.hint = nil
end

-- One FX per frame, so REAPER redraws between plug-ins and the count moves
-- the way its own "Bringing FX Online" window does. It keeps running after
-- the main window has closed; Cancel leaves the rest offline.
local function fx_job_window()
    local job = SB.fx_job
    local done = SB.fx_online_step(job)
    local cancel = false

    push_style()
    if S.win_x then
        ImGui.SetNextWindowPos(ctx, S.win_x + (S.win_w or 0) / 2,
            S.win_y + (S.win_h or 0) / 2, ImGui.Cond_Appearing, 0.5, 0.5)
    end
    ImGui.SetNextWindowSizeConstraints(ctx, PX(380), 0, PX(380), 6000)
    local visible = ImGui.Begin(ctx, 'Bringing FX Online##fxjob', nil,
        ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoCollapse |
        ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoScrollbar)
    if visible then
        ImGui.PushFont(ctx, nil, FS(BASE_FONT))
        ImGui.TextColored(ctx, C.text_dim, 'Bringing FX Online')
        ImGui.TextWrapped(ctx, ('%d/%d: %s'):format(job.i, #job.list, job.name))
        local dl = ImGui.GetWindowDrawList(ctx)
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local w = ImGui.GetContentRegionAvail(ctx)
        local h = PX(6)
        ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.frame, h / 2)
        ImGui.DrawList_AddRectFilled(dl, x, y, x + w * job.i / #job.list,
            y + h, C.accent, h / 2)
        ImGui.Dummy(ctx, w, h)
        if ImGui.Button(ctx, 'Cancel') then cancel = true end
        ImGui.PopFont(ctx)
    end
    ImGui.End(ctx)
    pop_style()

    if done or cancel then SB.fx_job = nil end
end

-- Waiting in the background for a new empty tab (Settings > Show on every
-- new empty tab). Once every half second it looks at the tab list: a tab it
-- has not seen, still blank a moment later and in front, brings the window
-- back. A tab that loads something, or that this script made, is let go.
SB.WATCH_EVERY = 0.5
-- A heartbeat this fresh means another instance is alive. Generous on
-- purpose: REAPER can stall for seconds (a dialog, a project load) without
-- the running instance being gone.
SB.ALIVE_WINDOW = 6

local function tab_is_blank(proj, path)
    return (path or '') == '' and reaper.IsProjectDirty(proj) == 0
        and reaper.CountTracks(proj) == 0
end

function SB.watch_reset()
    SB.tabs_known, SB.tabs_new = {}, {}
    local i = 0
    while true do
        local proj = reaper.EnumProjects(i)
        if not proj then break end
        SB.tabs_known[proj] = true
        i = i + 1
    end
end

-- True when the launcher should show up.
function SB.watch_step(now)
    local known, fresh = SB.tabs_known, SB.tabs_new
    local live, fire = {}, false
    local cur = reaper.EnumProjects(-1)
    local i = 0
    while true do
        local proj, path = reaper.EnumProjects(i)
        if not proj then break end
        live[proj] = true
        if not known[proj] then
            if now < (SB.own_until or 0) or not tab_is_blank(proj, path) then
                known[proj], fresh[proj] = true, nil
            elseif not fresh[proj] then
                fresh[proj] = now
            elseif proj == cur then
                known[proj], fresh[proj] = true, nil
                fire = true
            end
        end
        i = i + 1
    end
    for proj in pairs(known) do if not live[proj] then known[proj] = nil end end
    for proj in pairs(fresh) do if not live[proj] then fresh[proj] = nil end end
    return fire
end

local function show_again()
    SB.new_context()
    S.quit, S.dialog, S.pending, S.in_bg = false, nil, nil, nil
    S.show_settings, S.query, S.focus_search = false, '', true
    sel_reset()
    S.sel, S.sel_path = 1, nil
    SB.reload(S.view)
    -- The window is up: running the action again closes it, as always.
    if reaper.set_action_options then reaper.set_action_options(1 | 4) end
end

local loop

-- Window closed, watcher on: stay alive and cheap. Running the action again
-- must bring the window back. Flag 2 alone does not start a new instance on
-- REAPER 7.83, so this uses 1|2: REAPER ends this instance and starts a fresh
-- one, which opens the window like any manual run. 4 keeps the toggle on.
local function background()
    if not S.in_bg then
        S.in_bg = true
        SB.watch_reset()
        S.bg_next = 0
        if reaper.set_action_options then reaper.set_action_options(1 | 2 | 4) end
    end
    local now = reaper.time_precise()
    if now < S.bg_next then return end
    S.bg_next = now + SB.WATCH_EVERY
    reaper.SetExtState(SB.EXTNAME, 'heartbeat', tostring(now), false)
    local asked = reaper.GetExtState(SB.EXTNAME, 'show_ui') == '1'
    if asked then reaper.DeleteExtState(SB.EXTNAME, 'show_ui', false) end
    if SB.watch_step(now) or asked then show_again() end
end

-- The window stays away for two frames, so ReaImGui has really taken it off
-- the screen, then the command runs. With Keep the window open on, the loop
-- carries on from inside the dialog (a second chain is started first) but
-- draws nothing until the command comes back.
local function step_pending()
    SB.prox_stop()
    S.pending.frames = S.pending.frames + 1
    if S.pending.frames < 2 then
        reaper.defer(loop)
        return
    end
    local cmd = S.pending.cmd
    S.pending = nil
    SB.own_tab()
    if SB.cfg.keep_open or SB.cfg.watch_tabs then
        -- The watcher keeps the script alive either way; without Keep the
        -- window open it just stays closed once the command is done.
        S.away = true
        reaper.defer(loop)
        reaper.Main_OnCommand(cmd, 0)
        S.away = false
        if not SB.cfg.keep_open then S.quit = true end
    else
        S.quit = true
        reaper.Main_OnCommand(cmd, 0)
    end
end

loop = function()
    if S.quit then
        SB.prox_stop()
        -- Main window closed with FX still coming online: only the
        -- progress window is left.
        if SB.fx_job then SB.guard('progress', fx_job_window) end
        if SB.cfg.watch_tabs and not SB.reported then
            background()
            reaper.defer(loop)
            return
        end
        if SB.fx_job then reaper.defer(loop) end
        return
    end

    reaper.SetExtState(SB.EXTNAME, 'heartbeat',
        tostring(reaper.time_precise()), false)

    if S.pending or S.away then
        if S.pending then step_pending() else reaper.defer(loop) end
        return
    end

    if reaper.GetExtState(SB.EXTNAME, 'show_ui') == '1' then
        reaper.DeleteExtState(SB.EXTNAME, 'show_ui', false)
        ImGui.SetNextWindowFocus(ctx)
    end

    -- The context can be dropped while a dialog was up (Keep the window
    -- open) and nothing drew for a while. Make a new one before using it.
    local validate = rawget(ImGui, 'ValidatePtr')
    if validate and not validate(ctx, 'ImGui_Context*') then
        SB.new_context()
    end

    push_style()
    ImGui.SetNextWindowSize(ctx, S.win_w or math.min(PX(940), 1500),
        S.win_h or math.min(PX(580), 950), ImGui.Cond_FirstUseEver)
    if S.win_x then
        ImGui.SetNextWindowPos(ctx, S.win_x, S.win_y, ImGui.Cond_FirstUseEver)
    end
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
    -- NoDocking also undocks a window saved as docked. Docked, the first
    -- panel's EndChild fails with "Missing PopStyleVar" on every launch, and
    -- the dock is remembered, so the script could never open again.
    -- p_open must be a value, not nil: with nil ImGui drops the system's close
    -- request, so Alt+F4 or a compositor shortcut like Super+Q on COSMIC (which
    -- never reaches the keyboard check) would do nothing.
    local visible, open = ImGui.Begin(ctx, SB.NAME .. '##main', true,
        ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoCollapse |
        ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse |
        ImGui.WindowFlags_NoDocking)
    if not open then S.quit = true end
    if visible then
        S.win_w, S.win_h = ImGui.GetWindowSize(ctx)
        S.win_x, S.win_y = ImGui.GetWindowPos(ctx)
        ImGui.PushFont(ctx, nil, FS(BASE_FONT))
        SB.guard('frame', SB.frame)
        ImGui.PopFont(ctx)
    end
    ImGui.End(ctx)
    pop_style()
    SB.guard('open', run_later)
    if SB.fx_job then SB.guard('progress', fx_job_window) end

    if not S.quit or SB.fx_job or SB.cfg.watch_tabs then
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
    -- Leftovers of a crashed session (temp preview WAVs).
    for n = 0, SB.PX_SLOTS - 1 do
        SB.px_delete(SB.join(SB.cache_path(), ('prox-preview-%d.wav'):format(n)))
    end
    reaper.atexit(function()
        SB.prox_stop()
        SB.px_sweep(true)
        SB.fx_online_finish()
        reaper.DeleteExtState(SB.EXTNAME, 'heartbeat', false)
        reaper.DeleteExtState(SB.EXTNAME, 'show_ui', false)
        -- Toolbar toggle off. REAPER 7.03+ only.
        if reaper.set_action_options then reaper.set_action_options(8) end
    end)

    -- Launched from __startup.lua with a project already loaded? Stay away.
    if SB.cfg.skip_if_open and SB.launched_at_startup then
        local _, name = reaper.EnumProjects(0)
        if name and name ~= '' then
            -- No window now, but with the watcher on the script stays.
            if not SB.cfg.watch_tabs then return end
            S.quit = true
        end
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
    else
        SB.chk_start()
    end
    reaper.defer(loop)
end

if LAUNCHER_TEST then return SB end

-- REAPER < 7.03 has no set_action_options, so flag 1 above never applies and
-- a second run does not terminate this instance: bring the open window to
-- the front instead. On 7.03+ REAPER terminates the running instance first,
-- so this branch is the old-REAPER fallback only.
local beat = tonumber(reaper.GetExtState(SB.EXTNAME, 'heartbeat'))
if beat and reaper.time_precise() - beat < SB.ALIVE_WINDOW then
    reaper.SetExtState(SB.EXTNAME, 'show_ui', '1', false)
    return SB
end

-- Only __startup.lua sets this flag, so a manual run always shows up.
SB.launched_at_startup = reaper.GetExtState(SB.EXTNAME, 'startup') == '1'
    or reaper.GetExtState(SB.OLD_EXTNAME, 'startup') == '1'
reaper.DeleteExtState(SB.EXTNAME, 'startup', false)
reaper.DeleteExtState(SB.OLD_EXTNAME, 'startup', false)
SB.main()
