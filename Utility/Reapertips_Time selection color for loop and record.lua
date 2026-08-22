--[[
  @description Time selection color for loop and record
  @author Reapertips (Alejandro Hernandez)
  @version 1.1
  @license MIT
  @link
    Reapertips https://www.reapertips.com
  @about
    # Time selection color for loop and record
    Tints the time selection while Repeat/Loop is ON and while REAPER is
    recording, so you can tell both states apart without looking away from
    what you are doing.
    Each of the two states decides on its own which areas it paints, and the
    colours are remembered per theme. There is a live preview in the settings
    window, so you can see what a colour looks like before committing to it.
    ## Using it
    - Run the action to open the settings window. Closing the window leaves
      the script running in the background; running the action again brings
      the window back.
    - Tick **Run on startup** and it starts with REAPER, quietly, without
      opening the window.
    - **Quit script** stops it and puts every colour back.
    ## What it can paint
    - The loop bar in the ruler
    - The time selection overlay in the arrange view
    - The time selection in the MIDI editor
    - The whole ruler strip. Marker and region lanes are left alone.
    Every one of those has its own intensity slider, per state: drag it down
    and the colour is mixed with your theme's own instead of replacing it, so
    you can go from a hint to full strength.
    ## Safety
    Colours are changed in memory only, so your `.ReaperTheme` file is never
    written to. Even a crash cannot leave a permanent change: restarting
    REAPER puts everything back.
    ## Requirements
    REAPER 6.19 or newer. No extensions needed.
    ## Credits and licences
    This script is MIT licensed.
    Based on an earlier script by knmk, with thanks to CMS, which was passed
    around and improved by someone else before this rewrite.
    The startup hook handling is adapted from **Gridbox** by Ilias-Timon
    Poulakis (FeedTheCat), used under the MIT licence:
    > MIT License
    > Copyright (c) 2020 iliaspoulakis
    > Permission is hereby granted, free of charge, to any person obtaining a
      copy of this software and associated documentation files (the
      "Software"), to deal in the Software without restriction, including
      without limitation the rights to use, copy, modify, merge, publish,
      distribute, sublicense, and/or sell copies of the Software, and to
      permit persons to whom the Software is furnished to do so, subject to
      the following conditions:
    > The above copyright notice and this permission notice shall be included
      in all copies or substantial portions of the Software.
    > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
      OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
      IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
      CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
      TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
      SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  @changelog
    1.1 - Fixes the arrange and ruler rows, which were the wrong way round in
          1.0: what the matrix called "arrange" was painting the ruler and the
          other way round. If you set it up under 1.0, take one look at the
          matrix after updating.
        - Every cell now has its own intensity, so loop and record can be as
          strong or as subtle as you like, area by area. Replaces the single
          ruler-strip tint slider; your old value carries over.
        - Areas are listed in a more useful order, and the arrange overlay is
          off out of the box.
    1.0 - Initial release.
--]]

------------------------------------------------------------------------------
-- Requirements
------------------------------------------------------------------------------

local TITLE = 'Loop & record color'

if not reaper.APIExists or not reaper.APIExists('SetThemeColor') or
    not reaper.APIExists('GetThemeColor') then
    reaper.MB('This script needs REAPER 6.19 or newer.', TITLE, 0)
    return
end

------------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------------

local extname = 'RTIPS.LoopColorTS'

local OS       = reaper.GetOS()
local IS_MACOS = OS:match('OS') ~= nil

-- The areas REAPER lets us recolor, in the order they are listed.
-- keys  : every theme color that makes up the area
-- Every area is blended over the theme's own color by its own intensity, so
-- 100 % replaces the color outright and anything less is a tint.
-- NOTE ON THE TWO col_tl_bgsel KEYS: their names lie. Measured in REAPER
-- 7.79, `col_tl_bgsel` paints the time selection overlay in the ARRANGE, and
-- `col_tl_bgsel2` paints the loop bar with its two triangular markers in the
-- RULER -- the opposite of what you would guess. Do not "fix" this back.
local ZONES = {
    { id = 'ruler',   keys = { 'col_tl_bgsel2' },
      label = 'Time selection \u{00B7} ruler' },
    { id = 'arrange', keys = { 'col_tl_bgsel' },
      label = 'Time selection \u{00B7} arrange' },
    { id = 'midi',    keys = { 'midi_selbg' },
      label = 'Time selection \u{00B7} MIDI editor' },
    -- The ruler is not one surface. The timeline and the time signature lane
    -- are two separate theme colors, and painting only the first leaves a thin
    -- unpainted band under the markers. The marker and region lanes are
    -- deliberately NOT included: they carry the user's own content.
    { id = 'rulerbg', label = 'Whole ruler strip',
      keys = { 'col_tl_bg', 'ts_lane_bg' } },
}

local STATES = {
    { id = 'loop', label = 'LOOP ON' },
    { id = 'rec',  label = 'REC' },
}

-- Read for the preview only; never painted.
local PREVIEW_KEYS = { 'marker_lane_bg', 'col_arrangebg' }

-- Painted out of the box: the loop bar in the ruler and the MIDI editor. The
-- arrange overlay is off, it covers a lot of screen and not everyone wants it.
local DEFAULT_PAINT = {
    loop = { ruler = true, arrange = false, midi = true, rulerbg = false },
    rec  = { ruler = true, arrange = false, midi = true, rulerbg = false },
}

-- Starting intensity per area. Full strength everywhere except the whole
-- ruler strip, which at full strength buries the bar numbers.
local DEFAULT_TINT = { ruler = 100, arrange = 100, midi = 100, rulerbg = 20 }

local DEFAULT_LOOP = 'FFC21E'
local DEFAULT_REC  = 'FE6A6A'

-- Hand-picked starting points, matched on the theme file name.
local THEME_PRESETS = {
    { match = 'reapertips', loop = 'FFC21E', rec = 'E94546' },
    { match = 'default_7',  loop = '4FD16A', rec = 'FE6A6A' },
    { match = 'default_6',  loop = '4FD16A', rec = 'FE6A6A' },
}

-- Window metrics in points; everything is multiplied by the display scale.
local W, H  = 480, 388
local FONT  = 'Fira Sans' -- the OS substitutes if missing; the layout measures
local FSIZE = 15

local COL_BG   = { 0x24, 0x24, 0x24 }
local COL_TEXT = { 0xD2, 0xD2, 0xD2 }
local COL_DIM  = { 0x88, 0x88, 0x88 }
local COL_LINE = { 0x3A, 0x3A, 0x3B }
local COL_BOX  = { 0x5A, 0x5A, 0x5C }
local COL_PILL = { 0x33, 0x33, 0x34 }

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function HexToRGB(hex)
    local n = tonumber(hex, 16) or 0
    return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

local function HexToNative(hex)
    return reaper.ColorToNative(HexToRGB(hex))
end

-- Mix `hex` over `base` by `amount` (0..1) and return a native color.
local function Blend(base, hex, amount)
    local br, bg, bb = reaper.ColorFromNative(base)
    local r, g, b = HexToRGB(hex)
    return reaper.ColorToNative(
        math.floor(br + (r - br) * amount + 0.5),
        math.floor(bg + (g - bg) * amount + 0.5),
        math.floor(bb + (b - bb) * amount + 0.5))
end

local function NativeToHex(native)
    local r, g, b = reaper.ColorFromNative(native)
    return string.format('%02X%02X%02X', r, g, b)
end

local function GetExt(key, default)
    local v = reaper.GetExtState(extname, key)
    if v == '' then return default end
    return v
end

local function SetExt(key, value)
    reaper.SetExtState(extname, key, tostring(value), true)
end

local function GetBool(key, default)
    local v = reaper.GetExtState(extname, key)
    if v == '' then return default end
    return v == '1'
end

local function SetBool(key, value)
    SetExt(key, value and '1' or '0')
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

------------------------------------------------------------------------------
-- Single instance guard: a second run just re-opens the window
------------------------------------------------------------------------------

-- Generous, because the color picker and the hex prompt are modal and stall
-- the defer loop for as long as the user keeps them open.
local HEARTBEAT_TIMEOUT = 8

local function Beat()
    reaper.SetExtState(extname, 'heartbeat',
        tostring(reaper.time_precise()), false)
end

local beat = tonumber(reaper.GetExtState(extname, 'heartbeat'))
if beat and reaper.time_precise() - beat < HEARTBEAT_TIMEOUT then
    reaper.SetExtState(extname, 'show_ui', '1', false)
    return
end

-- 'session' is non-persistent, so it is empty once per REAPER launch.
local first_run_of_session = reaper.GetExtState(extname, 'session') ~= '1'
reaper.SetExtState(extname, 'session', '1', false)

local _, script_path, section, cmd_id = reaper.get_action_context()

------------------------------------------------------------------------------
-- Startup hook
--
-- ConcatPath, GetStartupHookCommandID, IsStartupHookEnabled and
-- SetStartupHookEnabled below are adapted from Gridbox by Ilias-Timon
-- Poulakis (FeedTheCat), MIT licensed.
-- https://github.com/iliaspoulakis/Reaper-Tools
-- The licence text is in this script's ReaPack about page and in the
-- repository LICENSE file.
------------------------------------------------------------------------------

local function ConcatPath(...)
    return table.concat({ ... }, package.config:sub(1, 1))
end

local function StartupPath()
    return ConcatPath(reaper.GetResourcePath(), 'Scripts', '__startup.lua')
end

local function ReadFile(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('*a')
    file:close()
    return content
end

-- __startup.lua is shared with every other script that hooks it, so a failed
-- write must never truncate somebody else's hook.
local function WriteFileSafely(path, content)
    local tmp = path .. '.tmp'
    local file = io.open(tmp, 'wb')
    if not file then return false end
    local ok = file:write(content)
    file:close()
    if not ok then
        os.remove(tmp)
        return false
    end
    os.remove(path)
    if os.rename(tmp, path) then return true end
    -- Rename can fail across some filesystems; never leave the user with no
    -- startup script at all.
    local direct = io.open(path, 'wb')
    if not direct then return false end
    direct:write(content)
    direct:close()
    os.remove(tmp)
    return true
end

-- read_only: report only, never touch the action list or stored state
local function GetStartupHookCommandID(read_only)
    -- Note: startup hook commands have to live in the main section
    local id = cmd_id
    if section == 0 then
        local name = reaper.ReverseNamedCommandLookup(id)
        if not name then return 0 end
        local cmd_name = '_' .. name
        if not read_only and GetExt('hook_cmd_name', '') ~= cmd_name then
            SetExt('hook_cmd_name', cmd_name)
        end
        return id
    end

    id = reaper.NamedCommandLookup(GetExt('hook_cmd_name', ''))
    if id ~= 0 or read_only then return id end

    -- Add the script to the main section so it gets a command id
    id = reaper.AddRemoveReaScript(true, 0, script_path, true)
    if id == 0 then return 0 end
    local name = reaper.ReverseNamedCommandLookup(id)
    if not name then return 0 end
    SetExt('hook_cmd_name', '_' .. name)
    return id
end

local function IsStartupHookEnabled(read_only)
    local id = GetStartupHookCommandID(read_only)
    if id == 0 then return false end
    local cmd_name = reaper.ReverseNamedCommandLookup(id)
    if not cmd_name then return false end

    local content = ReadFile(StartupPath())
    if not content then return false end

    local s, e = content:find('[^\n]+' .. cmd_name .. '\'?\n?[^\n]+')
    if s and e then
        local hook = content:sub(s, e)
        if not hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand') then
            return true
        end
    end
    return false
end

local function SetStartupHookEnabled(is_enabled)
    local id = GetStartupHookCommandID()
    if id == 0 then return end
    local cmd_name = reaper.ReverseNamedCommandLookup(id)
    if not cmd_name then return end
    local path = StartupPath()

    local content = ReadFile(path) or ''

    local s, e = content:find('[^\n]+' .. cmd_name .. '\'?\n?[^\n]+')
    if s and e then
        -- Comment out / uncomment the hook that is already there
        local hook = content:sub(s, e)
        local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
        hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
        WriteFileSafely(path, content:sub(1, s - 1) .. hook .. content:sub(e + 1))
        return
    end

    if not is_enabled then return end

    local hook = '-- Start script: Loop & record color (Reapertips)\n\z
        local loop_color_cmd_name = \'_%s\'\nreaper.\z
        Main_OnCommand(reaper.NamedCommandLookup(loop_color_cmd_name), 0)\n\n'
    WriteFileSafely(path, hook:format(cmd_name) .. content)
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

local settings = { enabled = GetBool('enabled', true), paint = {}, tint = {} }

-- 1.0 had a single ruler-strip tint. Carry it over so nobody's setting is
-- silently thrown away by the upgrade.
local legacy_tint = tonumber(GetExt('tint_pct', ''))

for _, st in ipairs(STATES) do
    settings.paint[st.id] = {}
    settings.tint[st.id] = {}
    for _, z in ipairs(ZONES) do
        settings.paint[st.id][z.id] =
            GetBool('paint.' .. st.id .. '.' .. z.id,
                DEFAULT_PAINT[st.id][z.id])
        local default = DEFAULT_TINT[z.id]
        if z.id == 'rulerbg' and legacy_tint then default = legacy_tint end
        local v = tonumber(GetExt('tint.' .. st.id .. '.' .. z.id, ''))
        settings.tint[st.id][z.id] =
            Clamp(math.floor(v or default), 0, 100)
    end
end

local function SavePaint(state, zone)
    SetBool('paint.' .. state .. '.' .. zone, settings.paint[state][zone])
end

local function SaveTint(state, zone)
    SetExt('tint.' .. state .. '.' .. zone, settings.tint[state][zone])
end

local theme_key, palette

local function ThemeKey()
    local path = reaper.GetLastColorThemeFile() or ''
    local name = path:match('[^/\\]+$') or 'default'
    return (name:gsub('%.[Rr]eaper[Tt]heme[Zz]?[Ii]?[Pp]?$', ''))
end

-- Two colors a user could not tell apart at a glance
local function TooClose(hex, native)
    if not native or native < 0 then return false end
    local r1, g1, b1 = HexToRGB(hex)
    local r2, g2, b2 = reaper.ColorFromNative(native)
    return math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) < 90
end

local function LoadPalette()
    theme_key = ThemeKey()
    local stored = GetExt('theme.' .. theme_key, '')
    local loop, rec = stored:match('^(%x%x%x%x%x%x),(%x%x%x%x%x%x)$')
    if loop then
        palette = { loop = loop, rec = rec }
        return
    end

    local lower = theme_key:lower()
    for _, preset in ipairs(THEME_PRESETS) do
        if lower:find(preset.match, 1, true) then
            palette = { loop = preset.loop, rec = preset.rec }
            return
        end
    end

    -- Unknown theme: borrow its accent, unless that would be invisible
    -- against the time selection it is meant to replace.
    local accent = reaper.GetThemeColor('areasel_outline', 0)
    local hex = accent >= 0 and NativeToHex(accent) or DEFAULT_LOOP
    if TooClose(hex, reaper.GetThemeColor('col_tl_bgsel', 0)) then
        hex = DEFAULT_LOOP
    end
    palette = { loop = hex, rec = DEFAULT_REC }
end

local function SavePalette()
    SetExt('theme.' .. theme_key, palette.loop .. ',' .. palette.rec)
end

local function ResetPalette()
    reaper.DeleteExtState(extname, 'theme.' .. theme_key, true)
    LoadPalette()
end

------------------------------------------------------------------------------
-- Theme color engine
------------------------------------------------------------------------------

local baseline   = {} -- theme key -> the color the theme itself specifies
local applied    = {} -- theme key -> color we forced, nil when restored
local dirty      = false
local dirty_midi = false

local function ThemeValue(key)
    -- flags&1 asks for the value the theme specifies, before any runtime
    -- override. Builds that ignore the flag return the same as flags 0, which
    -- is why the baseline is only ever refreshed while nothing is applied.
    local v = reaper.GetThemeColor(key, 1)
    if not v or v < 0 then v = reaper.GetThemeColor(key, 0) end
    return v
end

-- Never refresh a baseline for a color we are currently overriding: we would
-- read our own tint back and then "restore" it permanently.
local function Baseline(key)
    if applied[key] == nil then
        local v = ThemeValue(key)
        if v >= 0 then baseline[key] = v end
    end
    return baseline[key]
end

-- Which theme keys actually exist has to be re-checked when the theme changes.
local function RescanZones()
    for _, z in ipairs(ZONES) do
        z.live = {}
        for _, key in ipairs(z.keys) do
            if reaper.GetThemeColor(key, 0) >= 0 then
                z.live[#z.live + 1] = key
            end
        end
        z.supported = #z.live > 0
    end
end

local function CaptureBaseline()
    baseline, applied = {}, {}
    RescanZones()
    for _, z in ipairs(ZONES) do
        for _, key in ipairs(z.live) do Baseline(key) end
    end
    for _, key in ipairs(PREVIEW_KEYS) do Baseline(key) end
end

local function ForceColor(key, native)
    local base = Baseline(key)
    if base == nil or applied[key] == native then return end
    reaper.SetThemeColor(key, native, 0)
    applied[key] = native
    dirty = true
    if key == 'midi_selbg' then dirty_midi = true end
end

local function RestoreColor(key)
    if applied[key] == nil then return end
    reaper.SetThemeColor(key, baseline[key], 0)
    applied[key] = nil
    dirty = true
    if key == 'midi_selbg' then dirty_midi = true end
end

local function Flush()
    if not dirty then return end
    reaper.UpdateArrange()
    reaper.UpdateTimeline()
    -- An already-open MIDI editor does not repaint from UpdateArrange.
    if dirty_midi and reaper.APIExists('ThemeLayout_RefreshAll') then
        reaper.ThemeLayout_RefreshAll()
    end
    dirty, dirty_midi = false, false
end

local function RestoreAll()
    for _, z in ipairs(ZONES) do
        for _, key in ipairs(z.live) do RestoreColor(key) end
    end
    Flush()
end

-- 'none' | 'loop' | 'rec'
local function TransportState()
    if reaper.GetPlayState() & 4 == 4 then return 'rec' end
    if reaper.GetSetRepeat(-1) == 1 then return 'loop' end
    return 'none'
end

local function ApplyState(state)
    if state == 'none' then
        RestoreAll()
        return
    end
    for _, z in ipairs(ZONES) do
        local on = z.supported and settings.paint[state][z.id]
        local amount = settings.tint[state][z.id] / 100
        for _, key in ipairs(z.live) do
            if on then
                -- each area is blended over its OWN theme color, so areas that
                -- start out lighter or darker keep their relationship
                ForceColor(key, Blend(Baseline(key), palette[state], amount))
            else
                RestoreColor(key)
            end
        end
    end
    Flush()
end

------------------------------------------------------------------------------
-- Toolbar toggle state
------------------------------------------------------------------------------

local function SetToggle(on)
    reaper.SetToggleCommandState(section, cmd_id, on and 1 or 0)
    reaper.RefreshToolbar2(section, cmd_id)
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------

local ui_open      = false
local hot          = {}
local S            = 1
local last_state   = nil
local quitting     = false
local dragging     = nil
local mouse_down   = false
local resized      = false

-- Which state the preview shows. Validated: it is used as a table key.
local preview = GetExt('preview', 'loop')
if preview ~= 'loop' and preview ~= 'rec' then preview = 'loop' end

-- On macOS gfx doubles its own coordinate space on a retina display. Nowhere
-- else does, so there the window itself has to be opened bigger.
local function DisplayScale()
    if IS_MACOS then return 1 end
    if not reaper.APIExists('ThemeLayout_GetLayout') then return 1 end
    local _, dpi = reaper.ThemeLayout_GetLayout('trans', -3)
    return Clamp((tonumber(dpi) or 256) / 256, 1, 4)
end

local dpi_scale = DisplayScale()

local function OpenUI()
    local x = tonumber(GetExt('win_x', '')) or 200
    local y = tonumber(GetExt('win_y', '')) or 200
    -- A stale position from a monitor that is no longer attached would put the
    -- window somewhere the user cannot reach it.
    if x < -8000 or x > 16000 then x = 200 end
    if y < -8000 or y > 16000 then y = 200 end
    gfx.ext_retina = 1
    gfx.init(TITLE, math.floor(W * dpi_scale), math.floor(H * dpi_scale), 0,
        x, y)
    ui_open = true
end

-- Polled while the window is open, because by the time it closes gfx.dock can
-- no longer tell us where it was. Throttled: it is only ever needed on close.
local pos_checked_at = 0

local function RememberPosition(force)
    local now = reaper.time_precise()
    if not force and now - pos_checked_at < 1 then return end
    pos_checked_at = now
    local _, x, y = gfx.dock(-1, 0, 0, 0, 0)
    if x and y and (x ~= 0 or y ~= 0) then
        SetExt('win_x', math.floor(x))
        SetExt('win_y', math.floor(y))
    end
end

local function CloseUI()
    if not ui_open then return end
    RememberPosition(true)
    gfx.quit()
    ui_open = false
    dragging, mouse_down = nil, false
end

local function SetCol(rgb, a)
    gfx.set(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, a or 1)
end

local function SetHex(hex, a)
    local r, g, b = HexToRGB(hex)
    gfx.set(r / 255, g / 255, b / 255, a or 1)
end

local function SetNative(native, a)
    local r, g, b = reaper.ColorFromNative(native or 0)
    gfx.set(r / 255, g / 255, b / 255, a or 1)
end

local function AddHot(x, y, w, h, fn, drag)
    hot[#hot + 1] = { x = x, y = y, w = w, h = h, fn = fn, drag = drag }
end

local function Text(x, y, str)
    gfx.x, gfx.y = x, y
    gfx.drawstr(str)
end

local function TextH()
    local _, h = gfx.measurestr('Ag')
    return h
end

-- Left-aligned checkbox with a label. Returns its full width.
local function Checkbox(x, y, label, checked, fn, disabled)
    local box = math.floor(15 * S)
    SetCol(disabled and COL_LINE or COL_BOX)
    gfx.rect(x, y, box, box, 0)
    if checked then
        if disabled then SetCol(COL_DIM) else SetHex(palette.loop) end
        gfx.rect(x + 3 * S, y + 3 * S, box - 6 * S, box - 6 * S, 1)
    end
    SetCol(disabled and COL_DIM or COL_TEXT)
    local tw, th = gfx.measurestr(label)
    Text(x + box + 9 * S, y + (box - th) / 2, label)
    if not disabled then
        AddHot(x, y - 3 * S, box + 9 * S + tw, box + 6 * S, fn)
    end
    return box + 9 * S + tw
end

-- One cell of the matrix: on/off box, then how strong. 100 % replaces the
-- theme color outright, anything less mixes the two.
local CELL_BOX  = 15
local CELL_GAP  = 6
local CELL_BAR  = 44
local CELL_PCT  = 32
local CELL_W    = CELL_BOX + CELL_GAP + CELL_BAR + CELL_GAP + CELL_PCT

local function Cell(x, y, state, zone, disabled)
    local box = math.floor(CELL_BOX * S)
    local on  = settings.paint[state][zone]
    local pct = settings.tint[state][zone]
    local hex = palette[state]

    SetCol(disabled and COL_LINE or COL_BOX)
    gfx.rect(x, y, box, box, 0)
    if on then
        if disabled then SetCol(COL_DIM) else SetHex(hex) end
        gfx.rect(x + 3 * S, y + 3 * S, box - 6 * S, box - 6 * S, 1)
    end
    if not disabled then
        AddHot(x - 3 * S, y - 4 * S, box + 6 * S, box + 8 * S, function()
            settings.paint[state][zone] = not settings.paint[state][zone]
            SavePaint(state, zone)
            last_state = nil
        end)
    end

    -- intensity
    local bx = x + box + math.floor(CELL_GAP * S)
    local bw = math.floor(CELL_BAR * S)
    local bh = math.floor(6 * S)
    local by = y + math.floor(5 * S)

    SetCol(COL_LINE)
    gfx.rect(bx, by, bw, bh, 1)
    if disabled then
        SetCol(COL_DIM, 0.4)
    elseif on then
        SetHex(hex)
    else
        SetCol(COL_DIM, 0.45)
    end
    gfx.rect(bx, by, math.floor(bw * pct / 100), bh, 1)

    if not disabled then
        AddHot(bx - 4 * S, y - 4 * S, bw + 8 * S, box + 8 * S, nil,
            function(mx)
                -- dragging an area you had switched off turns it on: the bar
                -- is meaningless otherwise, and it saves a second click
                if not settings.paint[state][zone] then
                    settings.paint[state][zone] = true
                    SavePaint(state, zone)
                end
                local v = math.floor(Clamp((mx - bx) / bw, 0, 1) * 100 + 0.5)
                if v == settings.tint[state][zone] then return end
                settings.tint[state][zone] = v
                SaveTint(state, zone)
                last_state = nil
            end)
    end

    gfx.setfont(2, FONT, math.floor(11 * S))
    SetCol(COL_DIM, (on and not disabled) and 1 or 0.5)
    Text(bx + bw + math.floor(CELL_GAP * S), y + math.floor(3 * S), pct .. '%')
    gfx.setfont(1, FONT, math.floor(FSIZE * S))
end

local function Swatch(cx, y, hex, fn)
    local w, h = math.floor(40 * S), math.floor(18 * S)
    local x = math.floor(cx - w / 2)
    SetHex(hex)
    gfx.rect(x, y, w, h, 1)
    SetCol(COL_BOX)
    gfx.rect(x, y, w, h, 0)
    AddHot(x, y, w, h, fn)
    return h
end

local function Pill(x, y, label, active, fn)
    local pad = math.floor(10 * S)
    local tw, th = gfx.measurestr(label)
    local w, h = tw + pad * 2, th + math.floor(6 * S)
    SetCol(COL_PILL, active and 1 or 0.45)
    gfx.rect(x, y, w, h, 1)
    SetCol(COL_BOX, active and 1 or 0.5)
    gfx.rect(x, y, w, h, 0)
    SetCol(active and COL_TEXT or COL_DIM)
    Text(x + pad, y + 3 * S, label)
    AddHot(x, y, w, h, fn)
    return w
end

local function Centered(cx, y, label)
    local tw = gfx.measurestr(label)
    Text(math.floor(cx - tw / 2), y, label)
end

local function Link(x, y, label, fn)
    local tw, th = gfx.measurestr(label)
    SetCol(COL_DIM)
    Text(x, y, label)
    AddHot(x, y - 3 * S, tw, th + 6 * S, fn)
    return tw
end

-- A fake ruler + arrange, painted the way the chosen state would paint them
local function Preview(x, y, w)
    local mh   = math.floor(12 * S)  -- marker / region lanes: never painted
    local sh   = math.floor(6 * S)   -- time signature lane
    local rh   = math.floor(22 * S)
    local ah   = math.floor(34 * S)
    local top  = y
    local hex  = palette[preview]
    local on   = settings.paint[preview]
    local tn   = settings.tint[preview]
    local sel1 = math.floor(x + w * 0.26)
    local sel2 = math.floor(x + w * 0.64)
    local px   = math.max(1, math.floor(S))

    -- marker / region lanes: shown for context, never repainted
    SetNative(Baseline('marker_lane_bg') or 0x333333)
    gfx.rect(x, y, w, mh, 1)
    SetCol(COL_LINE)
    gfx.rect(x, y + mh - px, w, px, 1)
    y = y + mh

    -- time signature lane
    local ts_bg = Baseline('ts_lane_bg') or 0x2E2E2E
    if on.rulerbg then
        SetNative(Blend(ts_bg, hex, tn.rulerbg / 100))
    else
        SetNative(ts_bg)
    end
    gfx.rect(x, y, w, sh, 1)
    y = y + sh

    -- ruler strip
    local ruler_bg = Baseline('col_tl_bg') or 0x2B2B2B
    if on.rulerbg then
        SetNative(Blend(ruler_bg, hex, tn.rulerbg / 100))
    else
        SetNative(ruler_bg)
    end
    gfx.rect(x, y, w, rh, 1)

    -- ticks and bar numbers
    gfx.setfont(2, FONT, math.floor(9 * S))
    for i = 0, 5 do
        local tx = math.floor(x + w * i / 6)
        SetCol(COL_TEXT, 0.30)
        gfx.rect(tx, y, px, math.floor(rh * 0.6), 1)
        SetCol(COL_TEXT, 0.85)
        Text(tx + math.floor(3 * S), y + px, 1 + i * 4 .. '.1')
    end
    gfx.setfont(1, FONT, math.floor(FSIZE * S))

    -- The loop bar at the bottom of the ruler, with its two triangular loop
    -- markers. This is `col_tl_bgsel2`, the "ruler" row.
    local bar_off = Baseline('col_tl_bgsel2') or 0x808080
    local band = math.max(3, math.floor(rh * 0.20))
    local by = y + rh - band
    if on.ruler then
        SetNative(Blend(bar_off, hex, tn.ruler / 100))
    else
        SetNative(bar_off)
    end
    gfx.rect(sel1, by, sel2 - sel1, band, 1)
    local tri = band * 2
    for k = 0, tri - 1 do
        local tw = tri - k
        gfx.rect(sel1, by - tri + k, tw, 1, 1)
        gfx.rect(sel2 - tw, by - tri + k, tw, 1, 1)
    end

    -- Arrange overlay, `col_tl_bgsel`, the "arrange" row. Independent of the
    -- bar above. The grid lines go down first and the selection is blended
    -- over them at low opacity, which is what REAPER does; painting it solid
    -- made the preview look far heavier than the real thing.
    y = y + rh
    SetNative(Baseline('col_arrangebg') or 0x3D3D3D)
    gfx.rect(x, y, w, ah, 1)
    SetCol(COL_TEXT, 0.10)
    for i = 0, 5 do
        gfx.rect(math.floor(x + w * i / 6), y, px, ah, 1)
    end
    local arr_off = Baseline('col_tl_bgsel') or 0x808080
    if on.arrange then
        SetNative(Blend(arr_off, hex, tn.arrange / 100), 0.22)
    else
        SetNative(arr_off, 0.22)
    end
    gfx.rect(sel1, y, sel2 - sel1, ah, 1)

    SetCol(COL_LINE)
    gfx.rect(x, top, w, mh + sh + rh + ah, 0)
    return mh + sh + rh + ah
end

local function PickColor(which)
    -- GR_SelectColor takes only an HWND; the current color cannot be
    -- pre-selected. pcall because it is missing on some builds.
    local ok, ret, col = pcall(reaper.GR_SelectColor, nil)
    Beat()
    if ok then
        -- ret false means the user cancelled: do nothing, do not nag them
        -- with a second dialog.
        if ret and col then
            palette[which] = NativeToHex(col)
            SavePalette()
            last_state = nil
        end
        return
    end

    local ok2, csv = reaper.GetUserInputs(
        TITLE, 1, 'Hex color (RRGGBB),extrawidth=60', palette[which])
    Beat()
    if not ok2 then return end
    local hex = csv:gsub('#', ''):gsub('%s', ''):upper()
    if hex:match('^%x%x%x%x%x%x$') then
        palette[which] = hex
        SavePalette()
        last_state = nil
    end
end

-- Reading __startup.lua every frame would be wasteful; cache it.
local startup_cache, startup_checked_at = nil, 0

local function StartupState()
    local now = reaper.time_precise()
    if startup_cache == nil or now - startup_checked_at > 1 then
        startup_cache = IsStartupHookEnabled(true)
        startup_checked_at = now
    end
    return startup_cache
end

local function ShortThemeName()
    local name = theme_key
    if #name > 16 then name = name:sub(1, 15) .. '\u{2026}' end
    return name:upper()
end

local function DrawUI()
    hot = {}
    local retina = (gfx.ext_retina and gfx.ext_retina > 0) and gfx.ext_retina
        or 1
    S = math.max(retina, dpi_scale)
    gfx.setfont(1, FONT, math.floor(FSIZE * S))

    SetCol(COL_BG)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)

    local pad = math.floor(16 * S)
    local x   = pad
    local w   = gfx.w - pad * 2
    local th  = TextH()

    -- Everything horizontal is measured, so a substituted font cannot make
    -- the columns collide with the labels.
    local labelw = 0
    for _, z in ipairs(ZONES) do
        labelw = math.max(labelw, gfx.measurestr(z.label))
    end
    if not resized then
        resized = true
        local want = math.ceil((pad * 2 + labelw + (CELL_W * 2 + 30) * S) / S)
        if want > W then
            W = want
            gfx.init(TITLE, math.floor(W * dpi_scale),
                math.floor(H * dpi_scale))
            return
        end
    end

    local cw    = math.floor(CELL_W * S)
    local rec_x = gfx.w - pad - cw
    local col   = { rec = rec_x, loop = rec_x - cw - math.floor(16 * S) }
    -- headers and swatches centre over the box+bar, not over the number
    local half  = math.floor((CELL_BOX + CELL_GAP + CELL_BAR) * S / 2)
    local cx    = { rec = col.rec + half, loop = col.loop + half }
    local y = pad

    -- master switches
    Checkbox(x, y, 'Enabled', settings.enabled, function()
        settings.enabled = not settings.enabled
        SetBool('enabled', settings.enabled)
        SetToggle(settings.enabled)
        if not settings.enabled then RestoreAll() end
        last_state = nil
    end)
    local su = 'Run on startup'
    Checkbox(gfx.w - pad - (math.floor(24 * S) + gfx.measurestr(su)), y, su,
        StartupState(), function()
            SetStartupHookEnabled(not IsStartupHookEnabled())
            startup_cache = nil
        end)
    y = y + math.floor(15 * S) + math.floor(14 * S)

    -- preview
    y = y + Preview(x, y, w) + math.floor(9 * S)

    SetCol(COL_DIM)
    Text(x, y + 3 * S, 'Preview:')
    local px = x + gfx.measurestr('Preview:') + math.floor(12 * S)
    for _, st in ipairs(STATES) do
        local label = st.id == 'loop' and 'Loop is on' or 'Recording'
        px = px + Pill(px, y, label, preview == st.id, function()
            preview = st.id
            SetExt('preview', preview)
        end) + math.floor(7 * S)
    end
    y = y + th + math.floor(6 * S) + math.floor(14 * S)

    SetCol(COL_LINE)
    gfx.rect(x, y, w, math.max(1, math.floor(S)), 1)
    y = y + math.floor(13 * S)

    -- column headers + colors
    SetCol(COL_DIM)
    Text(x, y, ShortThemeName())
    for _, st in ipairs(STATES) do Centered(cx[st.id], y, st.label) end
    y = y + math.floor(20 * S)

    SetCol(COL_TEXT)
    Text(x, y + 2 * S, 'Color')
    for _, st in ipairs(STATES) do
        Swatch(cx[st.id], y, palette[st.id], function() PickColor(st.id) end)
    end
    y = y + math.floor(18 * S) + math.floor(16 * S)

    -- paint matrix
    SetCol(COL_DIM)
    Text(x, y, 'PAINT')
    y = y + math.floor(20 * S)

    for _, z in ipairs(ZONES) do
        SetCol(z.supported and COL_TEXT or COL_DIM)
        Text(x, y + (15 * S - th) / 2, z.label)
        for _, st in ipairs(STATES) do
            Cell(col[st.id], y, st.id, z.id, not z.supported)
        end
        y = y + math.floor(24 * S)
    end
    y = y + math.floor(10 * S)

    Link(x, y, 'Reset colors for this theme', function()
        ResetPalette()
        last_state = nil
    end)
    local quit = 'Quit script'
    Link(gfx.w - pad - gfx.measurestr(quit), y, quit, function()
        quitting = true
    end)
end

------------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------------

local last_theme_check = 0
local last_theme_file  = reaper.GetLastColorThemeFile()
local error_shown      = false

local function Frame()
    Beat()

    if reaper.GetExtState(extname, 'show_ui') == '1' then
        reaper.DeleteExtState(extname, 'show_ui', false)
        if not ui_open then OpenUI() end
    end

    local now = reaper.time_precise()
    if now - last_theme_check > 0.5 then
        last_theme_check = now
        local file = reaper.GetLastColorThemeFile()
        if file ~= last_theme_file then
            last_theme_file = file
            CaptureBaseline()
            LoadPalette()
            last_state = nil
        end
    end

    if settings.enabled then
        local state = TransportState()
        if state ~= last_state then
            last_state = state
            ApplyState(state)
        end
    end

    if not ui_open then return end

    local char = gfx.getchar()
    if char < 0 or char == 27 then
        CloseUI()
        return
    end

    RememberPosition()
    DrawUI()

    local down = gfx.mouse_cap & 1 == 1
    if down and not mouse_down then
        for i = #hot, 1, -1 do
            local r = hot[i]
            if gfx.mouse_x >= r.x and gfx.mouse_x <= r.x + r.w and
                gfx.mouse_y >= r.y and gfx.mouse_y <= r.y + r.h then
                if r.drag then
                    dragging = r
                    r.drag(gfx.mouse_x)
                elseif r.fn then
                    r.fn()
                end
                break
            end
        end
    elseif down and dragging then
        dragging.drag(gfx.mouse_x)
    elseif not down then
        dragging = nil
    end
    mouse_down = down
    gfx.update()
end

local function Tick()
    -- A drawing glitch must not be able to take the color engine down with it,
    -- and must never leave the theme half-painted.
    local ok, err = pcall(Frame)
    if not ok and not error_shown then
        error_shown = true
        reaper.ShowConsoleMsg(TITLE .. ': ' .. tostring(err) .. '\n')
    end
    if not quitting then reaper.defer(Tick) end
end

local function Exit()
    RestoreAll()
    CloseUI()
    SetToggle(false)
    reaper.DeleteExtState(extname, 'heartbeat', false)
    reaper.DeleteExtState(extname, 'show_ui', false)
end

------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------

CaptureBaseline()
LoadPalette()
SetToggle(settings.enabled)
reaper.atexit(Exit)

-- Launched by __startup.lua? Start working, but stay out of the way.
if not (first_run_of_session and IsStartupHookEnabled(true)) then OpenUI() end

Tick()
