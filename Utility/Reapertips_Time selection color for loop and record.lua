--[[
  @description Time selection color for loop and record
  @author Reapertips (Alejandro Hernandez)
  @version 1.2
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
    Each area can also have its own colour: click the small swatch at the end
    of its row. A dot marks the areas that have one; right click the swatch
    to go back to the column colour.
    Clicking any swatch opens a small Hue / Saturation / Brightness picker
    right under it, with nine preset colours on top. Changes show at once; More... opens REAPER's own picker.
    When the whole ruler strip is painted bright, the bar numbers turn dark
    on their own, and the loop bar is pushed lighter or darker so it never
    disappears into the strip.
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
    - Every area can have its own colour: click the swatch at the end of its
      row. A dot marks the areas that have one; right click the swatch to
      follow the column colour again.
    - Colours are picked in a small Hue / Saturation / Brightness popover
      under the swatch, with nine preset colours and live changes. REAPER's
      picker is one click away under More...
    - Cleaner settings window: plain check marks, one column per state
      (check, bar, swatch), and the % only shows while you drag.
    - The bar numbers turn dark when the painted ruler strip is bright, so
      they stay readable at any colour.
    - The loop bar no longer disappears when the ruler strip is painted in
      the same colour: it is pushed lighter or darker automatically.
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
local PREVIEW_KEYS = { 'col_arrangebg' }

-- The bar numbers and ticks in the ruler. Never painted with the user's
-- color: only flipped to dark or light when a painted ruler strip would make
-- the theme's own text hard to read.
local TEXT_KEYS = {
    { key = 'col_tl_fg',  dark = { 0x16, 0x16, 0x16 }, light = { 0xEE, 0xEE, 0xEE } },
    { key = 'col_tl_fg2', dark = { 0x3C, 0x3C, 0x3C }, light = { 0xB4, 0xB4, 0xB4 } },
}

-- Minimum brightness difference (0..1) before the text or the loop bar is
-- pushed away from a painted ruler strip.
local TEXT_CONTRAST = 0.40
local BAR_CONTRAST  = 0.20
local BAR_PUSH      = 0.60

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
local W, H  = 480, 332
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

-- Mix two native colors.
local function MixNative(base, over, amount)
    local br, bg, bb = reaper.ColorFromNative(base)
    local r, g, b = reaper.ColorFromNative(over)
    return reaper.ColorToNative(
        math.floor(br + (r - br) * amount + 0.5),
        math.floor(bg + (g - bg) * amount + 0.5),
        math.floor(bb + (b - bb) * amount + 0.5))
end

-- Perceived brightness, 0..1
local function Luma(native)
    local r, g, b = reaper.ColorFromNative(native)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255
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

-- Any area can have its own color; without one it uses its column's color.
local function RowKey(state, zone)
    return 'row.' .. theme_key .. '.' .. state .. '.' .. zone
end

local function LoadRowColors()
    palette.row = {}
    for _, st in ipairs(STATES) do
        palette.row[st.id] = {}
        for _, z in ipairs(ZONES) do
            local hex = GetExt(RowKey(st.id, z.id), ''):upper()
            if hex:match('^%x%x%x%x%x%x$') then
                palette.row[st.id][z.id] = hex
            end
        end
    end
end

local function LoadColumnColors()
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

local function LoadPalette()
    theme_key = ThemeKey()
    LoadColumnColors()
    LoadRowColors()
end

local function SavePalette()
    SetExt('theme.' .. theme_key, palette.loop .. ',' .. palette.rec)
end

local function ZoneColor(state, zone)
    return palette.row[state][zone] or palette[state]
end

-- nil goes back to the column color. nosave: memory only, while a color is
-- being dragged; the popover saves once it closes.
local function SetRowColor(state, zone, hex, nosave)
    if hex == palette[state] then hex = nil end
    palette.row[state][zone] = hex
    if nosave then return end
    if hex then
        SetExt(RowKey(state, zone), hex)
    else
        reaper.DeleteExtState(extname, RowKey(state, zone), true)
    end
end

local function ResetPalette()
    reaper.DeleteExtState(extname, 'theme.' .. theme_key, true)
    for _, st in ipairs(STATES) do
        for _, z in ipairs(ZONES) do
            reaper.DeleteExtState(extname, RowKey(st.id, z.id), true)
        end
    end
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
    for _, t in ipairs(TEXT_KEYS) do
        t.live = reaper.GetThemeColor(t.key, 0) >= 0
    end
end

local function CaptureBaseline()
    baseline, applied = {}, {}
    RescanZones()
    for _, z in ipairs(ZONES) do
        for _, key in ipairs(z.live) do Baseline(key) end
    end
    for _, t in ipairs(TEXT_KEYS) do
        if t.live then Baseline(t.key) end
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
    for _, t in ipairs(TEXT_KEYS) do RestoreColor(t.key) end
    Flush()
end

local function RGBNative(rgb)
    return reaper.ColorToNative(rgb[1], rgb[2], rgb[3])
end

-- Every color a state paints: theme key -> native. A key that is missing
-- keeps the theme's own color.
local function StateColors(state)
    local out = {}
    for _, z in ipairs(ZONES) do
        if z.supported and settings.paint[state][z.id] then
            local amount = settings.tint[state][z.id] / 100
            for _, key in ipairs(z.live) do
                -- each area is blended over its OWN theme color, so areas
                -- that start out lighter or darker keep their relationship
                local base = Baseline(key)
                if base then
                    out[key] = Blend(base, ZoneColor(state, z.id), amount)
                end
            end
        end
    end

    -- A painted ruler strip can swallow the bar numbers and the loop bar.
    -- Push whichever is too close to it towards black or white.
    local strip = out['col_tl_bg']
    if not strip then return out end
    local bright = Luma(strip) > 0.5

    for _, t in ipairs(TEXT_KEYS) do
        local fg = t.live and Baseline(t.key)
        if fg and math.abs(Luma(fg) - Luma(strip)) < TEXT_CONTRAST then
            out[t.key] = RGBNative(bright and t.dark or t.light)
        end
    end

    local bar = out['col_tl_bgsel2'] or Baseline('col_tl_bgsel2')
    if bar and math.abs(Luma(bar) - Luma(strip)) < BAR_CONTRAST then
        local to = bright and RGBNative({ 0, 0, 0 })
            or RGBNative({ 0xFF, 0xFF, 0xFF })
        out['col_tl_bgsel2'] = MixNative(bar, to, BAR_PUSH)
    end
    return out
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
    local colors = StateColors(state)
    local function Apply(key)
        if colors[key] then ForceColor(key, colors[key]) else RestoreColor(key) end
    end
    for _, z in ipairs(ZONES) do
        for _, key in ipairs(z.live) do Apply(key) end
    end
    for _, t in ipairs(TEXT_KEYS) do
        if t.live then Apply(t.key) end
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
local pop          = nil -- the open color popover
local OpenPop, ClosePop  -- defined with the popover
local hot          = {}
local S            = 1
local last_state   = nil
local quitting     = false
local dragging     = nil
local mouse_down   = false
local rmouse_down  = false
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
    ClosePop()
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

-- rfn: right click
local function AddHot(x, y, w, h, fn, drag, rfn)
    local r = { x = x, y = y, w = w, h = h, fn = fn, drag = drag, rfn = rfn }
    hot[#hot + 1] = r
    return r
end

local function Text(x, y, str)
    gfx.x, gfx.y = x, y
    gfx.drawstr(str)
end

local function TextH()
    local _, h = gfx.measurestr('Ag')
    return h
end

-- A neutral box with a check mark, so the only colored squares in the window
-- are colors.
local function CheckBox(x, y, box, checked, disabled)
    if not checked then
        SetCol(disabled and COL_LINE or COL_BOX)
        gfx.rect(x, y, box, box, 0)
        return
    end
    SetCol(disabled and COL_DIM or COL_TEXT)
    gfx.rect(x, y, box, box, 1)
    SetCol(COL_BG)
    local x1, y1 = x + box * 0.24, y + box * 0.52
    local x2, y2 = x + box * 0.42, y + box * 0.70
    local x3, y3 = x + box * 0.77, y + box * 0.30
    for k = 0, math.max(1, math.floor(1.6 * S)) - 1 do
        gfx.line(x1, y1 + k, x2, y2 + k, 1)
        gfx.line(x2, y2 + k, x3, y3 + k, 1)
    end
end

-- Left-aligned checkbox with a label. Returns its full width.
local function Checkbox(x, y, label, checked, fn, disabled)
    local box = math.floor(15 * S)
    CheckBox(x, y, box, checked, disabled)
    SetCol(disabled and COL_DIM or COL_TEXT)
    local tw, th = gfx.measurestr(label)
    Text(x + box + 9 * S, y + (box - th) / 2, label)
    if not disabled then
        AddHot(x, y - 3 * S, box + 9 * S + tw, box + 6 * S, fn)
    end
    return box + 9 * S + tw
end

-- One cell of the matrix: on/off box, how strong, and the area's color. Each
-- state is one column of those three. 100 % replaces the theme color
-- outright, anything less mixes the two.
local CELL_BOX  = 15
local CELL_GAP  = 8
local CELL_BAR  = 60
local CELL_SW   = 22
local CELL_SWH  = 14
local COL_SWH   = 18 -- the column's own swatch, right above the row swatches
local CELL_W    = CELL_BOX + CELL_GAP + CELL_BAR + CELL_GAP + CELL_SW

local function px1() return math.max(1, math.floor(S)) end

-- The % only shows while its bar is being dragged; drawn last, over the rest.
local drag_label = nil

local function Cell(x, y, state, zone, disabled)
    local box = math.floor(CELL_BOX * S)
    local on  = settings.paint[state][zone]
    local pct = settings.tint[state][zone]
    local hex = ZoneColor(state, zone)

    CheckBox(x, y, box, on, disabled)
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
    local fill = math.floor(bw * pct / 100)
    gfx.rect(bx, by, fill, bh, 1)

    local id = state .. '.' .. zone
    if dragging and dragging.cell == id then
        drag_label = { x = bx + fill, y = by, text = pct .. '%' }
    end

    if not disabled then
        local r = AddHot(bx - 4 * S, y - 4 * S, bw + 8 * S, box + 8 * S, nil,
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
        r.cell = id
    end

    -- This area's own color. A dot means it no longer follows the column.
    -- Right click puts it back.
    if disabled then return end
    local own = palette.row[state][zone] ~= nil
    local sw  = math.floor(CELL_SW * S)
    local sh  = math.floor(CELL_SWH * S)
    local sx  = x + math.floor((CELL_W - CELL_SW) * S)
    local sy  = y + math.floor((box - sh) / 2)
    SetHex(hex, on and 1 or 0.35)
    gfx.rect(sx, sy, sw, sh, 1)
    SetCol(COL_BOX, on and 1 or 0.5)
    gfx.rect(sx, sy, sw, sh, 0)
    if pop and pop.owner == id then
        SetCol(COL_TEXT)
        gfx.rect(sx - px1(), sy - px1(), sw + 2 * px1(), sh + 2 * px1(), 0)
    end
    if own then
        SetHex(palette.loop)
        gfx.circle(sx + sw + math.floor(4 * S), sy - math.floor(2 * S),
            math.floor(3 * S), 1, 1)
    end
    AddHot(sx - 3 * S, y - 4 * S, sw + 6 * S, box + 8 * S, function()
        OpenPop(state, zone, sx, sy, sw, sh)
        if not settings.paint[state][zone] then
            settings.paint[state][zone] = true
            SavePaint(state, zone)
            last_state = nil
        end
    end, nil, function()
        ClosePop()
        gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
        local item = own and 'Use column color' or '#Use column color'
        if gfx.showmenu(item) == 1 then
            SetRowColor(state, zone, nil)
            last_state = nil
        end
    end)
end

-- The column's color, in the swatch column of its cells
local function Swatch(cx, y, state)
    local w, h = math.floor(CELL_SW * S), math.floor(COL_SWH * S)
    local x = cx + math.floor((CELL_W - CELL_SW) * S)
    SetHex(palette[state])
    gfx.rect(x, y, w, h, 1)
    SetCol((pop and pop.owner == state) and COL_TEXT or COL_BOX)
    gfx.rect(x, y, w, h, 0)
    AddHot(x, y, w, h, function() OpenPop(state, nil, x, y, w, h) end)
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

local function Link(x, y, label, fn)
    local tw, th = gfx.measurestr(label)
    SetCol(COL_DIM)
    Text(x, y, label)
    AddHot(x, y - 3 * S, tw, th + 6 * S, fn)
    return tw
end

-- A fake ruler + arrange, painted the way the chosen state would paint them
local function Preview(x, y, w)
    local sh   = math.floor(6 * S)   -- time signature lane
    local rh   = math.floor(22 * S)
    local ah   = math.floor(34 * S)
    local top  = y
    local c    = StateColors(preview)
    local sel1 = math.floor(x + w * 0.26)
    local sel2 = math.floor(x + w * 0.64)
    local px   = math.max(1, math.floor(S))

    -- time signature lane
    SetNative(c.ts_lane_bg or Baseline('ts_lane_bg') or 0x2E2E2E)
    gfx.rect(x, y, w, sh, 1)
    y = y + sh

    -- ruler strip
    SetNative(c.col_tl_bg or Baseline('col_tl_bg') or 0x2B2B2B)
    gfx.rect(x, y, w, rh, 1)

    -- ticks and bar numbers
    gfx.setfont(2, FONT, math.floor(9 * S))
    local fg  = c.col_tl_fg or Baseline('col_tl_fg')
    local fg2 = c.col_tl_fg2 or Baseline('col_tl_fg2') or fg
    for i = 0, 5 do
        local tx = math.floor(x + w * i / 6)
        if fg2 then SetNative(fg2, 0.6) else SetCol(COL_TEXT, 0.30) end
        gfx.rect(tx, y, px, math.floor(rh * 0.6), 1)
        if fg then SetNative(fg) else SetCol(COL_TEXT, 0.85) end
        Text(tx + math.floor(3 * S), y + px, 1 + i * 4 .. '.1')
    end
    gfx.setfont(1, FONT, math.floor(FSIZE * S))

    -- The loop bar at the bottom of the ruler, with its two triangular loop
    -- markers. This is `col_tl_bgsel2`, the "ruler" row.
    local band = math.max(3, math.floor(rh * 0.20))
    local by = y + rh - band
    SetNative(c.col_tl_bgsel2 or Baseline('col_tl_bgsel2') or 0x808080)
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
    SetNative(c.col_tl_bgsel or Baseline('col_tl_bgsel') or 0x808080, 0.22)
    gfx.rect(sel1, y, sel2 - sel1, ah, 1)

    SetCol(COL_LINE)
    gfx.rect(x, top, w, sh + rh + ah, 0)
    return sh + rh + ah
end

-- REAPER's own color picker. Returns the chosen hex, or nil when cancelled.
local function SystemPicker(current)
    -- pcall because it is missing on some builds
    local ok, ret, col = pcall(reaper.GR_SelectColor, nil,
        HexToNative(current))
    Beat()
    -- Cancel returns 0, which Lua counts as true: test for it, or a cancel
    -- paints the color black.
    if ok and ret and ret ~= 0 and col then return NativeToHex(col) end
    return nil
end

local function TypeHex(current)
    local ok, csv = reaper.GetUserInputs(
        TITLE, 1, 'Hex color (RRGGBB),extrawidth=60', current)
    Beat()
    if not ok then return nil end
    local hex = csv:gsub('#', ''):gsub('%s', ''):upper()
    if hex:match('^%x%x%x%x%x%x$') then return hex end
    return nil
end

------------------------------------------------------------------------------
-- Color popover: Hue / Saturation / Brightness under the clicked swatch.
-- Every change applies at once; it is saved when the popover closes.
------------------------------------------------------------------------------

local POP_W, POP_PAD, POP_ROW, POP_VAL = 236, 12, 24, 30
local POP_BTN_H, POP_HEX_W, POP_ARROW = 22, 76, 6
local POP_PRESET_H, POP_PRESET_GAP = 18, 5
local COL_POP = { 0x2E, 0x2F, 0x32 }

-- Starting points across the top of the popover
local POP_PRESETS = { 'FFC21E', 'FD7308', 'E94546', 'FF5FA2', 'B15CFF',
    '4C7DFF', '22C7D6', '4FD16A', 'E8E8E8' }

local function RGBToHSV(hex)
    local r, g, b = HexToRGB(hex)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d, h = mx - mn, 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h * 60
    end
    return h, mx > 0 and d / mx or 0, mx
end

-- h 0..360, s and v 0..1. Returns r, g, b 0..255.
local function HSVToRGB(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
    local function q(u) return math.floor((u + m) * 255 + 0.5) end
    return q(r), q(g), q(b)
end

local function HSVToHex(h, s, v)
    return string.format('%02X%02X%02X', HSVToRGB(h, s, v))
end

local function PopColor(p)
    if p.zone then return ZoneColor(p.state, p.zone) end
    return palette[p.state]
end

local function PopSet(p, hex, nosave)
    if p.zone then
        SetRowColor(p.state, p.zone, hex, nosave)
    else
        palette[p.state] = hex
        if not nosave then SavePalette() end
    end
    last_state = nil
end

-- the H / S / V the sliders show, from a whole color. A gray keeps its hue.
local function PopFromHex(p, hex)
    local h, s, v = RGBToHSV(hex)
    p.s, p.v = math.floor(s * 100 + 0.5), math.floor(v * 100 + 0.5)
    if s > 0 and v > 0 then p.h = math.floor(h + 0.5) % 360 end
end

function ClosePop()
    if not pop then return end
    PopSet(pop, PopColor(pop))
    pop = nil
    dragging = nil -- a slider drag must not outlive its popover
end

-- A second click on the swatch that opened it closes it again.
local closed_owner = nil

function OpenPop(state, zone, x, y, w, h)
    local owner = zone and (state .. '.' .. zone) or state
    if closed_owner == owner then return end
    ClosePop()
    pop = { state = state, zone = zone, owner = owner,
        ax = x, ay = y, aw = w, ah = h }
    pop.orig = PopColor(pop)
    pop.h = 0
    PopFromHex(pop, pop.orig)
end

-- Where the popover goes: under its swatch, above it when there is no room.
local function PopRect()
    local p   = pop
    local pw  = math.floor(POP_W * S)
    local ph  = math.floor((POP_PAD * 2 + POP_PRESET_H + 10 + POP_ROW * 3 + 8 +
        POP_BTN_H) * S)
    local gap = math.floor((POP_ARROW + 4) * S)
    local x = math.floor(p.ax + p.aw / 2 - pw / 2)
    x = Clamp(x, math.floor(8 * S), gfx.w - pw - math.floor(8 * S))
    local below = p.ay + p.ah + gap + ph <= gfx.h - math.floor(4 * S)
    local y = below and (p.ay + p.ah + gap) or (p.ay - gap - ph)
    y = math.max(math.floor(4 * S), y)
    return x, y, pw, ph, below
end

local function InPop(mx, my)
    if not pop then return false end
    local x, y, w, h = PopRect()
    local a = math.floor(POP_ARROW * S)
    return mx >= x and mx <= x + w and my >= y - a and my <= y + h + a
end

local function DrawPop()
    if not pop then return end
    local p = pop
    local x, y, w, h, below = PopRect()
    local a = math.floor(POP_ARROW * S)

    -- the panel swallows its own clicks
    AddHot(x, y - a, w, h + a * 2, function() end)

    SetCol(COL_POP)
    gfx.rect(x, y, w, h, 1)
    SetCol(COL_BOX)
    gfx.rect(x, y, w, h, 0)
    -- the arrow, pointing at the swatch
    local acx = Clamp(math.floor(p.ax + p.aw / 2), x + a * 2, x + w - a * 2)
    for k = 0, a do
        local yy = below and (y - k) or (y + h - 1 + k)
        SetCol(COL_POP)
        gfx.rect(acx - (a - k), yy, (a - k) * 2 + 1, 1, 1)
        SetCol(COL_BOX)
        gfx.rect(acx - (a - k), yy, 1, 1, 1)
        gfx.rect(acx + (a - k), yy, 1, 1, 1)
    end

    gfx.setfont(2, FONT, math.floor(12 * S))
    local pad  = math.floor(POP_PAD * S)
    local ix   = x + pad
    local labw = gfx.measurestr('Brightness') + math.floor(12 * S)
    local valw = math.floor(POP_VAL * S)
    local tx   = ix + labw
    local tw   = x + w - pad - valw - tx
    local th   = math.floor(5 * S)
    local r    = math.floor(6 * S)
    local yy   = y + pad
    local rowh = math.floor(POP_ROW * S)
    local fh   = TextH()

    local function Apply()
        PopSet(p, HSVToHex(p.h, p.s / 100, p.v / 100), true)
    end

    -- presets: a click jumps the sliders there, ready to fine-tune
    local now  = PopColor(p)
    local gap  = math.floor(POP_PRESET_GAP * S)
    local ph   = math.floor(POP_PRESET_H * S)
    local pw   = (w - pad * 2 - gap * (#POP_PRESETS - 1)) / #POP_PRESETS
    for i, hex in ipairs(POP_PRESETS) do
        local px0 = math.floor(ix + (i - 1) * (pw + gap))
        local pwi = math.floor(ix + i * (pw + gap) - gap) - px0
        SetHex(hex)
        gfx.rect(px0, yy, pwi, ph, 1)
        if hex == now then
            SetCol(COL_TEXT)
            local o = math.floor(2 * S)
            gfx.rect(px0 - o, yy - o, pwi + o * 2, ph + o * 2, 0)
        end
        AddHot(px0, yy, pwi, ph, function()
            PopFromHex(p, hex)
            PopSet(p, hex, true)
        end)
    end
    yy = yy + ph + math.floor(10 * S)

    local function Slider(label, key, max, color_at)
        local cy = yy + math.floor(rowh / 2)
        SetCol(COL_TEXT)
        Text(ix, cy - fh / 2, label)
        -- the track in the color's own gradient
        for i = 0, tw - 1 do
            gfx.set(color_at(i / math.max(1, tw - 1)))
            gfx.rect(tx + i, cy - th / 2, 1, th, 1)
        end
        local kx = tx + math.floor(tw * p[key] / max + 0.5)
        SetCol({ 0xC8, 0xCB, 0xD0 })
        gfx.circle(kx, cy, r, 1, 1)
        SetCol(COL_DIM)
        local v = tostring(p[key])
        Text(x + w - pad - gfx.measurestr(v), cy - fh / 2, v)
        AddHot(tx - r, yy, tw + r * 2, rowh, nil, function(mx)
            local v2 = math.floor(Clamp((mx - tx) / tw, 0, 1) * max + 0.5)
            if v2 == p[key] then return end
            p[key] = v2
            Apply()
        end)
        yy = yy + rowh
    end

    local function F(r8, g8, b8) return r8 / 255, g8 / 255, b8 / 255, 1 end
    Slider('Hue', 'h', 359, function(t) return F(HSVToRGB(t * 360, 1, 1)) end)
    Slider('Saturation', 's', 100,
        function(t) return F(HSVToRGB(p.h, t, p.v / 100)) end)
    Slider('Brightness', 'v', 100,
        function(t) return F(HSVToRGB(p.h, p.s / 100, t)) end)
    yy = yy + math.floor(8 * S)

    -- hex: click to type one
    local bh  = math.floor(POP_BTN_H * S)
    local hw  = math.floor(POP_HEX_W * S)
    local cur = PopColor(p)
    SetCol(COL_BG)
    gfx.rect(ix, yy, hw, bh, 1)
    SetCol(COL_BOX)
    gfx.rect(ix, yy, hw, bh, 0)
    SetCol(COL_TEXT)
    local label = '#' .. cur
    Text(ix + math.floor((hw - gfx.measurestr(label)) / 2), yy + (bh - fh) / 2,
        label)
    AddHot(ix, yy, hw, bh, function()
        local hex = TypeHex(cur)
        if hex then PopFromHex(p, hex); PopSet(p, hex, true) end
    end)

    -- a dot once it differs from where it started: click to go back
    if cur ~= p.orig then
        local dx = ix + hw + math.floor(9 * S)
        local dy = yy + math.floor(bh / 2)
        SetHex(palette.loop)
        gfx.circle(dx, dy, math.floor(3 * S), 1, 1)
        AddHot(dx - 6 * S, yy, 12 * S, bh, function()
            PopFromHex(p, p.orig)
            PopSet(p, p.orig, true)
        end)
    end

    -- More...: REAPER's own picker
    if reaper.GR_SelectColor then
        local more = 'More...'
        local mw = gfx.measurestr(more) + math.floor(20 * S)
        local mx = x + w - pad - mw
        SetCol(COL_PILL)
        gfx.rect(mx, yy, mw, bh, 1)
        SetCol(COL_BOX)
        gfx.rect(mx, yy, mw, bh, 0)
        SetCol(COL_TEXT)
        Text(mx + math.floor(10 * S), yy + (bh - fh) / 2, more)
        AddHot(mx, yy, mw, bh, function()
            local hex = SystemPicker(cur)
            if hex then PopFromHex(p, hex); PopSet(p, hex, true) end
        end)
    end
    gfx.setfont(1, FONT, math.floor(FSIZE * S))
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

-- "Colors for <theme>", cut to fit the room left of the columns
local function ThemeTitle(x, y, maxw)
    local pre = 'Colors for '
    SetCol(COL_DIM)
    Text(x, y, pre)
    local nx = x + gfx.measurestr(pre)
    local name = theme_key
    while #name > 1 and gfx.measurestr(name) > maxw - (nx - x) do
        -- drop one whole UTF-8 character: its continuation bytes, then its
        -- lead byte
        while #name > 1 and name:byte(-1) >= 0x80 and name:byte(-1) < 0xC0 do
            name = name:sub(1, -2)
        end
        name = name:sub(1, -2)
        if gfx.measurestr(name .. '\u{2026}') <= maxw - (nx - x) then
            name = name .. '\u{2026}'
            break
        end
    end
    SetCol(COL_TEXT)
    Text(nx, y, name)
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
    local col   = { rec = rec_x, loop = rec_x - cw - math.floor(18 * S) }
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

    -- column headers: name over the bars, the column color over the swatches
    local swh = math.floor(COL_SWH * S)
    ThemeTitle(x, y + (swh - th) / 2, col.loop - x - math.floor(12 * S))
    gfx.setfont(2, FONT, math.floor(12 * S))
    local hh = TextH()
    for _, st in ipairs(STATES) do
        SetCol(COL_DIM)
        Text(col[st.id] + math.floor((CELL_BOX + CELL_GAP) * S),
            y + math.floor((swh - hh) / 2), st.label)
        Swatch(col[st.id], y, st.id)
    end
    gfx.setfont(1, FONT, math.floor(FSIZE * S))
    y = y + swh + math.floor(12 * S)

    drag_label = nil
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
        pop = nil
        ResetPalette()
        last_state = nil
    end)
    local quit = 'Quit script'
    Link(gfx.w - pad - gfx.measurestr(quit), y, quit, function()
        quitting = true
    end)

    -- the % of the bar being dragged, in a tag above its fill
    if drag_label then
        gfx.setfont(2, FONT, math.floor(11 * S))
        local tw, tth = gfx.measurestr(drag_label.text)
        local bw2 = tw + math.floor(8 * S)
        local bh2 = tth + math.floor(2 * S)
        local lx = math.floor(Clamp(drag_label.x - bw2 / 2, 0, gfx.w - bw2))
        local ly = drag_label.y - bh2 - math.floor(3 * S)
        SetCol(COL_POP)
        gfx.rect(lx, ly, bw2, bh2, 1)
        SetCol(COL_BOX)
        gfx.rect(lx, ly, bw2, bh2, 0)
        SetCol(COL_TEXT)
        Text(lx + math.floor(4 * S), ly + math.floor(1 * S), drag_label.text)
        gfx.setfont(1, FONT, math.floor(FSIZE * S))
    end

    DrawPop()
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
            -- an open popover saves its color to the theme it was edited for
            ClosePop()
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
    if char == 27 and pop then
        ClosePop()
    elseif char < 0 or char == 27 then
        CloseUI()
        return
    end

    RememberPosition()
    DrawUI()

    local down = gfx.mouse_cap & 1 == 1
    if down and not mouse_down then
        -- a click outside the popover closes it, and still reaches what is
        -- under it (another swatch opens the popover there)
        closed_owner = nil
        if pop and not InPop(gfx.mouse_x, gfx.mouse_y) then
            closed_owner = pop.owner
            ClosePop()
        end
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

    local rdown = gfx.mouse_cap & 2 == 2
    if rdown and not rmouse_down then
        for i = #hot, 1, -1 do
            local r = hot[i]
            -- the topmost area under the mouse takes it, so a right click on
            -- the popover never reaches a swatch underneath
            if gfx.mouse_x >= r.x and gfx.mouse_x <= r.x + r.w and
                gfx.mouse_y >= r.y and gfx.mouse_y <= r.y + r.h then
                if r.rfn then r.rfn() end
                break
            end
        end
    end
    rmouse_down = rdown
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
