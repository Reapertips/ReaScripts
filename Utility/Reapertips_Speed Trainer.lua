--[[
  @description Speed Trainer
  @author Reapertips (Alejandro Hernandez)
  @version 1.0.0
  @license MIT
  @link https://www.reapertips.com
  @provides
    [main] Reapertips_Speed Trainer - Advance one step.lua
    [main] Reapertips_Speed Trainer - Back one step.lua
    [main] Reapertips_Speed Trainer - Start pause resume.lua
    [main] Reapertips_Speed Trainer - Toggle hold.lua
  @about
    If there's a difficult section of a song you can play slowly but struggle
    to reach at full speed, **Speed Trainer helps you build up to it
    gradually!**

    Select the section, choose your starting speed and target, then decide how
    quickly you wanna get there. For example, you can start at **70%**,
    increase the speed by **5% every three loops**, and keep practicing until
    you reach **100%**.

    Speed Trainer handles the speed changes while you play. The ring shows
    where you are inside each repetition and warns you before the next
    increase. You can also add a count-in, hold the current speed, go back,
    advance, pause or stop at any time.

    You also get four companion actions for keyboard shortcuts, toolbar
    buttons or a MIDI footswitch. Super useful when your hands are busy
    playing!

    Speed Trainer changes REAPER's master playrate without editing your tempo
    map. If there isn't enough room for the count-in, it can insert the
    required bars at the start of the project in one undoable step.

    You need **REAPER 7.0 or newer** and **ReaImGui 0.10 or newer**.
  @changelog
    First release.
]]

-- Speed Trainer - practice a looped section while REAPER raises the playrate.
--
-- Select the section in the arrange, choose a start and a target percentage,
-- how much to add and how many completed loops to wait, then press Start.
-- The script drives the master playrate only: it never edits the tempo map.
--
-- Requires ReaImGui.

------------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------------

local ST = {
    NAME    = 'Speed Trainer',
    VERSION = '1.0.0',
    EXTNAME = 'RTIPS.SpeedTrainer',
}

-- Native action: Transport: Toggle preserve pitch in audio items when
-- changing master playrate. There is no project-info key for this, so the
-- toggle state of the action is the only reliable source. The id is verified
-- at runtime: GetToggleCommandState returns -1 when an action has no toggle
-- state, and then the feature disables itself instead of lying.
local ACT_PRESERVE_PITCH = 40671

-- Native action: Time selection: Insert empty space at time selection. Used
-- once, by hand, to make room for a count-in at the very start of a song.
local ACT_INSERT_SPACE = 40200

local ImGui
do
    local ok, path = pcall(function() return reaper.ImGui_GetBuiltinPath() end)
    if not ok or not path then
        reaper.MB('Speed Trainer needs ReaImGui.\n\n' ..
            'Install it with ReaPack:\nExtensions > ReaPack > Browse packages ' ..
            '> search "ReaImGui" > install "ReaImGui: ReaScript binding for ' ..
            'Dear ImGui".', 'Speed Trainer', 0)
        return
    end
    package.path = path .. '/?.lua'
    local ok2, mod = pcall(function() return require 'imgui' '0.10' end)
    if not ok2 then
        reaper.MB('Speed Trainer needs ReaImGui 0.10 or newer.\n\n' ..
            'Update it with ReaPack: Extensions > ReaPack > Synchronize ' ..
            'packages.\n\n' .. tostring(mod), 'Speed Trainer', 0)
        return
    end
    ImGui = mod
end

-- Every ReaImGui name this script cannot work without. Checked once at start
-- so a missing one becomes a clear message instead of a crash halfway through
-- a frame.
--
-- Only hard requirements belong here. Anything the window can do without goes
-- through optional() below and degrades quietly: a nicety must never be the
-- reason the window refuses to open.
local API_NAMES = {
    'Begin', 'BeginDisabled', 'Button', 'CalcTextSize', 'Checkbox',
    'Col_Border', 'Col_Button', 'Col_ButtonActive', 'Col_ButtonHovered',
    'Col_CheckMark', 'Col_ChildBg', 'Col_FrameBg', 'Col_FrameBgActive',
    'Col_FrameBgHovered', 'Col_PopupBg', 'Col_Separator', 'Col_Text',
    'Col_TextDisabled', 'Col_TitleBgActive', 'Col_WindowBg', 'Cond_Always',
    'Cond_FirstUseEver', 'ConfigVar_DragClickToInputText', 'CreateContext',
    'DragInt', 'DrawList_AddRect', 'DrawList_AddRectFilled', 'DrawList_AddText',
    'DrawList_PathArcTo', 'DrawList_PathClear', 'DrawList_PathFillConcave',
    'DrawList_PathStroke', 'Dummy', 'End', 'EndDisabled',
    'GetContentRegionAvail', 'GetCursorPosX', 'GetCursorPosY',
    'GetCursorScreenPos', 'GetFrameHeight', 'GetWindowDrawList',
    'GetWindowSize', 'GetWindowWidth', 'InvisibleButton', 'IsItemHovered',
    'IsKeyPressed', 'Key_Escape', 'PopFont', 'PopID', 'PopStyleColor',
    'PopStyleVar', 'PushFont', 'PushID', 'PushStyleColor', 'PushStyleVar',
    'SameLine', 'SetConfigVar', 'SetCursorPos', 'SetCursorPosX',
    'SetCursorPosY', 'SetNextItemWidth', 'SetNextWindowSize',
    'SetNextWindowSizeConstraints', 'SliderFlags_AlwaysClamp',
    'StyleVar_ChildRounding', 'StyleVar_FramePadding', 'StyleVar_FrameRounding',
    'StyleVar_GrabRounding', 'StyleVar_ItemInnerSpacing', 'StyleVar_ItemSpacing',
    'StyleVar_WindowBorderSize', 'StyleVar_WindowPadding',
    'StyleVar_WindowRounding', 'Text', 'WindowFlags_NoCollapse',
    'WindowFlags_NoScrollWithMouse', 'WindowFlags_NoScrollbar',
}

function ST.check_api()
    local missing = {}
    for _, name in ipairs(API_NAMES) do
        local ok, v = pcall(function() return ImGui[name] end)
        if not ok or v == nil then missing[#missing + 1] = name end
    end
    return missing
end

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round(v) return math.floor(v + 0.5) end

local function rgba(rgb, a) return (rgb << 8) | (a or 0xFF) end

-- Percentages the master playrate accepts. REAPER's own slider goes wider,
-- but nothing musical happens outside this and it keeps the inputs honest.
ST.RATE_MIN, ST.RATE_MAX = 10, 400
ST.LOOPS_MIN, ST.LOOPS_MAX = 1, 99
ST.INC_MIN, ST.INC_MAX = 1, 50

------------------------------------------------------------------------------
-- Step engine (pure: no reaper calls below this line until Transport)
------------------------------------------------------------------------------

-- Correct the four inputs in place and return them. Nothing here ever throws
-- a dialog: an impossible value becomes the nearest possible one.
function ST.sanitize(cfg)
    local out = {}
    out.start  = clamp(round(tonumber(cfg.start) or 70), ST.RATE_MIN, ST.RATE_MAX)
    out.target = clamp(round(tonumber(cfg.target) or 100), ST.RATE_MIN, ST.RATE_MAX)
    -- Ascending only in this version. A target below the start would be a
    -- different exercise (backoff), and silently swapping them would be
    -- invisible state.
    if out.target < out.start then out.target = out.start end
    out.inc    = clamp(round(tonumber(cfg.inc) or 3), ST.INC_MIN, ST.INC_MAX)
    out.loops  = clamp(round(tonumber(cfg.loops) or 3), ST.LOOPS_MIN, ST.LOOPS_MAX)
    return out
end

-- 70, 100, 3 -> {70, 73, ... 97, 100}. The last step is always exactly the
-- target, even when the increment does not divide the range.
function ST.build_steps(start_pct, target_pct, inc_pct)
    local steps = { start_pct }
    if target_pct <= start_pct then return steps end
    local v = start_pct
    while true do
        v = v + inc_pct
        if v >= target_pct then
            steps[#steps + 1] = target_pct
            break
        end
        steps[#steps + 1] = v
    end
    return steps
end

local Engine = {}
Engine.__index = Engine

function ST.new_engine(steps, loops_per)
    return setmetatable({
        steps      = steps,
        loops_per  = loops_per,
        idx        = 1,
        loops_done = 0,
        hold       = false,
        finished   = false,
        top_idx    = 1,   -- highest step actually reached
    }, Engine)
end

function Engine:rate() return self.steps[self.idx] end
function Engine:next_rate() return self.steps[self.idx + 1] end
function Engine:total_steps() return #self.steps end

function Engine:total_loops() return #self.steps * self.loops_per end

function Engine:loops_completed()
    return (self.idx - 1) * self.loops_per + self.loops_done
end

function Engine:progress()
    local total = self:total_loops()
    if total <= 0 then return 0 end
    return self:loops_completed() / total
end

-- True while the loop now playing is the last one before a rate change.
function Engine:on_last_loop()
    if self.hold or self.finished then return false end
    if self.idx >= #self.steps and self.loops_done == self.loops_per - 1 then
        return false   -- the last loop of all: it completes, it does not step
    end
    return self.loops_done == self.loops_per - 1
end

-- Called once per genuinely completed loop.
-- Returns 'same', 'stepped' or 'finished'.
function Engine:loop_done()
    if self.finished then return 'finished' end
    self.loops_done = self.loops_done + 1
    if self.loops_done < self.loops_per then return 'same' end
    if self.hold then
        -- Hold keeps repeating this rate: bank the loop, start counting again.
        self.loops_done = 0
        return 'same'
    end
    if self.idx >= #self.steps then
        self.finished = true
        return 'finished'
    end
    self.idx = self.idx + 1
    if self.idx > self.top_idx then self.top_idx = self.idx end
    self.loops_done = 0
    return 'stepped'
end

function Engine:back()
    self.finished = false
    if self.idx > 1 then self.idx = self.idx - 1 end
    self.loops_done = 0
    return self:rate()
end

function Engine:advance()
    if self.idx < #self.steps then
        self.idx = self.idx + 1
        if self.idx > self.top_idx then self.top_idx = self.idx end
        self.loops_done = 0
        return self:rate()
    end
    self.loops_done = 0
    return self:rate()
end

function Engine:toggle_hold()
    self.hold = not self.hold
    return self.hold
end

------------------------------------------------------------------------------
-- Loop detection (pure)
------------------------------------------------------------------------------

-- REAPER exposes GetPlayLoopCnt only to C extensions (its second parameter is
-- an INT64*, which ReaScript cannot pass), so loops are counted from the play
-- position. Verified against REAPER 7.79: reaper.GetPlayLoopCnt is nil.
--
-- A genuine wrap and a manual seek both move the position backwards. They are
-- told apart by distance: between two frames the position advances by about
-- dt * playrate seconds, so a real wrap satisfies
--     (loop_end - prev) + (cur - loop_start) ~= dt * playrate
-- while a seek jumps an arbitrary amount. prev must also already be in the
-- tail of the loop, which rejects a seek that lands on the loop start.
function ST.detect_loop(prev, cur, ls, le, dt, rate)
    local len = le - ls
    if len <= 0 then return false end
    if dt <= 0 or dt > 0.5 then return false end   -- hitch: resync, do not count
    if cur >= prev then return false end
    local expected = dt * rate
    if expected <= 0 then return false end
    local traveled = (le - prev) + (cur - ls)
    -- Audio runs in blocks, so a frame can straddle a block boundary. The
    -- tolerance is generous in absolute terms and proportional for fast rates.
    local tol = math.max(0.15, expected * 2.0)
    if math.abs(traveled - expected) > tol then return false end
    -- prev has to be near the end already.
    local tail = math.max(math.min(len * 0.5, 2.0), expected * 3)
    if prev < le - tail then return false end
    return true
end

------------------------------------------------------------------------------
-- Persistence
------------------------------------------------------------------------------

local function get_ext(key, default)
    local v = reaper.GetExtState(ST.EXTNAME, key)
    if v == nil or v == '' then return default end
    return v
end

local function set_ext(key, value)
    reaper.SetExtState(ST.EXTNAME, key, tostring(value), true)
end

ST.UI_DEFAULT = { scale = 1.0 }
ST.ui = { scale = ST.UI_DEFAULT.scale }

ST.cfg = {
    start = 70, target = 100, inc = 3, loops = 3,
    preserve_pitch = true,
    restore = true,
    at_target = 'stop',   -- 'stop' | 'keep'
    count_in = false,
    count_in_bars = 2,
}

ST.COUNTIN_MIN, ST.COUNTIN_MAX = 1, 8

function ST.load_cfg()
    local c = ST.cfg
    c.start  = tonumber(get_ext('start',  '70'))  or 70
    c.target = tonumber(get_ext('target', '100')) or 100
    c.inc    = tonumber(get_ext('inc',    '3'))   or 3
    c.loops  = tonumber(get_ext('loops',  '3'))   or 3
    c.preserve_pitch = get_ext('preserve_pitch', '1') == '1'
    c.restore        = get_ext('restore', '1') == '1'
    c.at_target      = get_ext('at_target', 'stop') == 'keep' and 'keep' or 'stop'
    c.count_in       = get_ext('count_in', '0') == '1'
    c.count_in_bars  = clamp(round(tonumber(get_ext('count_in_bars', '2')) or 2),
        ST.COUNTIN_MIN, ST.COUNTIN_MAX)
    local s = ST.sanitize(c)
    c.start, c.target, c.inc, c.loops = s.start, s.target, s.inc, s.loops
    return c
end

function ST.save_cfg()
    local c = ST.cfg
    set_ext('start', c.start)
    set_ext('target', c.target)
    set_ext('inc', c.inc)
    set_ext('loops', c.loops)
    set_ext('preserve_pitch', c.preserve_pitch and '1' or '0')
    set_ext('restore', c.restore and '1' or '0')
    set_ext('at_target', c.at_target)
    set_ext('count_in', c.count_in and '1' or '0')
    set_ext('count_in_bars', c.count_in_bars)
end

------------------------------------------------------------------------------
-- REAPER state: capture and restore
------------------------------------------------------------------------------

ST.orig = nil

function ST.preserve_pitch_supported()
    return reaper.GetToggleCommandState(ACT_PRESERVE_PITCH) ~= -1
end

function ST.preserve_pitch_on()
    return reaper.GetToggleCommandState(ACT_PRESERVE_PITCH) == 1
end

function ST.set_preserve_pitch(want)
    if not ST.preserve_pitch_supported() then return false end
    if ST.preserve_pitch_on() ~= want then
        reaper.Main_OnCommand(ACT_PRESERVE_PITCH, 0)
    end
    return true
end

function ST.capture_state()
    local ls, le = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    -- Written out rather than with `and ... or nil`: preserve pitch being
    -- off is a real value, and that idiom would turn it into nil and never
    -- restore it.
    local pitch = nil
    if ST.preserve_pitch_supported() then pitch = ST.preserve_pitch_on() end
    ST.orig = {
        rate    = reaper.Master_GetPlayRate(0),
        repeat_ = reaper.GetSetRepeatEx(0, -1),
        pitch   = pitch,
        loop_s  = ls,
        loop_e  = le,
        cursor  = reaper.GetCursorPosition(),
    }
    return ST.orig
end

function ST.restore_state()
    local o = ST.orig
    if not o then return false end
    ST.orig = nil
    reaper.CSurf_OnPlayRateChange(o.rate)
    reaper.GetSetRepeatEx(0, o.repeat_)
    if o.pitch ~= nil then ST.set_preserve_pitch(o.pitch) end
    reaper.GetSet_LoopTimeRange(true, true, o.loop_s, o.loop_e, false)
    reaper.SetEditCurPos2(0, o.cursor, false, false)
    return true
end

------------------------------------------------------------------------------
-- Session state
------------------------------------------------------------------------------

local S = {
    mode      = 'setup',    -- setup | running | paused | done | error
    eng       = nil,
    ls        = 0,
    le        = 0,
    prev_pos  = 0,
    prev_t    = 0,
    resync    = true,
    counting  = false,      -- inside the count-in bars, before the loop
    room_msg  = nil,        -- why making room for the count-in did not work
    pre       = 0,          -- where the count-in starts, in project seconds
    loop_frac = 0,
    win_w     = nil,
    chrome_h  = 46,
    pause_why = nil,        -- 'user' | 'transport' | 'timesel'
    flash_at  = -10,
    started_at = 0,
    elapsed   = 0,
    loops_total = 0,
    warn      = '',
    cmd_seen  = 0,
    quit      = false,
}

function ST.state() return S end

local function now() return reaper.time_precise() end

------------------------------------------------------------------------------
-- Single instance
------------------------------------------------------------------------------

local instance_token = nil
local INSTANCE_STALE_SECS = 3.0

local function read_heartbeat()
    local raw = reaper.GetExtState(ST.EXTNAME, 'heartbeat')
    if not raw or raw == '' then return nil, nil end
    local token, stamp = raw:match('^([^|]+)|([%d%.%-]+)$')
    return token, tonumber(stamp)
end

function ST.acquire_instance()
    local token, stamp = read_heartbeat()
    local t = now()
    if token and stamp and t - stamp < INSTANCE_STALE_SECS then return false end
    instance_token = tostring({})
    reaper.SetExtState(ST.EXTNAME, 'heartbeat',
        instance_token .. '|' .. ('%.17g'):format(t), false)
    return true
end

function ST.refresh_instance()
    if not instance_token then return false end
    local token, stamp = read_heartbeat()
    local t = now()
    if token and token ~= instance_token and stamp
        and t - stamp < INSTANCE_STALE_SECS then return false end
    reaper.SetExtState(ST.EXTNAME, 'heartbeat',
        instance_token .. '|' .. ('%.17g'):format(t), false)
    return true
end

function ST.release_instance()
    local token = read_heartbeat()
    if instance_token and token == instance_token then
        reaper.SetExtState(ST.EXTNAME, 'heartbeat', '', false)
    end
    instance_token = nil
end

------------------------------------------------------------------------------
-- Loop source and tempo
------------------------------------------------------------------------------

function ST.time_selection()
    local ls, le = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if le - ls < 0.05 then return nil, nil end
    return ls, le
end

-- Bars and seconds of the current selection, plus whether the tempo map
-- changes inside it. A single BPM number would be a lie across a tempo change.
function ST.loop_info(ls, le)
    local info = { secs = le - ls, bars = nil, constant = true, bpm = nil }
    local ok, m0 = pcall(function()
        local beats, measures, measure_len = reaper.TimeMap2_timeToBeats(0, ls)
        if not measure_len or measure_len <= 0 then return nil end
        return measures + beats / measure_len
    end)
    local ok2, m1 = pcall(function()
        local beats, measures, measure_len = reaper.TimeMap2_timeToBeats(0, le)
        if not measure_len or measure_len <= 0 then return nil end
        return measures + beats / measure_len
    end)
    if ok and ok2 and m0 and m1 then info.bars = m1 - m0 end

    local b0 = reaper.TimeMap2_GetDividedBpmAtTime(0, ls)
    local b1 = reaper.TimeMap2_GetDividedBpmAtTime(0, le - 0.001)
    info.bpm = b0
    if math.abs(b0 - b1) > 0.0001 then info.constant = false end
    local n = reaper.CountTempoTimeSigMarkers(0)
    for i = 0, n - 1 do
        local _, pos = reaper.GetTempoTimeSigMarker(0, i)
        if pos and pos > ls + 0.0001 and pos < le - 0.0001 then
            info.constant = false
            break
        end
    end
    return info
end

-- How long the whole session will take, in seconds. A loop of `loop_secs`
-- played at 70% takes loop_secs / 0.70, so the total is the sum over every
-- step. Truthful, not a guess: it is the only number in Setup a guitarist can
-- actually plan around.
function ST.session_seconds(steps, loops_per, loop_secs)
    if not loop_secs or loop_secs <= 0 then return nil end
    local total = 0
    for _, pct in ipairs(steps) do
        total = total + loop_secs / (pct / 100)
    end
    return total * loops_per
end

-- 0:14.2 - the loop length and the practice time, minutes and seconds.
function ST.fmt_clock(s)
    local m = math.floor(s / 60)
    return ('%d:%04.1f'):format(m, s - m * 60)
end

function ST.fmt_bars(bars)
    local text = ('%.2f'):format(bars):gsub('0+$', ''):gsub('%.$', '')
    return text .. (math.abs(bars - 1) < 1e-9 and ' bar' or ' bars')
end

-- Where playback has to start so the loop begins `bars` bars later. Working
-- in measures rather than seconds keeps the count-in on the grid even when
-- the section does not start on a bar line, and it survives a tempo change
-- inside the pre-roll.
--
-- Second return: the run-up did not fit. A count-in of one bar where four
-- were asked for is not a count-in, it is a surprise, so the window says so
-- and offers to make the room instead of quietly giving you less.
function ST.count_in_pos(ls, bars)
    bars = tonumber(bars) or 0
    if bars < 1 then return nil end
    if ls <= 0 then return nil, true end
    local ok, t = pcall(function()
        local beats, measures = reaper.TimeMap2_timeToBeats(0, ls)
        -- Not clamped to bar zero: a run-up that reaches in front of the
        -- project is clipped to zero seconds below, and clamping the measure
        -- instead would hand back the section itself.
        return reaper.TimeMap2_beatsToTime(0, beats, measures - bars)
    end)
    if not (ok and type(t) == 'number') then
        -- No beatsToTime in this build: four beats to the bar at the tempo
        -- where the section starts is close enough to give the player time.
        local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, ls)
        if not bpm or bpm <= 0 then return nil end
        t = ls - bars * 4 * 60 / bpm
    end
    local clipped = false
    if t < 0 then
        t = 0
        clipped = true
    end
    if t >= ls - 0.05 then return nil, true end
    return t, clipped
end

-- Make the room the count-in needs, at the very front of the project.
--
-- The action id is a hypothesis like every other one here, so the result is
-- measured rather than assumed: if the project did not get longer, nothing
-- happened and the window says so instead of pretending. One undo block, so
-- Cmd+Z puts the project back exactly as it was.
function ST.insert_space(bars)
    local ls, le = ST.time_selection()
    if not ls then return false, 'Select a time selection first' end
    local ok, span = pcall(function()
        return reaper.TimeMap2_beatsToTime(0, 0, bars)
    end)
    if not ok or type(span) ~= 'number' or span <= 0 then
        return false, 'This REAPER cannot measure the bars'
    end
    local before = reaper.GetProjectLength(0)
    reaper.Undo_BeginBlock()
    reaper.GetSet_LoopTimeRange(true, false, 0, span, false)
    reaper.Main_OnCommand(ACT_INSERT_SPACE, 0)
    local grew = reaper.GetProjectLength(0) - before
    if grew < span - 0.01 then
        reaper.GetSet_LoopTimeRange(true, false, ls, le, false)
        reaper.Undo_EndBlock('Speed Trainer: insert space', -1)
        return false, 'This REAPER did not insert the space'
    end
    reaper.GetSet_LoopTimeRange(true, false, ls + span, le + span, false)
    reaper.GetSet_LoopTimeRange(true, true, ls + span, le + span, false)
    reaper.Undo_EndBlock('Speed Trainer: space for the count-in', -1)
    return true
end

-- "1 bars" is the kind of thing that makes a window look unfinished.
function ST.bars_word(n)
    return ('%d %s'):format(n, n == 1 and 'bar' or 'bars')
end

function ST.fmt_duration(secs)
    if not secs then return '' end
    if secs < 90 then return ('about %d s'):format(round(secs / 5) * 5) end
    local mins = secs / 60
    if mins < 10 then return ('about %d min'):format(round(mins)) end
    return ('about %d min'):format(round(mins / 5) * 5)
end

------------------------------------------------------------------------------
-- Transport control
------------------------------------------------------------------------------

local function apply_rate(pct)
    reaper.CSurf_OnPlayRateChange(pct / 100)
end

function ST.start()
    local ls, le = ST.time_selection()
    if not ls then
        S.mode = 'error'
        S.warn = 'Select a time selection first'
        return false
    end
    local c = ST.sanitize(ST.cfg)
    ST.cfg.start, ST.cfg.target = c.start, c.target
    ST.cfg.inc, ST.cfg.loops = c.inc, c.loops
    ST.save_cfg()

    ST.capture_state()
    S.ls, S.le = ls, le
    -- Drive the loop points explicitly. Whether the user has loop points
    -- linked to the time selection is a preference, and the trainer should
    -- not depend on it.
    reaper.GetSet_LoopTimeRange(true, true, ls, le, false)
    reaper.GetSetRepeatEx(0, 1)
    if ST.cfg.preserve_pitch then ST.set_preserve_pitch(true) end

    S.eng = ST.new_engine(ST.build_steps(c.start, c.target, c.inc), c.loops)
    apply_rate(S.eng:rate())

    local pre = ST.cfg.count_in
        and ST.count_in_pos(ls, ST.cfg.count_in_bars) or nil
    S.counting = pre ~= nil
    S.pre = pre or ls
    reaper.SetEditCurPos2(0, S.pre, false, true)
    if reaper.GetPlayState() & 1 == 0 then reaper.OnPlayButton() end

    S.mode = 'running'
    S.prev_pos, S.prev_t, S.resync = S.pre, now(), true
    S.loop_frac = 0
    S.started_at, S.elapsed, S.loops_total = now(), 0, 0
    S.warn = ''
    S.flash_at = now()
    return true
end

function ST.pause(why)
    if S.mode ~= 'running' then return end
    S.mode = 'paused'
    S.pause_why = why or 'user'
    S.elapsed = S.elapsed + (now() - S.started_at)
    if why ~= 'transport' and reaper.GetPlayState() & 1 == 1 then
        reaper.OnPauseButton()
    end
end

function ST.resume()
    if S.mode ~= 'paused' then return end
    -- Resuming after the user moved the time selection adopts the new loop.
    local ls, le = ST.time_selection()
    if not ls then
        S.warn = 'Select a time selection first'
        return
    end
    S.ls, S.le = ls, le
    reaper.GetSet_LoopTimeRange(true, true, ls, le, false)
    reaper.GetSetRepeatEx(0, 1)
    apply_rate(S.eng:rate())
    local pre = ST.cfg.count_in
        and ST.count_in_pos(ls, ST.cfg.count_in_bars) or nil
    S.counting = pre ~= nil
    S.pre = pre or ls
    if S.counting then
        -- Resuming into the middle of a repetition is the same lost bar the
        -- count-in exists to prevent, so Resume restarts it from the pre-roll.
        if reaper.GetPlayState() & 2 ~= 0 then reaper.OnPlayButton() end
        reaper.SetEditCurPos2(0, S.pre, false, true)
        if reaper.GetPlayState() & 1 == 0 then reaper.OnPlayButton() end
    elseif reaper.GetPlayState() & 1 == 0 then
        reaper.SetEditCurPos2(0, ls, false, true)
        reaper.OnPlayButton()
    elseif reaper.GetPlayState() & 2 ~= 0 then
        reaper.OnPlayButton()
    end
    S.loop_frac = 0
    S.mode = 'running'
    S.pause_why = nil
    S.warn = ''
    S.started_at = now()
    S.prev_pos, S.prev_t, S.resync = reaper.GetPlayPosition2Ex(0), now(), true
end

function ST.stop(restore)
    local had_session = ST.orig ~= nil
    if S.mode == 'running' then
        S.elapsed = S.elapsed + (now() - S.started_at)
    end
    if had_session and reaper.GetPlayState() & 1 == 1 then reaper.OnStopButton() end
    local should_restore = restore == true or (restore ~= false and ST.cfg.restore)
    if had_session and should_restore then ST.restore_state() else ST.orig = nil end
    S.mode = 'setup'
    S.pause_why = nil
    S.counting = false
    S.warn = ''
end

function ST.finish()
    S.elapsed = S.elapsed + (now() - S.started_at)
    S.mode = 'done'
    S.counting = false
    if ST.cfg.at_target == 'stop' then
        if reaper.GetPlayState() & 1 == 1 then reaper.OnStopButton() end
    end
end

local function on_loop_completed()
    S.loops_total = S.loops_total + 1
    local what = S.eng:loop_done()
    if what == 'stepped' then
        apply_rate(S.eng:rate())
        S.flash_at = now()
    elseif what == 'finished' then
        ST.finish()
    end
end

-- Exposed so the tests can drive one frame at a time.
function ST.poll()
    if S.mode ~= 'running' then return end
    local t = now()
    local ps = reaper.GetPlayState()

    if ps & 1 == 0 then
        ST.pause('transport')
        return
    end
    if ps & 2 ~= 0 then          -- paused in REAPER: freeze, do not count
        S.resync = true
        S.prev_t = t
        return
    end

    -- Both ranges are watched. The trainer drives the loop points itself, but
    -- the section the user thinks they are practicing is the time selection,
    -- and whether REAPER keeps the two linked is a preference.
    local ls, le = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if math.abs(ls - S.ls) > 1e-6 or math.abs(le - S.le) > 1e-6
        or math.abs(ts - S.ls) > 1e-6 or math.abs(te - S.le) > 1e-6 then
        ST.pause('timesel')
        return
    end

    local cur = reaper.GetPlayPosition2Ex(0)
    local dt = t - S.prev_t

    -- The count-in walks the same ring, but nothing is counted here: the
    -- pre-roll is not a repetition, it is the time to get your hands ready.
    if S.counting then
        if cur >= S.ls then
            S.counting = false
            S.loop_frac = 0
            S.resync = true
        else
            S.loop_frac = clamp((cur - S.pre) / (S.ls - S.pre), 0, 1)
        end
        S.prev_pos, S.prev_t = cur, t
        return
    end

    -- Where we are inside this repetition, 0 to 1. This is what the ring
    -- draws, and it is the one number that tells you when the speed changes.
    S.loop_frac = clamp((cur - S.ls) / (S.le - S.ls), 0, 1)
    if S.resync then
        S.resync = false
    elseif ST.detect_loop(S.prev_pos, cur, S.ls, S.le, dt, S.eng:rate() / 100) then
        on_loop_completed()
    end
    S.prev_pos, S.prev_t = cur, t
end

------------------------------------------------------------------------------
-- Companion actions
------------------------------------------------------------------------------

-- The four action scripts write "<serial>|<name>" here. A serial rather than
-- a bare name so two presses of the same button are two commands.
function ST.poll_commands()
    local raw = reaper.GetExtState(ST.EXTNAME, 'cmd')
    if raw == nil or raw == '' then return end
    local serial, name = raw:match('^(%d+)|(%a+)$')
    if not serial then return end
    serial = tonumber(serial)
    if serial <= S.cmd_seen then return end
    S.cmd_seen = serial
    ST.command(name)
end

-- A command remains in non-persistent ExtState until REAPER exits. Adopt its
-- serial when the window opens so a command from the previous instance is not
-- replayed by the new one.
function ST.sync_command_serial()
    local raw = reaper.GetExtState(ST.EXTNAME, 'cmd')
    local serial = raw and raw:match('^(%d+)|%a+$')
    S.cmd_seen = tonumber(serial) or 0
end

function ST.command(name)
    if name == 'startstop' then
        if S.mode == 'running' then ST.pause('user')
        elseif S.mode == 'paused' then ST.resume()
        else
            -- Done still owns the state captured before the last session.
            -- Restore it before a new session captures its own baseline.
            if S.mode == 'done' then ST.stop() end
            ST.start()
        end
        return
    end
    if not S.eng or (S.mode ~= 'running' and S.mode ~= 'paused') then return end
    if name == 'hold' then
        S.eng:toggle_hold()
    elseif name == 'back' then
        S.eng:back()
        apply_rate(S.eng:rate())
        S.flash_at = now()
    elseif name == 'advance' then
        S.eng:advance()
        apply_rate(S.eng:rate())
        S.flash_at = now()
    end
end

------------------------------------------------------------------------------
-- Palette
------------------------------------------------------------------------------

local C = {}

function ST.build_palette()
    C.text        = rgba(0xD2D4DA)
    C.text_bright = rgba(0xEFF1F4)
    C.text_dim    = rgba(0x9A9CA4)
    C.text_faint  = rgba(0x7C7E86)
    C.win         = rgba(0x232326)
    C.card        = rgba(0xFFFFFF, 0x0B)
    C.panel       = rgba(0xFFFFFF, 0x0A)
    C.line        = rgba(0x33333A)
    C.line_bright = rgba(0xFFFFFF, 0x2E)
    C.field       = rgba(0xFFFFFF, 0x08)
    C.frame       = rgba(0xFFFFFF, 0x0D)
    C.frame_hover = rgba(0xFFFFFF, 0x14)
    C.button      = rgba(0xFFFFFF, 0x0F)
    C.button_hov  = rgba(0xFFFFFF, 0x18)
    C.accent      = rgba(0x3B9EFF)
    C.accent_dim  = rgba(0x3B9EFF, 0x33)
    C.accent_soft = rgba(0x3B9EFF, 0x55)
    C.accent_past = rgba(0x3B9EFF, 0x4D)
    C.accent_text = rgba(0xCFE6FF)
    C.amber       = rgba(0xFFB454)
    C.cyan        = rgba(0x4FD6E0)
    -- Hold gets a hue of its own. Cyan and green sat too close together in
    -- the one state where both segments are lit at once (held and paused),
    -- and amber is already spoken for by "the change is one loop away".
    C.hold_dim    = rgba(0xA78BFA, 0x3D)
    C.hold_text   = rgba(0xE4DBFF)
    C.hold_line   = rgba(0xC4B5FD)
    C.green       = rgba(0x39D98A)
    C.green_dim   = rgba(0x39D98A, 0x33)
    C.green_text  = rgba(0xD3F6E6)
    C.warn        = rgba(0xFF8A8A)
    C.track       = rgba(0xFFFFFF, 0x14)
    C.clear       = rgba(0x000000, 0x00)
end




------------------------------------------------------------------------------
-- Test hook: everything below this point needs a live ImGui context.
------------------------------------------------------------------------------

if SPEEDTRAINER_TEST == 'engine' then return ST end

local ctx = ImGui.CreateContext(ST.NAME)

-- A ReaImGui name the script would like but can live without. Returns nil
-- when this build does not have it.
local function optional(name)
    local ok, v = pcall(function() return ImGui[name] end)
    if ok and v ~= nil then return v end
    return nil
end

-- Holding a stepper to repeat is a convenience, not the feature. Dear ImGui
-- moved it from PushButtonRepeat to the ItemFlags_ButtonRepeat item flag, and
-- some builds expose neither, so all three cases are handled and none of them
-- stops the window from opening. (Verified the hard way on 2026-08-24: a
-- string being present in the extension binary says nothing about whether the
-- Lua binding exposes it. Only REAPER can answer that.)
-- Resizing needs to know whether the user is still holding the border. While
-- they are, the window is left alone; forcing a size into the middle of a
-- drag makes it shake, because our height and their mouse fight over the same
-- pixels every frame. Missing, we simply keep the old width-only lock.
local mouse_down do
    local fn, btn = optional('IsMouseDown'), optional('MouseButton_Left')
    if fn and btn then mouse_down = function() return fn(ctx, btn) end end
end

local push_repeat, pop_repeat
do
    local push, pop = optional('PushButtonRepeat'), optional('PopButtonRepeat')
    local pushf, popf = optional('PushItemFlag'), optional('PopItemFlag')
    local flag = optional('ItemFlags_ButtonRepeat')
    if push and pop then
        push_repeat = function() push(ctx, true) end
        pop_repeat = function() pop(ctx) end
    elseif pushf and popf and flag then
        push_repeat = function() pushf(ctx, flag, true) end
        pop_repeat = function() popf(ctx) end
    else
        push_repeat = function() end
        pop_repeat = function() end
    end
end

-- Alt for one, Cmd (Ctrl away from macOS) for ten. Both are conveniences on
-- top of the stride the field already uses, so a build without GetKeyMods
-- simply always steps by the plain stride.
local key_mods
do
    local fn = optional('GetKeyMods')
    local alt, ctrl, super = optional('Mod_Alt'), optional('Mod_Ctrl'),
        optional('Mod_Super')
    if fn and alt then
        key_mods = function()
            local m = fn(ctx)
            return m & alt ~= 0,
                ((ctrl and m & ctrl ~= 0) or (super and m & super ~= 0)) and true
                    or false
        end
    end
end

local set_tooltip = optional('SetTooltip')

-- One button carries the whole window, and it should read like it. A build
-- without CreateFont keeps the regular weight and nothing else changes.
local font_bold
do
    local create, attach = optional('CreateFont'), optional('Attach')
    local bold = optional('FontFlags_Bold')
    if create and attach and bold then
        local ok, f = pcall(create, 'sans-serif', bold)
        if ok and f and pcall(attach, ctx, f) then font_bold = f end
    end
end

------------------------------------------------------------------------------
-- One canvas, one size
------------------------------------------------------------------------------

-- Setup and the playing HUD are laid out on the same canvas and the window
-- never resizes itself between them: pressing Start must not make the window
-- jump. The user drags the window to the size they want and everything in it
-- grows, because the scale is simply how wide the window is.
--
-- Every number below is the approved mockup, one for one. The workshop keeps
-- a drawing of it in mockup.html; when you change a number here, change it
-- there too or the drawing stops being evidence.
ST.CANVAS_W, ST.CANVAS_H = 480, 290

function ST.canvas() return ST.CANVAS_W, ST.CANVAS_H end

local function PX(n) return math.max(1, math.floor(n * ST.ui.scale + 0.5)) end
local function FS(n) return math.max(7, n * ST.ui.scale) end

-- Type sizes, from the mockup.
local T_HEAD, T_LINK   = 11, 11.5     -- loop info, Settings
local T_CAP,  T_NUM    = 10, 24       -- START / TARGET..., the editable numbers
local T_SUM,  T_GO     = 12.5, 16     -- 7 steps · 28 loops..., START TRAINING
local T_PCT,  T_BPM    = 46, 12       -- inside the ring
local T_STAT           = 24           -- 5 / 11 and 85%
local T_CUE,  T_SEG    = 11.5, 12     -- the status line, the transport labels

-- Vertical rhythm of the setup grid, straight off the drawing:
-- caption 13, six of air, field, 22 to the caption below it.
local CAP_H, CAP_AIR, ROW_AIR = 13, 6, 22

local STYLE_C, STYLE_V

function ST.build_style()
    STYLE_C = {
        { ImGui.Col_WindowBg,       C.win },
        { ImGui.Col_ChildBg,        C.card },
        { ImGui.Col_PopupBg,        C.win },
        { ImGui.Col_Text,           C.text },
        { ImGui.Col_TextDisabled,   C.text_faint },
        { ImGui.Col_Border,         rgba(0x000000, 0x8C) },
        { ImGui.Col_FrameBg,        C.field },
        { ImGui.Col_FrameBgHovered, C.frame },
        { ImGui.Col_FrameBgActive,  C.frame_hover },
        { ImGui.Col_Button,         C.button },
        { ImGui.Col_ButtonHovered,  C.button_hov },
        { ImGui.Col_ButtonActive,   C.accent_soft },
        { ImGui.Col_Separator,      C.line },
        { ImGui.Col_CheckMark,      C.accent },
        { ImGui.Col_TitleBgActive,  C.win },
    }
    STYLE_V = {
        { ImGui.StyleVar_WindowRounding,   PX(10) },
        { ImGui.StyleVar_WindowBorderSize, 0 },
        { ImGui.StyleVar_WindowPadding,    PX(18), PX(16) },
        { ImGui.StyleVar_ChildRounding,    PX(8) },
        { ImGui.StyleVar_FrameRounding,    PX(7) },
        { ImGui.StyleVar_GrabRounding,     PX(7) },
        { ImGui.StyleVar_FramePadding,     PX(9), PX(7) },
        { ImGui.StyleVar_ItemSpacing,      PX(9), PX(8) },
        { ImGui.StyleVar_ItemInnerSpacing, PX(6), PX(6) },
    }
end

local function push_style()
    for _, c in ipairs(STYLE_C) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
    for _, v in ipairs(STYLE_V) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
end

local function pop_style()
    ImGui.PopStyleVar(ctx, #STYLE_V)
    ImGui.PopStyleColor(ctx, #STYLE_C)
end

------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------

local function text_col(col, s)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col)
    ImGui.Text(ctx, s)
    ImGui.PopStyleColor(ctx)
end

local function label(size, col, s)
    ImGui.PushFont(ctx, nil, FS(size))
    text_col(col, s)
    ImGui.PopFont(ctx)
end

local function measure(size, s)
    ImGui.PushFont(ctx, nil, FS(size))
    local w, h = ImGui.CalcTextSize(ctx, s)
    ImGui.PopFont(ctx)
    return w, h
end

-- Draw text at an exact place, which is how everything hand-placed is done.
local function put(x, y, size, col, s)
    ImGui.PushFont(ctx, nil, FS(size))
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx), x, y, col, s)
    ImGui.PopFont(ctx)
end

local function centered(s, size, col)
    local x0 = ImGui.GetCursorPosX(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    local w = measure(size, s)
    ImGui.SetCursorPosX(ctx, x0 + math.max(0, (avail - w) * 0.5))
    label(size, col, s)
end

------------------------------------------------------------------------------
-- Icons
--
-- Drawn, never typed. The default font has no dependable glyphs for a play
-- triangle, and a text arrow would sit off center in its line box anyway.
-- Every call here is one Project Launcher already makes, so none of it is a
-- guess about what this ReaImGui exposes.
------------------------------------------------------------------------------

-- An equilateral triangle: three segments of a full turn, filled. Pointing
-- right for play and advance, left for back.
-- Three points of a circle, and exactly three: asking PathArcTo for a whole
-- turn in three segments hands back four, the last one sitting on top of the
-- first. That doubled edge is what read as a bevel down one side of the
-- triangle. Two segments of two thirds of a turn give the same three corners
-- with nothing repeated, so the shape fills flat.
local function icon_triangle(dl, cx, cy, w, right, col)
    local r = w / 1.5
    local a0 = right and 0 or math.pi
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, cx, cy, r, a0, a0 + math.pi * 4 / 3, 2)
    ImGui.DrawList_PathFillConcave(dl, col)
end

local function icon_pause(dl, cx, cy, h, col)
    local bw = math.max(PX(2), h * 0.30)
    local gap = math.max(PX(2), h * 0.23)
    ImGui.DrawList_AddRectFilled(dl, cx - gap * 0.5 - bw, cy - h * 0.5,
        cx - gap * 0.5, cy + h * 0.5, col, PX(1))
    ImGui.DrawList_AddRectFilled(dl, cx + gap * 0.5, cy - h * 0.5,
        cx + gap * 0.5 + bw, cy + h * 0.5, col, PX(1))
end

local function icon_stop(dl, cx, cy, s, col)
    ImGui.DrawList_AddRectFilled(dl, cx - s * 0.5, cy - s * 0.5,
        cx + s * 0.5, cy + s * 0.5, col, PX(2))
end

-- A circle is a square with the rounding turned all the way up. Hollow while
-- Hold is off, filled while it is on: it is a switch, not a transport button.
local function icon_dot(dl, cx, cy, s, filled, col)
    local r = s * 0.5
    if filled then
        ImGui.DrawList_AddRectFilled(dl, cx - r, cy - r, cx + r, cy + r, col, r)
    else
        ImGui.DrawList_AddRect(dl, cx - r, cy - r, cx + r, cy + r, col, r, 0,
            math.max(1, PX(2)))
    end
end

local function draw_icon(dl, kind, cx, cy, col)
    if kind == 'back' then icon_triangle(dl, cx, cy, PX(12), false, col)
    elseif kind == 'advance' then icon_triangle(dl, cx, cy, PX(12), true, col)
    elseif kind == 'play' then icon_triangle(dl, cx, cy, PX(12), true, col)
    elseif kind == 'pause' then icon_pause(dl, cx, cy, PX(13), col)
    elseif kind == 'stop' then icon_stop(dl, cx, cy, PX(11), col)
    elseif kind == 'hold' then icon_dot(dl, cx, cy, PX(11), false, col)
    elseif kind == 'hold_on' then icon_dot(dl, cx, cy, PX(11), true, col)
    end
end

------------------------------------------------------------------------------
-- Ring, pips, staircase
------------------------------------------------------------------------------

-- The ring does not count repetitions: it runs around the repetition that is
-- playing right now. When it closes, the loop restarts.
local function ring(left, top, diameter, frac, col, pct, under)
    local dl = ImGui.GetWindowDrawList(ctx)
    local cx, cy = left + diameter * 0.5, top + diameter * 0.5
    local thick = math.max(PX(4), diameter * 0.08)
    local r = diameter * 0.5 - thick * 0.5
    local TAU = math.pi * 2

    -- The stroke has flat ends, so a full turn from 0 to TAU leaves a visible
    -- seam at three o'clock. Overshooting by a few degrees puts the end under
    -- the start and the circle closes cleanly.
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, cx, cy, r, 0, TAU + 0.18, 72)
    ImGui.DrawList_PathStroke(dl, C.track, 0, thick)
    if frac > 0.001 then
        local a0 = -math.pi * 0.5
        ImGui.DrawList_PathClear(dl)
        ImGui.DrawList_PathArcTo(dl, cx, cy, r, a0, a0 + TAU * frac, 72)
        ImGui.DrawList_PathStroke(dl, col, 0, thick)
    end

    -- The percentage and the tempo are the same fact said two ways, so they
    -- live together in the middle of the ring.
    local pw, ph = measure(T_PCT, pct)
    local uw, uh = measure(T_BPM, under)
    local block = ph + PX(2) + uh
    put(cx - pw * 0.5, cy - block * 0.5, T_PCT, col, pct)
    put(cx - uw * 0.5, cy - block * 0.5 + ph + PX(2), T_BPM, C.text_dim, under)
end

local function pips(x, y, done, total, col)
    local dl = ImGui.GetWindowDrawList(ctx)
    local shown = math.min(total, 6)
    local pw, ph, gap = PX(32), PX(8), PX(7)
    for i = 1, shown do
        local px = x + (i - 1) * (pw + gap)
        ImGui.DrawList_AddRectFilled(dl, px, y, px + pw, y + ph,
            i <= done and col or C.track, PX(4))
    end
    return ph
end

-- One column per speed, ascending. Reading it is the whole point, so it
-- carries no numbers of its own. idx 0 means Setup: nothing has been played
-- yet, so only the two ends are marked.
local function staircase(x, y, w, h, steps, idx, col_now)
    local dl = ImGui.GetWindowDrawList(ctx)
    local n = #steps
    local gap = n > 20 and PX(2) or PX(4)
    local cw = (w - gap * (n - 1)) / n
    local lo, hi = steps[1], steps[n]
    local span = math.max(1, hi - lo)
    for i = 1, n do
        local frac = 0.15 + 0.85 * ((steps[i] - lo) / span)
        local ch = math.max(PX(3), h * frac)
        local cx = x + (i - 1) * (cw + gap)
        local col = C.track
        if idx == 0 then
            if i == 1 then col = C.accent_past elseif i == n then col = col_now end
        elseif i < idx then col = C.accent_past
        elseif i == idx then col = col_now end
        ImGui.DrawList_AddRectFilled(dl, cx, y + h - ch, cx + cw, y + h, col, PX(1))
    end
end

------------------------------------------------------------------------------
-- Small interactive pieces
------------------------------------------------------------------------------

-- A word that lights up when the mouse is on it. No pill, no border: the
-- settings are a way out of the window, not a control competing with the
-- numbers.
local function link(id, text, size)
    ImGui.PushFont(ctx, nil, FS(size))
    local w, h = ImGui.CalcTextSize(ctx, text)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local hit = ImGui.InvisibleButton(ctx, id, w, h)
    local hot = ImGui.IsItemHovered(ctx)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx), x, y,
        hot and C.text_bright or C.text_faint, text)
    ImGui.PopFont(ctx)
    return hit, w
end

-- The minus and the plus are drawn, not typed. A hyphen glyph sits high in
-- its line box and looks off center inside a button however the label is
-- aligned; two rectangles are exactly where they should be at any size.
-- The modifiers have nowhere to live in a window this tight, so they live in
-- a tooltip that only appears if you rest on the button long enough to be
-- asking the question. A short delay would put it in the way of a fast click.
local HOVER_DELAY = 1.2
local hover_key, hover_since = nil, 0
local pending_tip = nil

local function sign_button(id, w, h, plus, tip, key)
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local hit = ImGui.Button(ctx, id, w, h)
    local hot = ImGui.IsItemHovered(ctx)
    if hot and tip and set_tooltip then
        local t = reaper.time_precise()
        if hover_key ~= key then hover_key, hover_since = key, t end
        -- Handed back rather than drawn here: a tooltip takes the font that
        -- is pushed when it is asked for, and here that is the 24 px of the
        -- number. It is drawn once the field has popped that font.
        if t - hover_since >= HOVER_DELAY then pending_tip = tip end
    elseif hover_key == key then
        hover_key = nil
    end
    local col = hot and C.text_bright or C.text_dim
    local cx, cy = x + w * 0.5, y + h * 0.5
    local arm = w * 0.23
    local t = math.max(1, PX(2))
    ImGui.DrawList_AddRectFilled(dl, cx - arm, cy - t * 0.5, cx + arm,
        cy + t * 0.5, col, 0)
    if plus then
        ImGui.DrawList_AddRectFilled(dl, cx - t * 0.5, cy - arm, cx + t * 0.5,
            cy + arm, col, 0)
    end
    return hit
end

------------------------------------------------------------------------------
-- One number: a caption, a minus, the field, a plus
------------------------------------------------------------------------------

-- How far one click moves. Five for a percentage, one for the small counts,
-- and the two modifiers on top of either.
local function stride(base)
    -- A field that already moves one at a time has nothing finer to offer,
    -- so it gets no modifiers and no tooltip promising them.
    if base <= 1 or not key_mods then return base end
    local alt, big = key_mods()
    if alt then return 1 end
    if big then return 10 end
    return base
end

-- Stepping by five lands on multiples of five, the way a grid would:
-- 73 + 5 is 75, not 78. Off-grid values only ever come from dragging or
-- typing, and this is how they get back on it.
local function nudge(value, step, dir, lo, hi)
    local out
    if step <= 1 then
        out = value + dir
    elseif dir > 0 then
        out = math.floor(value / step) * step + step
    else
        out = math.ceil(value / step) * step - step
    end
    return clamp(round(out), lo, hi)
end

-- One line per modifier, and only the modifiers: what a plain click does is
-- already written on the button you just pressed. Both key names on each
-- line, so the same sentence is true on every system.
local function stride_tip(step)
    if step <= 1 or not key_mods then return nil end
    return 'Press alt/opt to adjust by 1%\nPress ctrl/cmd to adjust by 10%'
end

-- Three ways to change it and none of them has to be taught: the buttons are
-- visible, dragging the number is the gesture REAPER already uses everywhere,
-- and a double click types.
local function number_field(id, caption, value, fmt, lo, hi, w, step)
    step = step or 1
    local changed, out = false, value
    ImGui.PushID(ctx, id)
    -- Text and Dummy both return the cursor to the window margin, so the
    -- column has to remember where it started or the right-hand field lands
    -- on top of the left one. (The mock caught exactly that on 2026-08-24.)
    local cx, cy = ImGui.GetCursorPosX(ctx), ImGui.GetCursorPosY(ctx)
    label(T_CAP, C.text_faint, caption)
    -- Placing the field by hand, not by letting the cursor fall: ItemSpacing
    -- lands twice between a caption and the box below it, which reads as the
    -- caption belonging to the row above.
    ImGui.SetCursorPos(ctx, cx, cy + PX(CAP_H + CAP_AIR))

    ImGui.PushFont(ctx, nil, FS(T_NUM))
    local fh = ImGui.GetFrameHeight(ctx)
    ImGui.PopFont(ctx)
    local bw = PX(30)
    local inner = PX(6)
    local field = w - bw * 2 - inner * 2

    ImGui.PushFont(ctx, nil, FS(T_NUM))
    local tip = stride_tip(step)
    push_repeat()
    if sign_button('##dec', bw, fh, false, tip, id .. '-') then
        changed, out = true, nudge(value, stride(step), -1, lo, hi)
    end
    ImGui.SameLine(ctx, 0, inner)
    ImGui.SetNextItemWidth(ctx, field)
    local dc, dv = ImGui.DragInt(ctx, '##v', value, 0.25, lo, hi, fmt,
        ImGui.SliderFlags_AlwaysClamp)
    if dc then changed, out = true, dv end
    ImGui.SameLine(ctx, 0, inner)
    if sign_button('##inc', bw, fh, true, tip, id .. '+') then
        changed, out = true, nudge(value, stride(step), 1, lo, hi)
    end
    pop_repeat()
    ImGui.PopFont(ctx)

    if pending_tip then
        ImGui.PushFont(ctx, nil, FS(T_HEAD))
        set_tooltip(ctx, pending_tip)
        ImGui.PopFont(ctx)
        pending_tip = nil
    end

    ImGui.PopID(ctx)
    return changed, out, fh
end

------------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------------

local show_options = false

local function draw_setup()
    local ls, le = ST.time_selection()
    local ready = ls ~= nil
    local c = ST.cfg

    -- Header: what is going to loop, and the way into the three settings.
    local loop_text = ''
    if ready then
        local info = ST.loop_info(ls, le)
        local bars = info.bars and (ST.fmt_bars(info.bars) .. '  ·  ') or ''
        loop_text = ('Loop:  %s%s'):format(bars, ST.fmt_clock(info.secs))
    end
    -- A count-in with nowhere to count is the one thing the numbers cannot
    -- fix, so it takes the header, the same slot that asks for a selection,
    -- and brings the only remedy there is with it.
    local short_room = false
    if ready and c.count_in then
        local pos, clipped = ST.count_in_pos(ls, c.count_in_bars)
        short_room = pos == nil or clipped == true
    end
    if not short_room then S.room_msg = nil end

    local x0 = ImGui.GetCursorPosX(ctx)
    local y0 = ImGui.GetCursorPosY(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    -- With no section there is nothing to say about the loop, so the header
    -- slot carries the instruction instead of stacking a second warning under
    -- the button. One line, one place, and it disappears the moment there is
    -- a selection.
    if not ready then
        label(T_HEAD, C.warn, 'Select a time selection first')
    elseif S.room_msg then
        label(T_HEAD, C.warn, S.room_msg)
    elseif short_room then
        -- A word that lights up on hover reads as an instruction to the
        -- player, not as something to press. This one is a button on purpose.
        local msg = 'No room for the count-in'
        label(T_HEAD, C.amber, msg)
        ImGui.SetCursorPos(ctx, x0 + measure(T_HEAD, msg) + PX(12), y0 - PX(3))
        ImGui.PushFont(ctx, nil, FS(T_HEAD))
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, PX(9), PX(3))
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.accent_past)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent_text)
        if ImGui.Button(ctx, ('Add %s##room'):format(ST.bars_word(c.count_in_bars))) then
            local done, why = ST.insert_space(c.count_in_bars)
            S.room_msg = (not done) and why or nil
        end
        ImGui.PopStyleColor(ctx, 4)
        ImGui.PopStyleVar(ctx)
        ImGui.PopFont(ctx)
    else
        label(T_HEAD, C.text_dim, loop_text)
    end
    local word = show_options and 'Close' or 'Settings'
    ImGui.SetCursorPos(ctx, x0 + avail - measure(T_LINK, word), y0)
    if link('##settings', word, T_LINK) then show_options = not show_options end
    ImGui.SetCursorPos(ctx, x0, y0 + PX(14))

    if show_options then
        ImGui.Dummy(ctx, 1, PX(10))
        local pp_ok = ST.preserve_pitch_supported()
        local hit
        if not pp_ok then ImGui.BeginDisabled(ctx) end
        hit, c.preserve_pitch = ImGui.Checkbox(ctx, 'Preserve pitch', c.preserve_pitch)
        if hit then ST.save_cfg() end
        if not pp_ok then
            ImGui.EndDisabled(ctx)
            ImGui.SameLine(ctx)
            label(T_CAP, C.text_faint, '(not in this REAPER)')
        end
        hit, c.restore = ImGui.Checkbox(ctx, 'Restore REAPER settings on Stop or close',
            c.restore)
        if hit then ST.save_cfg() end
        -- The bar count sits on the same line as the switch that turns it on,
        -- grayed out until it means something. One row, one idea.
        ImGui.PushID(ctx, 'countin')
        hit, c.count_in = ImGui.Checkbox(ctx, 'Count-in before the loop',
            c.count_in)
        if hit then ST.save_cfg() end
        ImGui.SameLine(ctx, 0, PX(10))
        if not c.count_in then ImGui.BeginDisabled(ctx) end
        ImGui.SetNextItemWidth(ctx, PX(96))
        local bch, bv = ImGui.DragInt(ctx, '##bars', c.count_in_bars, 0.25,
            ST.COUNTIN_MIN, ST.COUNTIN_MAX,
            c.count_in_bars == 1 and '%d bar' or '%d bars',
            ImGui.SliderFlags_AlwaysClamp)
        if bch then
            c.count_in_bars = bv
            ST.save_cfg()
        end
        if not c.count_in then ImGui.EndDisabled(ctx) end
        ImGui.PopID(ctx)
        local keep = c.at_target == 'keep'
        if ImGui.Button(ctx, keep and 'At target: keep playing'
                or 'At target: stop after the final loops', -1, 0) then
            c.at_target = keep and 'stop' or 'keep'
            ST.save_cfg()
        end
        return
    end

    -- Two columns, two rows. Every number starts and ends on the same x, top
    -- and bottom: that is the whole point of the grid.
    local col = (avail - PX(20)) / 2
    local ch, v, fh

    ImGui.SetCursorPos(ctx, x0, y0 + PX(24))
    ch, v, fh = number_field('start', 'START', c.start, '%d%%',
        ST.RATE_MIN, ST.RATE_MAX, col, 5)
    if ch then c.start = v end
    ImGui.SetCursorPos(ctx, x0 + col + PX(20), y0 + PX(24))
    ch, v = number_field('target', 'TARGET', c.target, '%d%%',
        ST.RATE_MIN, ST.RATE_MAX, col, 5)
    if ch then c.target = v end

    local row2 = y0 + PX(24) + PX(CAP_H + CAP_AIR) + fh + PX(ROW_AIR)
    ImGui.SetCursorPos(ctx, x0, row2)
    ch, v = number_field('inc', 'SPEED UP BY', c.inc, '+%d%%',
        ST.INC_MIN, ST.INC_MAX, col)
    if ch then c.inc = v end
    ImGui.SetCursorPos(ctx, x0 + col + PX(20), row2)
    ch, v = number_field('loops', 'EVERY', c.loops, '%d loops',
        ST.LOOPS_MIN, ST.LOOPS_MAX, col)
    if ch then c.loops = v end

    local san = ST.sanitize(c)
    local steps = ST.build_steps(san.start, san.target, san.inc)
    local secs = ready and ST.session_seconds(steps, san.loops, le - ls) or nil

    -- The summary floats in the gap between the grid and the button, so it
    -- gets the middle of that gap: 25 above, its own 16, 25 below.
    local grid_bottom = row2 + PX(CAP_H + CAP_AIR) + fh
    ImGui.SetCursorPos(ctx, x0, grid_bottom + PX(25))
    centered(('%d steps  ·  %d loops%s'):format(#steps, #steps * san.loops,
        secs and ('  ·  ' .. ST.fmt_duration(secs)) or ''), T_SUM, C.text_dim)

    ImGui.SetCursorPos(ctx, x0, grid_bottom + PX(25) + PX(16) + PX(25))
    if not ready then ImGui.BeginDisabled(ctx) end
    -- Hover brightens the blue. The default hover color is a gray overlay,
    -- which on a colored button reads as the button going dead.
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.accent_past)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent_text)
    ImGui.PushFont(ctx, font_bold, FS(T_GO))
    if ImGui.Button(ctx, 'START TRAINING', -1, PX(48)) then ST.start() end
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx, 4)
    if not ready then ImGui.EndDisabled(ctx) end
end

------------------------------------------------------------------------------
-- Playing
------------------------------------------------------------------------------

-- Color follows state, but the words carry it: amber never appears without
-- the sentence that explains it, and green never without the target reached.
local function hud_color(eng)
    if S.counting then return C.amber end
    if eng:on_last_loop() then return C.amber end
    if now() - S.flash_at < 0.35 then return C.cyan end
    if eng.idx >= eng:total_steps() then return C.green end
    return C.accent
end

local function status_words(eng)
    if S.mode == 'paused' then
        if S.pause_why == 'timesel' then return 'PAUSED - new loop, press RESUME' end
        if S.pause_why == 'transport' then return 'PAUSED - transport stopped' end
        return 'PAUSED'
    end
    if S.counting then return 'COUNT IN - get ready' end
    if eng.hold then return 'HOLD - staying at this speed' end
    if eng:on_last_loop() then
        local nxt = eng:next_rate()
        return nxt and ('%d%% WHEN THE RING CLOSES'):format(nxt) or 'LAST LOOP'
    end
    -- Never empty. A blank line under the staircase reads as something
    -- failing to draw; the word is also the fastest way to see the trainer
    -- is still following the transport.
    return 'PLAYING'
end

-- The line is gray while nothing is happening, blue while Hold holds the
-- speed, amber when the change is one loop away. The color repeats what the
-- word already says, so it never carries meaning on its own.
local function status_color(eng)
    if S.mode == 'paused' then
        return S.pause_why == 'user' and C.text_dim or C.amber
    end
    if S.counting then return C.amber end
    if eng.hold then return C.hold_line end
    if eng:on_last_loop() then return C.amber end
    return C.text_faint
end

-- One bar, five equal segments, hairlines between them. Equal is the point:
-- what the eye looks for in a transport is position, and position only works
-- if every segment is the same size. Pause is marked by color, never by
-- being bigger.
local function transport(items, on_hit)
    local dl = ImGui.GetWindowDrawList(ctx)
    local x0, y0 = ImGui.GetCursorPosX(ctx), ImGui.GetCursorPosY(ctx)
    local sx, sy = ImGui.GetCursorScreenPos(ctx)
    local w = ImGui.GetContentRegionAvail(ctx)
    local h = PX(52)
    local pad = PX(4)
    local seg = w / #items
    ImGui.DrawList_AddRectFilled(dl, sx, sy, sx + w, sy + h, C.button, PX(10))
    for i, it in ipairs(items) do
        local lx = sx + (i - 1) * seg
        ImGui.SetCursorPos(ctx, x0 + (i - 1) * seg, y0)
        local hit = ImGui.InvisibleButton(ctx, '##seg' .. i, seg, h)
        local hot = ImGui.IsItemHovered(ctx)
        -- The highlight is a pill inside the segment, so the middle segments
        -- never show half-rounded corners.
        -- A lit segment may bring its own hue: Hold is holding something, and
        -- Resume is about to move, so neither of them is the blue that just
        -- means "this is the current state".
        local lit_bg = it.tint and it.tint[1] or C.accent_dim
        local lit_tx = it.tint and it.tint[2] or C.accent_text
        if it.lit or hot then
            ImGui.DrawList_AddRectFilled(dl, lx + pad, sy + pad,
                lx + seg - pad, sy + h - pad,
                it.lit and lit_bg or C.button_hov, PX(7))
        end
        if i > 1 then
            ImGui.DrawList_AddRectFilled(dl, lx, sy + PX(12),
                lx + math.max(1, PX(1)), sy + h - PX(12), C.line_bright, 0)
        end
        local tw, th = measure(T_SEG, it.label)
        local iw, gap = PX(13), PX(8)
        local left = lx + (seg - (iw + gap + tw)) * 0.5
        local cy = sy + h * 0.5
        local tcol = it.lit and lit_tx or (hot and C.text_bright or C.text)
        local icol = it.lit and lit_tx or (hot and C.text_bright or C.text_faint)
        draw_icon(dl, it.icon, left + iw * 0.5, cy, icol)
        put(left + iw + gap, cy - th * 0.5, T_SEG, tcol, it.label)
        if hit then on_hit(i) end
    end
    ImGui.SetCursorPos(ctx, x0, y0 + h)
end

local function draw_running()
    local eng = S.eng
    local col = hud_color(eng)
    local rate = eng:rate()
    local dl = ImGui.GetWindowDrawList(ctx)

    local x0, y0 = ImGui.GetCursorPosX(ctx), ImGui.GetCursorPosY(ctx)
    local sx, sy = ImGui.GetCursorScreenPos(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)

    local d = PX(200)
    local info = ST.loop_info(S.ls, S.le)
    local bpm = info.constant and ('%d BPM'):format(round(info.bpm * rate / 100))
        or ('Tempo map x %d%%'):format(rate)
    ring(sx, sy, d, S.loop_frac, col, ('%d%%'):format(rate), bpm)

    -- Everything else lives to the right of the ring, centered against it.
    local rx = sx + d + PX(22)
    local rw = avail - d - PX(22)
    local cap_h = select(2, measure(T_CAP, 'STEP'))
    local val_h = select(2, measure(T_STAT, '0'))
    local block = cap_h + PX(5) + val_h + PX(22) + PX(8) + PX(22) + PX(22)
    local ry = sy + (d - block) * 0.5

    -- The step and the next speed are the two numbers worth reading while
    -- your hands are busy, so they get real size.
    local nxt = eng:next_rate() and ('%d%%'):format(eng:next_rate()) or 'FINAL'
    local cur = ('%d / %d'):format(eng.idx, eng:total_steps())
    local warm = eng:on_last_loop()
    put(rx, ry, T_CAP, C.text_faint, 'STEP')
    put(rx, ry + cap_h + PX(5), T_STAT, C.text_bright, cur)
    local ncw = measure(T_CAP, 'NEXT')
    local nvw = measure(T_STAT, nxt)
    put(rx + rw - ncw, ry, T_CAP, warm and C.amber or C.text_faint, 'NEXT')
    put(rx + rw - nvw, ry + cap_h + PX(5), T_STAT,
        warm and C.amber or C.text_bright, nxt)

    local py = ry + cap_h + PX(5) + val_h + PX(22)
    local ph = pips(rx, py, eng.loops_done, eng.loops_per, col)
    local ty = py + ph + PX(22)
    staircase(rx, ty, rw, PX(22), eng.steps, eng.idx, col)

    local words = status_words(eng)
    if words then
        put(rx, ty + PX(22) + PX(14), T_CUE, status_color(eng), words)
    end

    -- The transport sits on the bottom edge, always visible.
    ImGui.SetCursorPos(ctx, x0, y0 + d + PX(24))
    local paused = S.mode == 'paused'
    transport({
        { label = eng.hold and 'HOLD ON' or 'HOLD',
          icon = eng.hold and 'hold_on' or 'hold', lit = eng.hold,
          tint = { C.hold_dim, C.hold_text } },
        { label = 'BACK', icon = 'back' },
        { label = paused and 'RESUME' or 'PAUSE',
          icon = paused and 'play' or 'pause', lit = true,
          tint = paused and { C.green_dim, C.green_text } or nil },
        { label = 'ADV', icon = 'advance' },
        { label = 'STOP', icon = 'stop' },
    }, function(i)
        if i == 1 then ST.command('hold')
        elseif i == 2 then ST.command('back')
        elseif i == 3 then if paused then ST.resume() else ST.pause('user') end
        elseif i == 4 then ST.command('advance')
        else ST.stop() end
    end)
    local _ = dl
end

------------------------------------------------------------------------------
-- Summary
------------------------------------------------------------------------------

local function draw_done()
    local eng = S.eng
    local x0 = ImGui.GetCursorPosX(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    ImGui.Dummy(ctx, 1, PX(14))
    centered('DONE', 38, C.green)
    ImGui.Dummy(ctx, 1, PX(2))
    centered(('%d%% reached'):format(eng.steps[eng.top_idx]), 14, C.text_dim)
    ImGui.Dummy(ctx, 1, PX(18))

    local rows = {
        { 'Time practicing', ST.fmt_clock(S.elapsed) },
        { 'Loops completed', tostring(S.loops_total) },
        { 'Top speed', ('%d%%'):format(eng.steps[eng.top_idx]) },
    }
    for _, r in ipairs(rows) do
        local y = ImGui.GetCursorPosY(ctx)
        label(13, C.text_dim, r[1])
        ImGui.SetCursorPos(ctx, x0 + avail - measure(13, r[2]), y)
        label(13, C.text, r[2])
    end

    ImGui.Dummy(ctx, 1, PX(18))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent_dim)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_soft)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.accent_past)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.accent_text)
    ImGui.PushFont(ctx, nil, FS(T_GO))
    if ImGui.Button(ctx, 'BACK TO SETUP', -1, PX(48)) then ST.stop() end
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx, 4)
end

------------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------------

function ST.frame()
    if not ST.refresh_instance() then
        S.quit = true
        return false
    end
    ST.poll_commands()
    ST.poll()

    -- The window keeps its shape. Width is the user's; height follows from it,
    -- and so does everything inside, because the scale is the width. Nothing
    -- resizes when the view changes: pressing Start must not move the window.
    local dragging = mouse_down and mouse_down() or false
    if S.win_w and not dragging then
        ImGui.SetNextWindowSize(ctx, S.win_w,
            S.chrome_h + S.win_w * (ST.CANVAS_H / ST.CANVAS_W), ImGui.Cond_Always)
    elseif not S.win_w then
        ImGui.SetNextWindowSize(ctx, ST.CANVAS_W, ST.CANVAS_H + PX(46),
            ImGui.Cond_FirstUseEver)
    end
    ImGui.SetNextWindowSizeConstraints(ctx, PX(320), PX(150), 4000, 4000)

    push_style()
    local visible, open = ImGui.Begin(ctx, ST.NAME, true,
        ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse |
        ImGui.WindowFlags_NoCollapse)
    if visible then
        local ww = ImGui.GetWindowWidth(ctx)
        local _, wh = ImGui.GetWindowSize(ctx)
        local _, avail_h = ImGui.GetContentRegionAvail(ctx)
        -- Title bar plus padding, measured rather than assumed: it comes from
        -- REAPER's own font, which our scale does not control.
        S.chrome_h = wh - avail_h
        -- The shape is locked, and any edge drives it. Whichever dimension
        -- the user moved further since the last frame is the one they meant,
        -- so dragging the corner down grows the window instead of fighting
        -- the height we force back every frame.
        -- The shape is restored once, when the border is let go. Whichever
        -- edge the user pulled furthest out decides the new size, so dragging
        -- the corner grows the window and nothing snaps back under the
        -- mouse while it is moving.
        local ratio = ST.CANVAS_H / ST.CANVAS_W
        local content_h = wh - S.chrome_h
        if dragging then
            S.win_w = nil                     -- their size, untouched
            S.drag_w, S.drag_h = ww, content_h
        elseif S.drag_w then
            S.win_w = math.max(S.drag_w, S.drag_h / ratio)
            S.drag_w, S.drag_h = nil, nil
        else
            S.win_w = ww
        end
        -- While the border is held S.win_w is nil on purpose; the scale still
        -- follows the size the window actually has, so the drag looks live.
        local want_w = S.win_w or ww
        local scale = clamp(want_w / ST.CANVAS_W, 0.55, 4.0)
        if math.abs(scale - ST.ui.scale) > 0.001 then
            ST.ui.scale = scale
            ST.build_style()
        end

        if S.mode == 'setup' or S.mode == 'error' then
            draw_setup()
        elseif S.mode == 'done' then
            draw_done()
        else
            draw_running()
        end
        -- Space belongs to REAPER's transport and is never swallowed here.
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then open = false end
    end
    -- Begin/End must stay balanced even when the window is collapsed or
    -- fully clipped and Begin reports it as not visible.
    ImGui.End(ctx)
    pop_style()
    return open
end

local function loop()
    if S.quit then return end
    local ok, open = pcall(ST.frame)
    if not ok then
        -- A crash still has to hand REAPER back the way it was found.
        ST.stop(true)
        reaper.ShowConsoleMsg('Speed Trainer error: ' .. tostring(open) .. '\n')
        return
    end
    if open then
        reaper.defer(loop)
    else
        ST.stop()
    end
end

function ST.shutdown()
    S.quit = true
    if ST.cfg.restore then ST.restore_state() end
    ST.save_cfg()
    ST.release_instance()
end

if SPEEDTRAINER_TEST then
    ST.acquire_instance()
    return ST
end

do
    local missing = ST.check_api()
    if #missing > 0 then
        reaper.MB('This ReaImGui is missing: ' .. table.concat(missing, ', ') ..
            '\n\nUpdate ReaImGui with ReaPack.', 'Speed Trainer', 0)
        return
    end
end

if not ST.acquire_instance() then
    reaper.MB('Speed Trainer is already open.', 'Speed Trainer', 0)
    return
end

reaper.atexit(ST.shutdown)
ST.load_cfg()
ST.sync_command_serial()
ST.build_palette()
ST.build_style()
-- A double click on any number types into it, instead of ImGui's default
-- ctrl-click, which nobody discovers.
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_DragClickToInputText, 1)
reaper.defer(loop)
