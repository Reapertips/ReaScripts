--[[
  @description TunerBox
  @author Reapertips (Alejandro Hernandez)
  @version 1.0.1
  @license MIT
  @link https://www.reapertips.com
  @provides
    [effect] rtips_tuner_v28
    [main] Reapertips_TunerBox toggle.lua
  @about
    # TunerBox

    A chromatic tuner that lives in REAPER's transport bar.

    It looks for notes from 22 Hz to 1470 Hz, which covers everything from
    a 5 string bass low B to the 5th fret harmonic on a guitar's high E.
    There is nothing to configure for a particular instrument.

    Click the tuning fork to switch it on. The box shows the note you are
    playing with an arrow on each side: the left one lights when you are
    flat, the right one when you are sharp, and both light up in your
    theme's accent colour once you are in tune. Click the readout for a
    large tuner window.

    Right click for options: which input to listen to, reference pitch,
    colours and size. Appearance is remembered per theme.

    ## Keyboard shortcut

    A second action is installed with this one:

        Script: Reapertips_TunerBox toggle.lua

    Bind it to a key to switch the tuner between listening and standby
    without taking your hands off the guitar. It does not start or stop
    TunerBox itself, so the box stays where it is in the transport.

    ## Setup

    None. Pick your input from the right click menu if it is not input 1.

    While the tuner is on it adds a hidden track to your project to listen
    to the input. The track has no master send and its record mode is set to
    "disable (input monitoring only)", so it cannot be heard and cannot
    capture anything. It is removed as soon as you switch the tuner off or
    close the script. Because adding a track counts as a change, REAPER may
    ask to save the project afterwards.

    If you save a project while the tuner is on, the track is saved with it.
    Next time you switch the tuner on in that project the saved track is
    re-used where it sits rather than a new one being made, and if you never
    do, it is cleaned up on its own the next time you change something in
    that project.

    ## Requirements

    - REAPER 6.0 or newer
    - js_ReaScriptAPI extension

    Both are checked at startup and reported plainly if missing.

    ## Credits and licences

    TunerBox is MIT licensed.

    The window, docking and drawing engine is adapted from **Gridbox** by
    Ilias-Timon Poulakis (FeedTheCat), used under the MIT licence:

    > MIT License
    >
    > Copyright (c) 2020 iliaspoulakis
    >
    > Permission is hereby granted, free of charge, to any person obtaining
    > a copy of this software and associated documentation files (the
    > "Software"), to deal in the Software without restriction, including
    > without limitation the rights to use, copy, modify, merge, publish,
    > distribute, sublicense, and/or sell copies of the Software, and to
    > permit persons to whom the Software is furnished to do so, subject to
    > the following conditions:
    >
    > The above copyright notice and this permission notice shall be
    > included in all copies or substantial portions of the Software.
    >
    > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    > EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    > MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    > NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    > LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    > OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    > WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    Pitch detection is a small JSFX installed alongside this script. It
    analyses the selected input and reports the frequency back through gmem.
  @changelog
    - Fixed TunerBox failing to reopen when attached to a toolbar.
    - Preserved its saved size after restarting REAPER.
    - Corrected the audio and update-rate diagnostics.
]]


local box_name = 'TunerBox'
local extname = 'RTIPS.' .. box_name

local box_w
local box_h
local box_x
local box_y

local prev_box_w
local prev_box_h
local prev_box_x
local prev_box_y

local attach_mode
local attach_x
local attach_center_mode
local attach_center_x
local prev_is_centered

local user_bg_color
local user_border_color
local user_text_color
local user_swing_color
local user_corner_radius
local user_adaptive_color
local user_font_height
local user_font_family
local user_font_weight
local user_font_yoffs

local user_snap_size
local user_snap_on_color
local user_snap_off_color
local user_snap_sep_color

local window_hwnd
local prev_window_hwnd
local window_w
local window_h

local prev_time
local prev_window_w
local prev_window_h
local prev_color_theme
local prev_main_mult
local prev_top_window_cnt
local prev_attach_hwnd
local top_window_array = reaper.new_array(4096)
local main_hwnd = reaper.GetMainHwnd()



local drag_x
local drag_y
local swing_drag_x
local is_swing_drag

local is_left_click = false
local is_right_click = false

local snap_w = 0
local prev_is_snap
local prev_is_rel_snap
local prev_is_snap_hovered

local menu_time

local bitmap
local lice_font
local font_size

local snap_bitmap
local bg_bitmap

local prev_bg_color
local prev_bg_corner_r
local prev_snap_color

local is_redraw = false
local is_resize = false
local resize_flags = 0
local resize_cursor

local prev_hover_m_x, prev_hover_m_y
local prev_tooltip
local mouse_x, mouse_y
local hover_cnt = 0


local has_reapack = reaper.ReaPack_BrowsePackages ~= nil
local missing_dependencies = {}

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Composite_Delay then
    if has_reapack then
        table.insert(missing_dependencies, 'js_ReaScriptAPI')
    else
        reaper.MB('Please install js_ReaScriptAPI extension', box_name, 0)
        return
    end
end


local _, script_path, sec, cmd = reaper.get_action_context()
local script_dir = script_path:match('^(.+)[\\/]')

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

if #missing_dependencies > 0 then
    local msg = 'Missing dependencies:\n\n'
    for _, dependency in ipairs(missing_dependencies) do
        msg = msg .. ' - ' .. dependency .. '\n'
    end
    reaper.MB(msg, box_name, 0)

    for i = 1, #missing_dependencies do
        if missing_dependencies[i]:match(' ') then
            missing_dependencies[i] = '"' .. missing_dependencies[i] .. '"'
        end
    end
    reaper.ReaPack_BrowsePackages(table.concat(missing_dependencies, ' OR '))
    return
end

if not reaper.ThemeLayout_GetLayout or not reaper.GetThingFromPoint or
    not reaper.ThemeLayout_GetParameter then
    reaper.MB(('%s needs REAPER 6.0 or newer.\n\nYou are running %s.')
        :format(box_name, reaper.GetAppVersion()), box_name, 0)
    return
end

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Detect operating system
local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OS')
local is_linux = os:match('Other')


local hide_snap = reaper.GetExtState(extname, 'hide_snap') == '1'

local comp_fps = reaper.GetExtState(extname, 'comp_fps')
comp_fps = tonumber(comp_fps) or (is_windows and 30 or 0)
local comp_delay = comp_fps == 0 and 0 or 1 / comp_fps

local attach_window_title = reaper.GetExtState(extname, 'attach_title')
if attach_window_title == '' then attach_window_title = nil end

local attach_window_wait = reaper.GetExtState(extname, 'attach_wait')
if attach_window_wait == '' then attach_window_wait = nil end

local attach_window_child_id = reaper.GetExtState(extname, 'attach_child_id')
attach_window_child_id = tonumber(attach_window_child_id)

local transport_title = reaper.JS_Localize('Transport', 'common')

--============================================================================--
--                             TUNER ENGINE                                   --
--============================================================================--

local JSFX_VERSION = '28'
-- The file name carries the version on purpose. REAPER keeps JSFX code
-- cached per path for the lifetime of the session, so overwriting the same
-- file leaves the OLD code running while the script thinks it updated it.
-- A new path forces a fresh load every time the detector changes.
local JSFX_FILE = 'rtips_tuner_v' .. JSFX_VERSION
-- Where the detector can live, most preferred first:
--   1. installed by ReaPack alongside the script (nothing to write, and
--      ReaPack removes it again when the package is uninstalled)
--   2. written by this script, for anyone who grabbed the .lua on its own
local JSFX_DIRS = {'Reapertips/Tuner', 'Reapertips'}
local JSFX_REL_PATH = JSFX_DIRS[2] .. '/' .. JSFX_FILE
local GMEM_NAME = 'ReapertipsTuner'
-- Keep well clear of gmem[0..2], which the window engine uses for its
-- shared mouse position cache (see GetMousePosition further down).
local GB = 1000

-- gmem_attach selects the namespace for the WHOLE Lua state, and this script
-- needs two of them: the detector's own slots, and the 'mouse_pos' cache the
-- window engine shares with the other transport box scripts. Getting this
-- wrong is what caused 0.9.0's "moving the mouse turns into notes" bug, and
-- leaving it parked on one namespace means the other one is silently broken.
-- So every point of use says which it wants. The switch is a pointer swap
-- and the guard makes repeats free.
local MOUSE_GMEM = 'mouse_pos'
local gmem_ns

function AttachGmem(name)
    if gmem_ns ~= name then
        reaper.gmem_attach(name)
        gmem_ns = name
    end
end

local function GRead(i)
    AttachGmem(GMEM_NAME)
    return reaper.gmem_read(i)
end

local function GWrite(i, v)
    AttachGmem(GMEM_NAME)
    reaper.gmem_write(i, v)
end
local TRACK_TAG = 'RTIPS_TUNER'

local NOTE_NAMES = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#',
                    'B'}

-- The engine this script is built on does `local os = reaper.GetOS()`, which
-- shadows Lua's os table with a string for the rest of the file. Reach the
-- real one through _G so file deletion does not blow up.
local DeleteFile = _G.os and _G.os.remove or function() end

-- All mutable tuner state lives in this table (keeps local count low)
local T = {
    on = false,
    track = nil,
    fx = nil,
    a4 = 440,   -- see the one time reset below
    -- I_RECINPUT value. Mono hardware input n -> n (0 based)
    input = tonumber(reaper.GetExtState(extname, 'input')) or 0,
    -- Linear RMS below which the input is treated as silence (-48 dBFS)
    gate = tonumber(reaper.GetExtState(extname, 'gate')) or 0.0002,
    -- Lowest note the detector looks for. This was a setting until 1.4.0.
    -- Measured against both a real 5 string bass low A and the whole guitar
    -- range with hum and a weak fundamental, the wide range was no less
    -- accurate than the narrow one - 2 wrong readings in 1440 against 3 in
    -- 1300 - and it is the only one that finds a 27.5 Hz A0 at all. All it
    -- costs is reporting rate, 22 a second instead of 55, which is far
    -- faster than the display's own damping. So nobody has to know their
    -- instrument needs a menu.
    low_hz = 22,
    -- display
    text = '---',
    cents = 0,
    disp = 0,           -- damped cents used for drawing
    prev_disp = 0,
    note_since = 0,     -- when the current note first appeared
    settled = false,    -- true once the attack transient is over
    has_pitch = false,
    in_tune = false,
    -- internals
    hist = {},
    trace = {},         -- rolling log of readings, for diagnosing dropouts
    stable_f = nil,     -- last frequency we committed to
    oct_cnt = 0,        -- consecutive readings an octave away from it
    last_beat = -1,
    last_beat_time = 0,
    last_pitch_time = 0,
    poll_time = 0,
    check_time = 0,
    floor = 1,          -- adaptive estimate of the input noise floor
    level = 0,
    disp_step = nil,    -- cents per pixel of the deviation bar
    pub_live = nil,     -- last state published to the toggle action
    swept_proj = nil,   -- SweepOrphanTracks memo
    swept_cnt = nil,
    -- The project the hidden track lives in. The tuner deliberately does
    -- NOT follow the user around project tabs: creating a track dirties a
    -- project, and doing that to every tab somebody visits is not ours to
    -- do. In another tab the box goes quiet ("parked") until clicked.
    proj = nil,
    parked = false,
    err = nil,
}

local JSFX_CODE = [==[
desc:Reapertips Tuner Detector
// version: ]==] .. JSFX_VERSION .. [==[

// Auto-generated by the TunerBox script. Do not edit by hand.
// Reports detected pitch of the incoming audio through gmem:
//   gmem[0] = frequency in Hz
//   gmem[1] = clarity (0-1), 0 means "no pitch"
//   gmem[2] = heartbeat counter
//   gmem[3] = samplerate
//   gmem[4] = rms of the analysis window
//   gmem[5] = version of the JSFX that is actually running
//   gmem[6] = state machine state
//   gmem[7] = decimated samplerate
//   gmem[8] = highest analysed period (in decimated samples)
//   gmem[9]  = id of the instance currently allowed to publish
//   gmem[11] = liveness counter of that instance
//   gmem[13] = decaying peak level of the input
//   gmem[10] = noise gate (linear rms), written by the script
// Written by the script for the big readout, so both views agree exactly:
//   gmem[20] = displayed deviation in cents (already damped)
//   gmem[21] = displayed MIDI note number, 0 = nothing to show
//   gmem[22] = 1 while in tune
//   gmem[23] = 1 once the attack has settled
//   gmem[24] = reference pitch (A4 in Hz)
//   gmem[25] = displayed frequency in Hz
options:gmem=ReapertipsTuner
in_pin:left
in_pin:right
out_pin:left
out_pin:right

@init
// The host script is built on an engine that caches the mouse position in
// gmem[0], gmem[1] and gmem[2]. gmem_attach is per Lua state, so those
// writes land in THIS namespace and used to overwrite frequency, clarity
// and the heartbeat: moving the mouse literally produced notes. Everything
// this effect publishes therefore lives behind a base offset.
GB = 1000;

// ---- memory map ---------------------------------------------------------
FLEN  = 32768;  fbuf  = 0;          // full rate ring (linear, shifted)
DLEN  = 4096;   dbuf  = FLEN;       // decimated ring
                snapD = 36864;      // frozen decimated window   (2048)
                wrk   = 38912;      // NSDF values               (2048)
                snapF = 40960;      // frozen full rate window  (16384)
                wrk2  = 57344;      // refinement values          (512)
// snapF has to hold r_NF samples, and r_NF grows with the period: the
// lowest note in range at 192 kHz is a ~5000 sample period and the
// refinement correlates over 2.2 of them.

fpos = 0;
dpos = 0;
deccnt = 0;
hopcnt = 0;
heartbeat = 0;

dec = max(1, floor(srate / 8000));
dsrate = srate / dec;

lp1 = 0; lp2 = 0; lp3 = 0;
lpc = exp(-2 * $pi * 2200 / srate);
lpc_i = 1 - lpc;

// DC blocker, 15 Hz, well below anything we look for. Without it a DC
// offset - which some interfaces and DI boxes really do have - makes the
// NSDF 1.0 at every lag, so no peak is ever found and the tuner reads
// nothing at all while the level meter looks perfectly healthy.
dcr = exp(-2 * $pi * 15 / srate);
dcx = 0; dcy = 0;

// Search range.
//
//   low:  22 Hz. It has to be below the lowest note anybody will point
//         this at - a 5 string bass low B is 30.9 Hz and people tune those
//         down to A0, 27.5 Hz - because a period longer than tmax does NOT
//         read as "no note". Either the sub harmonic peak at T/2 is the
//         only one in the window, so the tuner confidently reports the note
//         an OCTAVE UP, which is the worst thing a tuner can do, or nothing
//         is found at all. Mains hum falls inside this range and is
//         rejected by the noise gate and the clarity test, not by the
//         search range.
//   high: 1470 Hz, so the 5th fret harmonic on the high E string (1318 Hz)
//         is in range. The decimation lowpass sits at 2200 Hz.
// slo is where the NSDF is computed from, tmin is the shortest period we
// are willing to ACCEPT. They are not the same thing, and conflating them
// cost an octave at the top of the range: the peak picker first has to walk
// past the initial positive lobe of the NSDF, and that lobe ends around a
// quarter of a period. Starting the walk at tmin meant that for a note near
// the top of the range - the 5th fret harmonic on the high E - the walk
// started INSIDE the lobe, skipped straight over the true peak, and locked
// onto the one at twice the period. slo has to sit below a quarter of the
// shortest period we care about, so 2.
slo = 2;
tmin = max(3, floor(dsrate / 1600));
cur_low = 22;
tmax = min(1000, floor(dsrate / cur_low));
NW = min(2048, floor(tmax * 2.5));
// Every lag is measured over the SAME window. This is not an efficiency
// detail, it is what makes the values at different lags comparable, and
// comparing them is the whole of the peak picking step.
//
// Version 1.1.0 made the window proportional to the lag, which made a wide
// search range cheap. On a real bass recording that turned out to move the
// first zero crossing of the correlation - where the peak search starts -
// around between lag 11 and lag 81 from one analysis to the next, because
// the short lags were being measured over a few dozen samples of mostly
// high frequency content. Whenever it landed low, the search would accept a
// spurious peak at a short lag: 8 wrong notes in 122 analyses of a plucked
// A0, against 0 with a fixed window.

// The analysis is spread over many audio blocks so no single block ever
// does more than about WORK multiply-accumulates. The chunks are measured
// in WORK, not in lags: the cost of a lag varies by two orders of magnitude
// across the range, so counting lags left most steps nearly empty and made
// a whole scan take twice the steps it needed.
WORK = 16000;
hop = max(16, floor(srate * 0.002));

state = 0;      // 0 = start scan, 1 = correlating, 2 = refining
scan_tau = 0;
r_lo = 0; r_hi = 0; r_L = 0; r_NF = 0; r_best = 0; r_bestL = 0;
c_Tf = 0; c_clarity = 0;

// Nothing is published from here. A new instance is not necessarily the
// publisher - it may be a leftover on another track - and zeroing the live
// reading on instantiation used to blank the readout of whoever was
// actually running. The configuration slots are written by the publisher
// on every block instead.

watchdog = 0;

// Every JSFX instance that declares this gmem name shares ONE array, so two
// tuner tracks (two project tabs, a leftover track) end up fighting over the
// same slots and the readings jump around. Elect a single publisher.
// A counter in the shared array, not rand(): two instances created in the
// same host tick can draw the same random number, and two instances with
// the same id both believe they are the publisher, forever.
gmem[GB+12] += 1;
inst_id = gmem[GB+12];
is_writer = 0;
seen_live = -1;
seen_cnt = 0;
peak = 0;
// EEL2 has no scientific notation: 1e12 is a syntax error, not a number.
BIG = 1000000000000;
// 150 ms fall, independent of sample rate (the old fixed coefficient fell
// 4x faster at 192 kHz than at 44.1)
peak_c = exp(-1 / (srate * 0.15));
snap_fpos = 0;
lowreq = 0;
max_steps = 4;
steps = 0;

// Remembers the best evidence of a real note over the last few seconds, so
// the status report can tell "nothing ever reached the detector" apart from
// "plenty reached it but none of it was periodic". Called wherever a scan
// concludes, whatever it concluded.
function note_evidence(cl, f)
(
  peak_hold = max(peak_hold * 0.97, peak);
  clar_hold = max(clar_hold * 0.97, cl);
  cl >= 0.6 ? ( last_good = f; );
  gmem[GB+14] = peak_hold;
  gmem[GB+15] = clar_hold;
  gmem[GB+16] = last_good;
);

// ---- start a scan: freeze the analysis window ---------------------------
function scan_start() local(i, e, rms, thr)
(
  dpos < NW ? ( state = 0; ) : (
    // Freeze BOTH windows at this instant. The refinement used to snapshot
    // the full rate buffer when it started, tens of milliseconds later, so
    // on a vibrato the two stages were looking at different pitches and the
    // refinement bracket no longer contained the true peak.
    snap_fpos = fpos;
    memcpy(snapD, dbuf + dpos - NW, NW);

    e = 0; i = 0;
    while (i < NW) ( e += snapD[i] * snapD[i]; i += 1; );
    rms = sqrt(e / NW);
    gmem[GB+4] = rms;

    thr = gmem[GB+10] > 0 ? gmem[GB+10] : 0.0002;
    rms < thr ? (
      gmem[GB+1] = 0;
      note_evidence(0, 0);
      heartbeat += 1; gmem[GB+2] = heartbeat;
      state = 0;
    ) : (
      scan_tau = slo;
      state = 1;
    );
  );
);

// ---- one chunk of the NSDF ----------------------------------------------
// NOTE: "spent", not "work". EEL2 identifiers are CASE INSENSITIVE, so a
// local called work is the same variable as the global WORK - setting it to
// zero set the budget to zero, the loop never ran a single iteration, the
// scan never advanced past its first chunk, and the only thing that ever
// finished a scan was the watchdog. The detector looked alive (the heartbeat
// ticked once a second) and never produced a single reading.
function scan_chunk() local(i, tau, ac, m, n2, a, b, spent)
(
  spent = 0;
  while (scan_tau <= tmax && spent < WORK) (
    tau = scan_tau;
    ac = 0; m = 0; i = 0; n2 = NW - tau;
    while (i < n2) (
      a = snapD[i]; b = snapD[i + tau];
      ac += a * b;
      m += a * a + b * b;
      i += 1;
    );
    wrk[tau] = m > 0 ? 2 * ac / m : 0;
    spent += n2;
    scan_tau += 1;
  );
);

// ---- pick the peak, then set up the refinement --------------------------
function scan_pick() local(t, st, gmax, thresh, chosen, y1, y2, y3, d, delta, Tf)
(
  t = slo;
  while (t <= tmax && wrk[t] > 0) ( t += 1; );
  st = t;

  gmax = 0; t = st;
  while (t <= tmax) ( wrk[t] > gmax ? (gmax = wrk[t]); t += 1; );
  thresh = gmax * 0.86;

  chosen = 0;
  t = st + 1;
  while (t < tmax && chosen == 0) (
    (wrk[t] > wrk[t - 1] && wrk[t] >= wrk[t + 1] && wrk[t] > thresh) ?
      (chosen = t);
    t += 1;
  );

  // >= / <= : the parabolic interpolation below only needs one lag of
  // margin on each side. Demanding two threw away the top and bottom of
  // the range for nothing.
  // publish what the picker saw, so a rejection can be explained instead
  // of guessed at
  gmem[GB+18] = gmax;
  gmem[GB+19] = chosen;
  gmem[GB+26] = st;
  gmem[GB+27] = tmin;

  (chosen >= tmin && chosen <= tmax - 1 && gmax >= 0.6) ? (
    y1 = wrk[chosen - 1]; y2 = wrk[chosen]; y3 = wrk[chosen + 1];
    d = y1 - 2 * y2 + y3;
    delta = d != 0 ? 0.5 * (y1 - y3) / d : 0;
    abs(delta) > 1 ? (delta = 0);
    Tf = (chosen + delta) * dec;
    c_clarity = wrk[chosen];

    bw = max(3, dec + 2);
    r_lo = max(2, floor(Tf + 0.5) - bw);
    r_hi = floor(Tf + 0.5) + bw;
    // 2.2 periods is enough for the correlation and keeps the cost of a lag
    // proportional to the period rather than three times it
    r_NF = min(12000, max(floor(Tf * 2.2), r_hi + 16));
    (snap_fpos >= r_NF && r_NF > r_hi + 8) ? (
      memcpy(snapF, fbuf + snap_fpos - r_NF, r_NF);
      r_L = r_lo; r_best = -2; r_bestL = r_lo;
      c_Tf = Tf;
      state = 2;
    ) : (
      gmem[GB+0] = srate / Tf;
      gmem[GB+1] = c_clarity;
      note_evidence(c_clarity, srate / Tf);
      heartbeat += 1; gmem[GB+2] = heartbeat;
      state = 0;
    );
  ) : (
    gmem[GB+1] = 0;
    // gmax is the best correlation anywhere in the range: worth keeping
    // even when it failed the test, it is the difference between "silence"
    // and "loud but not a note"
    note_evidence(gmax, 0);
    heartbeat += 1; gmem[GB+2] = heartbeat;
    state = 0;
  );
);

// ---- one chunk of the full rate refinement ------------------------------
function refine_chunk() local(i, ac, m, v, n2, a, b, spent)
(
  spent = 0;
  while (r_L <= r_hi && spent < WORK) (
    ac = 0; m = 0; i = 0; n2 = r_NF - r_L;
    while (i < n2) (
      a = snapF[i]; b = snapF[i + r_L];
      ac += a * b;
      m += a * a + b * b;
      i += 1;
    );
    v = m > 0 ? 2 * ac / m : 0;
    wrk2[r_L - r_lo] = v;
    v > r_best ? ( r_best = v; r_bestL = r_L; );
    r_L += 1;
    spent += n2;
  );
);

function refine_done() local(k, y1, y2, y3, d, delta, Tf)
(
  (
    Tf = r_bestL;
    k = r_bestL - r_lo;
    (k > 0 && k < r_hi - r_lo) ? (
      y1 = wrk2[k - 1]; y2 = wrk2[k]; y3 = wrk2[k + 1];
      d = y1 - 2 * y2 + y3;
      delta = d != 0 ? 0.5 * (y1 - y3) / d : 0;
      abs(delta) < 1 ? (Tf = r_bestL + delta);
    );
    Tf > 0 ? (
      gmem[GB+0] = srate / Tf;
      // r_best, not max(c_clarity, r_best): the frequency being published
      // comes from the refinement, so the confidence published with it has
      // to be the refinement's. Taking the better of the two let a bad
      // refinement hide behind a good coarse pass.
      gmem[GB+1] = r_best;
      note_evidence(r_best, srate / Tf);
    ) : (
      gmem[GB+1] = 0;
      note_evidence(0, 0);
    );
    heartbeat += 1; gmem[GB+2] = heartbeat;
    state = 0;
  );
);

@block
// ---- who is allowed to publish? -----------------------------------------
// Exactly one instance writes to the shared slots, so a leftover detector
// in another project tab cannot fight over them.
gmem[GB+9] == inst_id ? (
  // publish the configuration from here rather than from @init, so an
  // instance that is not the publisher never touches the shared slots
  is_writer == 0 ? ( hopcnt = 0; state = 0; );
  is_writer = 1;
  // The script chooses how low to look. Written out as plain nested
  // conditionals with a local copy rather than one clever line: this is the
  // handshake that decides the whole search range, a silent failure here
  // means the detector is looking for a note the user cannot play, and
  // there is nothing to gain from being terse.
  lowreq = gmem[GB+17];
  lowreq >= 16 ? (
    lowreq <= 1600 ? (
      lowreq != cur_low ? (
        cur_low = lowreq;
        tmax = min(1000, floor(dsrate / cur_low));
        NW = min(2048, floor(tmax * 2.5));
        state = 0;
        scan_tau = slo;
      );
    );
  );
  gmem[GB+3] = srate;
  gmem[GB+5] = ]==] .. JSFX_VERSION .. [==[;
  gmem[GB+7] = dsrate;
  gmem[GB+8] = tmax;
  // what the detector is ACTUALLY using, and what it thinks the script
  // asked for. If these disagree with the script the handshake is broken,
  // and that is invisible from either side alone.
  gmem[GB+28] = cur_low;
  gmem[GB+29] = gmem[GB+17];
  gmem[GB+11] += 1;
) : (
  is_writer = 0;
  // Nobody holds the slot (the script clears it whenever the tuner is
  // switched on): claim it immediately. Waiting the full timeout here is
  // what used to leave the box showing "---" for two to nine seconds after
  // every switch on, depending on the audio buffer size.
  gmem[GB+9] == 0 ? (
    gmem[GB+9] = inst_id;
    seen_cnt = 0;
  ) : (
    gmem[GB+11] == seen_live ? ( seen_cnt += 1; ) : ( seen_live = gmem[GB+11]; seen_cnt = 0; );
    // the current publisher stopped running: take over
    seen_cnt > 200 ? ( gmem[GB+9] = inst_id; seen_cnt = 0; );
  );
);

hopcnt += samplesblock;
// One analysis step per audio BLOCK would tie the update rate to the user's
// buffer size (a 1024 sample buffer gave 4 readings/s instead of 22), so
// steps follow elapsed samples instead. The cap scales with the block: a
// big block has proportionally more time to spend, and a fixed cap of 8
// made the update rate collapse again above a 1408 sample buffer.
max_steps = max(4, ceil(samplesblock / hop) + 2);
steps = 0;
while (is_writer && hopcnt >= hop && steps < max_steps) (
  hopcnt -= hop;
  steps += 1;
  gmem[GB+13] = peak;
  state == 0 ? (
    watchdog = 0;
    scan_start();
  ) : (
    watchdog += 1;
    // Never let the machine sit in one scan: restart if it takes too long
    watchdog > 200 ? (
      state = 0;
      gmem[GB+1] = 0;
      note_evidence(0, 0);
      heartbeat += 1; gmem[GB+2] = heartbeat;
    ) : (
      state == 1 ? (
        scan_chunk();
        scan_tau > tmax ? ( scan_pick(); );
      ) : (
        refine_chunk();
        r_L > r_hi ? ( refine_done(); );
      );
    );
  );
  gmem[GB+6] = state;
);
// never build a backlog we would then try to catch up on in one block
hopcnt > hop * max_steps ? ( hopcnt = hop * max_steps; );

@sample
// Average, not sum: a centre panned guitar would otherwise read 6 dB hotter
// than the same signal on one channel, and the noise gate the user sets in
// dB would mean two different things depending on their routing.
s = (spl0 + spl1) * 0.5;
// One NaN or infinity from an upstream plugin would poison the lowpass
// state permanently - it is an IIR - and the tuner would read nothing for
// the rest of the session with no visible cause.
(s == s && abs(s) < BIG) ? 0 : ( s = 0; lp1 = 0; lp2 = 0; lp3 = 0; dcy = 0; dcx = 0; );

dcy = s - dcx + dcr * dcy; dcx = s; s = dcy;

peak = max(peak * peak_c, abs(s));

fpos >= FLEN ? (
  memcpy(fbuf, fbuf + FLEN / 2, FLEN / 2);
  fpos = FLEN / 2;
  snap_fpos = max(0, snap_fpos - FLEN / 2);
);
fbuf[fpos] = s; fpos += 1;

lp1 = lp1 * lpc + s * lpc_i;
lp2 = lp2 * lpc + lp1 * lpc_i;
lp3 = lp3 * lpc + lp2 * lpc_i;

deccnt += 1;
deccnt >= dec ? (
  deccnt = 0;
  dpos >= DLEN ? ( memcpy(dbuf, dbuf + DLEN / 2, DLEN / 2); dpos = DLEN / 2; );
  dbuf[dpos] = lp3; dpos += 1;
);

@gfx 620 400
// ---------------------------------------------------------------------
// Big readout, laid out after the Logic tuner.
//
//   * a band of tick bars across the top, every 2 cents
//   * the bars BETWEEN the centre and where you are fill in, so the
//     amount of colour is the error - you watch it drain as you tune
//   * a marker at top centre plus a full height centre bar, so dead
//     centre is unmistakable
//   * a needle underneath pointing at the band, and the note below it
//
// Everything shown comes from the slots the script publishes, so this
// window and the transport box can never disagree.
// ---------------------------------------------------------------------
// Ask for a real pixel backing store. REAPER raises this to 2 on a retina
// display, so it must only be set when it is still 0, and every size below
// is derived from gfx_h and therefore scales by itself.
gfx_ext_retina < 1 ? gfx_ext_retina = 1;

function note_name(n) local(i) (
  i = n % 12;
  i == 0 ? sprintf(#nn, "C")  : i == 1 ? sprintf(#nn, "C#") :
  i == 2 ? sprintf(#nn, "D")  : i == 3 ? sprintf(#nn, "D#") :
  i == 4 ? sprintf(#nn, "E")  : i == 5 ? sprintf(#nn, "F")  :
  i == 6 ? sprintf(#nn, "F#") : i == 7 ? sprintf(#nn, "G")  :
  i == 8 ? sprintf(#nn, "G#") : i == 9 ? sprintf(#nn, "A")  :
  i == 10 ? sprintf(#nn, "A#") : sprintf(#nn, "B");
);

// an antialiased line with thickness, built from parallel hairlines
function thick_line(x1, y1, x2, y2, wid) local(dx, dy, len, nx, ny, i, o) (
  dx = x2 - x1; dy = y2 - y1;
  len = sqrt(dx * dx + dy * dy);
  len > 0 ? (
    nx = -dy / len; ny = dx / len;
    i = 0;
    while (i < wid * 2) (
      o = (i / 2 - wid / 2 + 0.25);
      gfx_line(x1 + nx * o, y1 + ny * o, x2 + nx * o, y2 + ny * o, 1);
      i += 1;
    );
  );
);

// one tick bar of the band, at a cents position
function bar(c, rin, wid) local(a) (
  a = c / 50 * SPAN;
  thick_line(cx + sin(a) * R * rin, cy - cos(a) * R * rin,
             cx + sin(a) * R,       cy - cos(a) * R, wid);
);

W = gfx_w; H = gfx_h;
midi = gmem[GB+21];
cents = gmem[GB+20];
tuned = gmem[GB+22];
ready = gmem[GB+23];
a4 = gmem[GB+24] > 0 ? gmem[GB+24] : 440;
hz = gmem[GB+25];
live = ready > 0 && midi > 0;

gfx_set(0.086, 0.086, 0.094, 1); gfx_rect(0, 0, W, H);

cx = W * 0.5;
cy = H * 0.800;                        // needle pivot
R  = min(W * 0.435, H * 0.635);
SPAN = 0.96;                           // +-55 degrees maps to +-50 cents
STEP = 2;                              // one bar every 2 cents

c = live ? max(-50, min(50, cents)) : 0;

WMIN = max(1, R * 0.0065);             // bar widths
WMAJ = max(2, R * 0.0105);
WCEN = max(3, R * 0.016);

// ---- tick band -------------------------------------------------------
gfx_setfont(1, "Arial", max(8, floor(H / 25)));
i = -50;
while (i <= 50) (
  major = (i % 10) == 0;
  // is this bar inside the span between dead centre and the reading?
  lit = live && i != 0 &&
        (c > 0 ? (i > 0 && i <= c + STEP * 0.5) :
         (c < 0 ? (i < 0 && i >= c - STEP * 0.5) : 0));

  lit ? (
    tuned > 0 ? gfx_set(0.275, 0.725, 0.996, 1) : gfx_set(0.925, 0.365, 0.318, 1);
  ) : (
    gfx_set(0.34, 0.34, 0.38, major ? 0.90 : 0.42);
  );
  bar(i, major ? 0.865 : 0.912, major ? WMAJ : WMIN);

  // labels, but never at 0 - the centre gets a marker instead
  (major && i != 0) ? (
    sprintf(#lb, "%d", i);
    gfx_measurestr(#lb, tw, th);
    gfx_set(0.50, 0.50, 0.55, 1);
    ang = i / 50 * SPAN;
    gfx_x = cx + sin(ang) * R * 1.115 - tw * 0.5;
    gfx_y = max(1, cy - cos(ang) * R * 1.115 - th * 0.5);
    gfx_drawstr(#lb);
  );
  i += STEP;
);

// ---- centre: a full depth bar plus a marker above it -----------------
tuned > 0 ? gfx_set(0.275, 0.725, 0.996, 1) :
  (live ? gfx_set(0.78, 0.78, 0.84, 1) : gfx_set(0.52, 0.52, 0.58, 1));
bar(0, 0.800, WCEN);

// marker: a triangle above the band pointing down at the centre bar
my1 = cy - R * 1.145;
my2 = cy - R * 1.048;
mw  = R * 0.040;
gfx_triangle(cx - mw, my1, cx + mw, my1, cx, my2);
// soften the two sloped edges, gfx_triangle has no antialiasing
thick_line(cx - mw, my1, cx, my2, 1);
thick_line(cx + mw, my1, cx, my2, 1);

// ---- note ------------------------------------------------------------
// drawn before the needle so the guard arc can sit over it, exactly the
// way the needle never runs into the letter
// The note is sized from the height, but it has to fit the WIDTH too: in a
// tall narrow window a two character name like C# would otherwise be drawn
// off both edges. And gfx_setfont with a size of 0 is not valid.
nsz = max(8, floor(min(H * 0.28, W * 0.26)));
gfx_setfont(2, "Arial", nsz, 'b');
live ? (
  note_name(midi);
  tuned > 0 ? gfx_set(0.93, 0.93, 0.95, 1) : gfx_set(0.925, 0.365, 0.318, 1);
  gfx_measurestr(#nn, tw, th);
  gfx_x = cx - tw * 0.5;
  gfx_y = cy - th * 0.42;
  gfx_drawstr(#nn);

  gfx_setfont(3, "Arial", max(7, floor(H * 0.105)));
  sprintf(#ov, "%d", floor(midi / 12) - 1);
  gfx_measurestr(#ov, ow, oh);
  gfx_set(0.42, 0.42, 0.46, 1);
  gfx_x = cx + tw * 0.5 + H * 0.018;
  gfx_y = cy - th * 0.42 + th - oh * 1.15;
  gfx_drawstr(#ov);
) : (
  tw = 0;
);

// ---- guard arc, between the needle and the note ----------------------
gfx_set(0.34, 0.34, 0.38, 0.85);
gfx_arc(cx, cy, R * 0.315, -SPAN * 0.62, SPAN * 0.62, 1);

// ---- needle ----------------------------------------------------------
// stops at the inner edge of the band: the band carries the reading, the
// needle only says where to look
live ? (
  tuned > 0 ? gfx_set(0.275, 0.725, 0.996, 1) : gfx_set(0.925, 0.365, 0.318, 1);
  ang = c / 50 * SPAN;
  thick_line(cx + sin(ang) * R * 0.35, cy - cos(ang) * R * 0.35,
             cx + sin(ang) * R * 0.82, cy - cos(ang) * R * 0.82,
             max(2, R * 0.0095));
);

// ---- readouts flanking the note --------------------------------------
gfx_setfont(4, "Arial", max(8, floor(H / 22)));
gfx_set(0.48, 0.48, 0.52, 1);
base_y = cy - H * 0.012;

live ? sprintf(#l1, "%.1f Hz", hz) : sprintf(#l1, "-- Hz");
gfx_measurestr(#l1, lw, lh);
gfx_x = W * 0.055; gfx_y = base_y - lh * 0.5;
gfx_drawstr(#l1);

live ? sprintf(#l2, "%+.0f cents", cents) : sprintf(#l2, "-- cents");
gfx_measurestr(#l2, lw, lh);
gfx_x = W * 0.945 - lw; gfx_y = base_y - lh * 0.5;
gfx_drawstr(#l2);

// reference pitch, tucked under the Hz readout so it is out of the way
// of both the cent labels and the note
gfx_setfont(5, "Arial", max(8, floor(H / 27)));
sprintf(#l3, "A4 = %.1f Hz", a4);
gfx_measurestr(#l3, lw, lh);
gfx_set(0.33, 0.33, 0.37, 1);
gfx_x = W * 0.055; gfx_y = H - lh - H * 0.05;
gfx_drawstr(#l3);
]==]

--------------------------------- JSFX file ---------------------------------

-- The directory this script writes to when it has to install the detector
-- itself. Never the ReaPack one: those files belong to ReaPack.
function GetJSFXDir()
    return ConcatPath(reaper.GetResourcePath(), 'Effects', 'Reapertips')
end

function GetJSFXPath()
    return ConcatPath(GetJSFXDir(), JSFX_FILE)
end

-- Relative path (from the Effects folder) of a detector that already exists
-- on disk, or nil. Checks the ReaPack location first.
function FindInstalledJSFX()
    local root = ConcatPath(reaper.GetResourcePath(), 'Effects')
    for _, dir in ipairs(JSFX_DIRS) do
        local rel = dir .. '/' .. JSFX_FILE
        local path = ConcatPath(root, (rel:gsub('/', package.config:sub(1, 1))))
        local file = io.open(path, 'r')
        if file then
            local content = file:read(4096)
            file:close()
            if content and content:find('// version: ' .. JSFX_VERSION, 1, true)
            then
                return rel
            end
        end
    end
end

function InstallJSFX()
    -- Already there (ReaPack's copy, or one we wrote earlier)? Nothing to do.
    local found = FindInstalledJSFX()
    if found then
        JSFX_REL_PATH = found
        return true
    end

    local path = GetJSFXPath()

    local dir = GetJSFXDir()
    if reaper.RecursiveCreateDirectory then
        reaper.RecursiveCreateDirectory(dir, 0)
    end

    -- Clean up detectors written by previous versions of this script
    if reaper.EnumerateFiles then
        local old = {}
        local i = 0
        while true do
            local name = reaper.EnumerateFiles(dir, i)
            if type(name) ~= 'string' then break end
            if name:match('^rtips_tuner') and name ~= JSFX_FILE then
                old[#old + 1] = ConcatPath(dir, name)
            end
            i = i + 1
        end
        for _, f in ipairs(old) do DeleteFile(f) end
    end

    local file = io.open(path, 'w')
    if not file then
        T.err = 'Could not write JSFX to:\n' .. path
        return false
    end
    file:write(JSFX_CODE)
    file:close()
    return true
end

--------------------------------- The track ---------------------------------

-- Removes every track tagged as a tuner track in EVERY open project, so a
-- leftover from another tab cannot run a second detector against the same
-- shared gmem. Returns how many were removed.
function RemoveAllTunerTracks(except)
    local removed = 0
    local p = 0
    -- bounded on purpose: never trust an enumerator to terminate the loop
    while p < 128 do
        local proj = reaper.EnumProjects(p)
        if not proj then break end
        local i = reaper.CountTracks(proj) - 1
        while i >= 0 do
            local track = reaper.GetTrack(proj, i)
            if track and track ~= except and
                reaper.GetSetMediaTrackInfo_String(track,
                    'P_EXT:' .. TRACK_TAG, '', false) then
                reaper.DeleteTrack(track)
                removed = removed + 1
            end
            i = i - 1
        end
        p = p + 1
    end
    T.track = nil
    T.fx = nil
    T.proj = nil
    if removed > 0 then reaper.TrackList_AdjustWindows(false) end
    return removed
end

-- True when the tuner is on AND we are in the project it was turned on in.
-- Everything user facing (the readout, the icon, the click) goes through
-- this rather than T.on.
function TunerIsLive()
    return T.on and not T.parked
end

-- The project the tuner should be operating in right now.
function TunerProj()
    return T.proj or 0
end

function FindTunerTrack()
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local ret = reaper.GetSetMediaTrackInfo_String(track,
            'P_EXT:' .. TRACK_TAG, '', false)
        if ret then return track end
    end
end

function AddTunerFX(track)
    local names = {JSFX_REL_PATH}
    for _, dir in ipairs(JSFX_DIRS) do names[#names + 1] = dir .. '/' .. JSFX_FILE end
    names[#names + 1] = 'JS: Reapertips Tuner Detector'
    for _, name in ipairs(names) do
        local fx = reaper.TrackFX_AddByName(track, name, false, 1)
        if fx >= 0 then return fx end
    end
    return -1
end

function CreateTunerTrack()
    if not InstallJSFX() then return end

    reaper.PreventUIRefresh(1)

    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, false)
    local track = reaper.GetTrack(0, idx)

    reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'TunerBox (auto)', true)
    reaper.GetSetMediaTrackInfo_String(track, 'P_EXT:' .. TRACK_TAG, '1', true)

    reaper.SetMediaTrackInfo_Value(track, 'I_RECINPUT', T.input)
    ArmTunerTrack(track)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)

    local fx = AddTunerFX(track)

    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)

    if fx < 0 then
        reaper.DeleteTrack(track)
        T.err = 'Could not load the tuner JSFX.\n\nExpected at:\n' ..
            GetJSFXPath()
        return
    end

    T.track = track
    T.fx = fx
    T.proj = reaper.EnumProjects(-1)
    T.parked = false
    return track
end

-- Deletes ONLY a track this script tagged. It checks the tag rather than
-- trusting T.track, so a stale handle can never take a user's track with it.
function RemoveTunerTrack()
    local track = T.track
    local is_ours = track and reaper.ValidatePtr(track, 'MediaTrack*') and
        reaper.GetSetMediaTrackInfo_String(track, 'P_EXT:' .. TRACK_TAG, '',
            false)
    if not is_ours then track = FindTunerTrack() end
    T.track = nil
    T.fx = nil
    if track then
        reaper.PreventUIRefresh(1)
        reaper.DeleteTrack(track)
        reaper.PreventUIRefresh(-1)
        reaper.TrackList_AdjustWindows(false)
    end
end

-- ---------------------------------------------------------------------
-- The detector FX
-- ---------------------------------------------------------------------

function FindTunerFX(track)
    for i = 0, reaper.TrackFX_GetCount(track) - 1 do
        local _, name = reaper.TrackFX_GetFXName(track, i, '')
        if name and name:find('Reapertips Tuner', 1, true) then return i end
    end
    return -1
end

-- Up to 1.3.1 the tuner could be pointed at a track the user picked instead
-- of its own hidden one. That mode is gone (it could not work across project
-- tabs, and the track it had been pointed at lived in a different tab from
-- the box), but anyone who had it switched on has our JSFX sitting on one of
-- their tracks right now. Take it off once, then forget the whole thing.
function MigrateAwayFromOwnTrack()
    if reaper.GetExtState(extname, 'mode') ~= 'own' then return end
    local guid = reaper.GetExtState(extname, 'own_guid')
    local p = 0
    while p < 128 and guid ~= '' do
        local proj = reaper.EnumProjects(p)
        if not proj then break end
        for i = 0, reaper.CountTracks(proj) - 1 do
            local track = reaper.GetTrack(proj, i)
            if track and reaper.GetTrackGUID(track) == guid then
                local fx = FindTunerFX(track)
                if fx >= 0 then reaper.TrackFX_Delete(track, fx) end
            end
        end
        p = p + 1
    end
    reaper.SetExtState(extname, 'mode', '', true)
    reaper.SetExtState(extname, 'own_guid', '', true)
    reaper.DeleteExtState(extname, 'mode', true)
    reaper.DeleteExtState(extname, 'own_guid', true)
end

-- Puts the hidden track into the one state it is ever allowed to be in:
-- record mode "disable (input monitoring only)", armed, monitoring, no
-- output. Record mode 2 is what makes it structurally impossible for the
-- track to capture anything, whatever the transport is doing, so there is
-- no un-arm dance around takes and nothing here depends on play state.
function ArmTunerTrack(track)
    local V = reaper.GetMediaTrackInfo_Value
    local Set = reaper.SetMediaTrackInfo_Value
    -- set record mode FIRST: arming a track that is still in a capturing
    -- record mode, even for an instant, is the one thing worth avoiding
    if V(track, 'I_RECMODE') ~= 2 then Set(track, 'I_RECMODE', 2) end
    if V(track, 'B_MAINSEND') ~= 0 then Set(track, 'B_MAINSEND', 0) end
    if V(track, 'I_RECARM') ~= 1 then Set(track, 'I_RECARM', 1) end
    if V(track, 'I_RECMON') ~= 1 then Set(track, 'I_RECMON', 1) end
end

-- Keeps the hidden track healthy on the periodic check.
--
-- This deliberately does NOT re-arm on every pass. The track is hidden from
-- the TCP and the mixer, so if the user runs "un-arm all tracks" and it
-- silently armed itself again a second later, they would have no way to see
-- which track was doing it. Un-arming it just means the tuner stops
-- reading, which the box shows plainly, and switching the tuner off and on
-- puts it back.
function MaintainTunerTrack()
    local track = T.track
    if not track or not reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*') then
        return
    end
    -- Record mode is the safety property, not a preference: restore it even
    -- if the user changed it, because a capturing record mode on a hidden
    -- armed track is how you end up with a stray file after a take.
    if reaper.GetMediaTrackInfo_Value(track, 'I_RECMODE') ~= 2 then
        reaper.SetMediaTrackInfo_Value(track, 'I_RECMODE', 2)
    end
    if reaper.GetMediaTrackInfo_Value(track, 'B_MAINSEND') ~= 0 then
        reaper.SetMediaTrackInfo_Value(track, 'B_MAINSEND', 0)
    end
end

function EnsureTunerTrack()
    local track = T.track
    if track and reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*') then
        return track
    end
    -- A track this project was saved with, or one an undo brought back.
    track = FindTunerTrack()
    if track then
        T.track = track
        T.proj = reaper.EnumProjects(-1)
        T.parked = false
        -- Re-add the JSFX if it went missing
        if reaper.TrackFX_GetCount(track) == 0 then
            InstallJSFX()
            T.fx = AddTunerFX(track)
        else
            T.fx = 0
        end
        reaper.SetMediaTrackInfo_Value(track, 'I_RECINPUT', T.input)
        -- A track saved by an older build, or edited by hand, can arrive in
        -- a capturing record mode. Fix that before arming it, not on the
        -- next periodic pass a second later.
        ArmTunerTrack(track)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
        return track
    end
    return CreateTunerTrack()
end

function SetTunerInput(input)
    T.input = input
    reaper.SetExtState(extname, 'input', input, true)
    local track = T.track
    if track and reaper.ValidatePtr(track, 'MediaTrack*') then
        reaper.SetMediaTrackInfo_Value(track, 'I_RECINPUT', input)
        -- Re-arm so REAPER picks up the new input
        reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 0)
        reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 1)
    end
end

--------------------------------- Pitch math --------------------------------

function FreqToNote(freq, a4)
    local n = 12 * math.log(freq / a4, 2) + 69
    local nr = math.floor(n + 0.5)
    local cents = (n - nr) * 100
    local name = NOTE_NAMES[nr % 12 + 1]
    local octave = math.floor(nr / 12) - 1
    return name .. octave, cents
end

-- Returns the median frequency once the last 3 readings agree with each
-- other, or nil while the reading is still jumping around. This is what
-- stops noise and string attacks from flashing random notes.
local NOTE_INDEX = {}
for i, n in ipairs(NOTE_NAMES) do NOTE_INDEX[n] = i - 1 end

function NoteToMidi(text)
    local name, oct = text:match('^([A-G]#?)(-?%d+)$')
    local idx = name and NOTE_INDEX[name]
    if not idx then return 0 end
    return (tonumber(oct) + 1) * 12 + idx
end

-- A rolling trace of the last few seconds of readings. When a note drops
-- out for reasons that cannot be reproduced with a synthetic signal - and a
-- thick, slack, stiff bass string is exactly that - the only way to find
-- out why is to look at what the detector actually reported, reading by
-- reading, on the instrument that misbehaves.
local TRACE_N = 90

function Trace(freq, clarity, rms, verdict)
    local tr = T.trace
    tr[#tr + 1] = {t = reaper.time_precise(), f = freq, c = clarity,
        r = rms, v = verdict,
        -- what the detector's own peak picker saw for this scan
        gmax = GRead(GB + 18), pick = GRead(GB + 19),
        st = GRead(GB + 26), tmin = GRead(GB + 27)}
    while #tr > TRACE_N do table.remove(tr, 1) end
end

function PrintTrace()
    local tr = T.trace
    if #tr == 0 then
        reaper.ShowConsoleMsg('\nNo readings recorded yet.\n')
        return
    end
    local t0 = tr[#tr].t
    reaper.ShowConsoleMsg(('\nLAST %d READINGS  (most recent first)\n' ..
        'peak picker: gmax = best correlation anywhere, lag = the one it\n' ..
        'chose, zero = where it started looking, min = shortest allowed\n\n' ..
        '   age      freq      note   clarity      rms |  gmax  lag zero  min' ..
        ' | what happened\n'):format(#tr))
    for i = #tr, 1, -1 do
        local e = tr[i]
        local name = e.f > 0 and e.f == e.f and select(1, FreqToNote(e.f, T.a4))
            or '-'
        reaper.ShowConsoleMsg(
            ('%7.2fs %9.2f %7s %9.3f %8.5f | %5.2f %4d %4d %4d | %s\n')
            :format(e.t - t0, e.f, name, e.c, e.r,
                e.gmax or 0, e.pick or 0, e.st or 0, e.tmin or 0, e.v))
    end
end

-- How many consecutive octave-related readings it takes to believe one.
-- At ~25 readings a second this is about 160 ms.
local OCTAVE_HOLD = 4

function PushHistory(freq)
    local hist = T.hist

    -- An octave flip is not a new note, it is the detector changing its
    -- mind about which peak is the fundamental. That happens on very low,
    -- thick strings where the fundamental is weak: the correlation at half
    -- the period is nearly as good as at the whole one. Clearing the
    -- history on every flip is the worst possible response, because the
    -- history then never reaches two agreeing readings and the readout
    -- drops out completely - which looks like the tuner losing the note
    -- rather than like it disagreeing with itself. So an octave jump has to
    -- persist before it is believed, and until then it is ignored rather
    -- than allowed to wipe what we had.
    local ref = T.stable_f
    if ref and ref > 0 then
        local ratio = freq / ref
        local is_octave = math.abs(ratio - 2) < 0.06 or
            math.abs(ratio - 0.5) < 0.015
        if is_octave then
            T.oct_cnt = (T.oct_cnt or 0) + 1
            if T.oct_cnt < OCTAVE_HOLD then return nil end
        else
            T.oct_cnt = 0
        end
    end

    -- A genuinely new note should snap in instantly instead of being
    -- averaged with the previous one: drop the history whenever the pitch
    -- jumps by more than a few cents.
    local last = hist[#hist]
    if last and math.abs(freq / last - 1) > 0.03 then
        for i = #hist, 1, -1 do hist[i] = nil end
    end
    hist[#hist + 1] = freq
    while #hist > 3 do table.remove(hist, 1) end
    if #hist < 2 then return nil end

    local lo, hi = hist[1], hist[1]
    for i = 2, #hist do
        if hist[i] < lo then lo = hist[i] end
        if hist[i] > hi then hi = hist[i] end
    end
    -- Readings must sit within ~35 cents of each other
    if hi / lo > 1.02 then return nil end

    local sorted = {}
    for i = 1, #hist do sorted[i] = hist[i] end
    table.sort(sorted)
    local median = sorted[(#sorted + 1) // 2]
    T.stable_f = median
    T.oct_cnt = 0
    return median
end

--------------------------------- Polling -----------------------------------

function ReadTuner()
    local time = reaper.time_precise()

    local beat = GRead(GB + 2)
    if beat ~= T.last_beat then
        T.last_beat = beat
        T.last_beat_time = time
    end

    -- Rolling measurement of how often the JSFX reports
    if not T.rate_t0 then T.rate_t0, T.rate_b0 = time, beat end
    if time - T.rate_t0 >= 1 then
        T.rate = (beat - T.rate_b0) / (time - T.rate_t0)
        T.rate_t0, T.rate_b0 = time, beat
    end

    -- JSFX is not running (deleted track, bypassed fx, audio engine off...)
    if time > T.last_beat_time + 1.5 then
        T.hist = {}
        return SetDisplay('---', 0, false)
    end

    -- REAPER served a cached build of the detector: say so instead of
    -- silently reporting whatever that build happens to write
    if GRead(GB + 5) ~= tonumber(JSFX_VERSION) then
        T.hist = {}
        return SetDisplay('old', 0, false)
    end

    local clarity = GRead(GB + 1)
    local freq = GRead(GB + 0)
    local rms = GRead(GB + 4)
    T.level = GRead(GB + 13)

    -- Track the noise floor of this input and only trust readings that sit
    -- clearly above it. A fixed dB threshold cannot work: every interface
    -- and gain setting has a different floor, and analysing the floor is
    -- exactly what produces the drifting phantom notes.
    if rms > 0 then
        if rms < T.floor then
            T.floor = rms
        else
            T.floor = T.floor * 1.0002 + 1e-12
        end
    end
    local threshold = math.max(T.gate, T.floor * 2.5)

    local is_valid = rms > threshold and clarity >= 0.6 and
        freq >= T.low_hz and freq <= 1470

    if is_valid then
        T.bad_time = nil
        local stable = PushHistory(freq)
        if stable then
            T.last_pitch_time = time
            T.freq = stable
            local name, cents = FreqToNote(stable, T.a4)
            SetDisplay(name, cents, true)
            Trace(freq, clarity, rms, 'shown as ' .. name)
        else
            Trace(freq, clarity, rms,
                (T.oct_cnt or 0) > 0
                    and ('an octave from %.1f Hz, waiting (%d/%d)')
                        :format(T.stable_f or 0, T.oct_cnt, OCTAVE_HOLD)
                    or 'waiting for a second reading that agrees')
        end
        return
    end

    Trace(freq, clarity, rms,
        rms <= threshold and 'too quiet'
        or clarity < 0.6 and 'not periodic enough'
        or ('%.1f Hz is outside the %g - 1470 Hz range')
            :format(freq, T.low_hz))

    -- A single weak frame (attack transient, note decay) must NOT wipe the
    -- history, otherwise it never collects enough readings to show anything.
    T.bad_time = T.bad_time or time
    if time - T.bad_time > 0.4 then T.hist = {} end

    -- Hold the last note so it does not flicker while a string decays
    if time > T.last_pitch_time + 1.5 then
        -- Standby placeholder. The input level is still reported in
        -- Detector status when something needs diagnosing.
        SetDisplay('---', 0, false)
    end
end

-- A plucked string is genuinely sharp for the first fraction of a second:
-- the extra tension of the attack pushes the pitch up before it settles.
-- Showing that would flash the red arrow on a string that is perfectly in
-- tune, so the arrows stay neutral until the note has had time to settle.
local ATTACK_SETTLE = 0.18
-- Asymmetric thresholds keep the readout from flickering on the boundary
local IN_TUNE_ENTER = 3
local IN_TUNE_LEAVE = 5

function SetDisplay(text, cents, has_pitch)
    local time = reaper.time_precise()

    if text ~= T.text then T.note_since = time end

    local limit = T.in_tune and IN_TUNE_LEAVE or IN_TUNE_ENTER
    local in_tune = has_pitch and math.abs(cents) <= limit

    -- Damping, the way a hardware tuner does it: snap when the note itself
    -- changes, ease when it is the same note drifting.
    if not has_pitch or text ~= T.text then
        T.disp = cents
    else
        T.disp = T.disp + (cents - T.disp) * 0.3
    end

    local settled = has_pitch and (time - T.note_since) >= ATTACK_SETTLE

    -- Redraw when something actually changes on screen. The damped value
    -- moves on nearly every reading, but the only thing it drives is the
    -- length of the deviation bar, so the test is whether the bar would
    -- land on a different pixel. T.disp_step is the bar's cents-per-pixel,
    -- published by the drawing code; without it we fall back to a step that
    -- is finer than any real box.
    local step = T.disp_step or 0.5
    if text ~= T.text or has_pitch ~= T.has_pitch or in_tune ~= T.in_tune or
        settled ~= T.settled or
        math.floor(T.disp / step) ~= math.floor((T.prev_disp or 0) / step) then
        is_redraw = true
        T.prev_disp = T.disp
    end

    T.text = text
    T.cents = cents
    T.has_pitch = has_pitch
    T.in_tune = in_tune
    T.settled = settled

    -- Publish for the big readout so the two views can never disagree.
    -- The frequency belongs to the reading, so it goes stale the moment
    -- there is no reading: publish 0 rather than the last note's pitch.
    if not has_pitch then T.freq = nil end
    GWrite(GB + 20, T.disp)
    GWrite(GB + 21, has_pitch and NoteToMidi(text) or 0)
    GWrite(GB + 22, in_tune and 1 or 0)
    GWrite(GB + 23, settled and 1 or 0)
    GWrite(GB + 24, T.a4)
    GWrite(GB + 25, T.freq or 0)
end

local function dB(v)
    return v and v > 0 and 20 * math.log(v, 10) or -150
end

-- The one line worth reading first. Everything else in the report is
-- evidence for it.
local function Verdict()
    local peak5 = GRead(GB + 14)      -- loudest sample in the last ~5 s
    local clar5 = GRead(GB + 15)      -- best correlation in the last ~5 s
    local good5 = GRead(GB + 16)      -- last frequency worth believing

    if not T.on then
        return 'the tuner is switched OFF', ''
    end
    if T.parked then
        return 'the tuner is PARKED in another project tab', ''
    end
    if GRead(GB + 5) ~= tonumber(JSFX_VERSION) then
        return 'REAPER is running an OLD cached build of the detector',
            'Reinstall from ReaPack, or restart REAPER.'
    end
    if GRead(GB + 28) > 0 and GRead(GB + 28) ~= T.low_hz then
        return ('the detector is searching from %g Hz, not the %g Hz you set')
            :format(GRead(GB + 28), T.low_hz),
            'Switch the tuner off and on again. If it comes back, tell me:\n' ..
            'the setting is not reaching the detector.'
    end
    if (T.rate or 0) < 1 then
        return 'the detector is NOT RUNNING',
            'The audio engine may be off, the FX bypassed, or the track gone.'
    end
    -- A confirmed note is stronger evidence than a peak accumulator that
    -- has just started or reset. The three evidence slots are published
    -- independently and can legitimately be observed between updates.
    if good5 > 0 then
        return ('working: last confident reading was %.2f Hz'):format(good5), ''
    end
    if dB(peak5) < -60 then
        return 'NO AUDIO is reaching the detector',
            'Nothing above -60 dBFS in the last 5 seconds, so this is not the\n' ..
            'detector: it is routing. Check the input in the right click menu,\n' ..
            'and that your interface really has the guitar on that input.\n' ..
            'Play something and run this again - the numbers below cover the\n' ..
            'last 5 seconds, so you can put the guitar down first.'
    end
    if dB(peak5) < -40 then
        return 'audio is arriving but it is VERY QUIET',
            ('Loudest in the last 5 s was %.1f dBFS. Turn up the input gain,\n' ..
             'or lower the noise gate in Advanced.'):format(dB(peak5))
    end
    if GRead(GB + 16) == 0 and clar5 >= 0.6 then
        return 'notes are being found but rejected as OUT OF RANGE',
            ('Everything found sat outside %g - 1470 Hz. That is below the\n' ..
             'lowest note on any common instrument, so it is more likely to\n' ..
             'be mains hum or a subsonic rumble than a string.')
                :format(T.low_hz)
    end
    if clar5 < 0.6 then
        return 'audio is arriving but NONE OF IT IS PERIODIC',
            ('Best correlation in the last 5 s was %.2f, and it needs 0.60.\n' ..
             'That is what a distorted, very percussive or polyphonic signal\n' ..
             'looks like. Try a clean DI, one string at a time.'):format(clar5)
    end
    return 'the detector found notes but the script rejected them',
        'Most likely the noise floor estimate. Try Advanced -> Noise gate.'
end

function ShowTunerStatus()
    local track = T.track
    local valid = track and reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*')
    local rms = GRead(GB + 4)
    local verdict, advice = Verdict()

    reaper.ClearConsole()
    reaper.ShowConsoleMsg(('TunerBox status\n\n' ..
        '>>> %s\n%s%s' ..
        'listening to     : %s\n' ..
        'tuner on         : %s\n' ..
        'track valid      : %s\n' ..
        'fx count         : %s\n' ..
        'rec arm/mon/mode : %s / %s / %s\n' ..
        'rec input        : %s   (0-based mono, 1024+n = stereo pair)\n' ..
        '\n' ..
        'JSFX build running: %s   (script expects %s)  %s\n' ..
        'detector state    : %s   (0 idle, 1 scanning, 2 refining)\n' ..
        'analysis rate     : %s Hz,  max period %s\n' ..
        'lowest note sought: %s Hz   (detector is using %s Hz, was told %s)%s\n' ..
        '\n' ..
        'JSFX updates/s   : %.1f   (20-250; silence is faster)\n' ..
        '\n' ..
        'IN THE LAST 5 SECONDS  (so you can play, then run this)\n' ..
        '  loudest input  : %.1f dBFS\n' ..
        '  best clarity   : %.3f   (needs >= 0.6)\n' ..
        '  last good note : %s\n' ..
        '\n' ..
        'RIGHT NOW\n' ..
        'gmem freq        : %.3f Hz\n' ..
        'gmem clarity     : %.3f   (needs >= 0.6)\n' ..
        'input peak       : %.1f dBFS   <- 150 ms decay, so it reads 0 unless\n' ..
        '                                  you are playing at this instant\n' ..
        'gmem rms         : %.5f  (%.1f dBFS)\n' ..
        'noise floor est. : %.1f dBFS\n' ..
        'needs more than  : %.1f dBFS\n' ..
        'noise gate (min) : %.5f  (%.1f dBFS)\n' ..
        'gmem samplerate  : %s\n' ..
        'A4 reference     : %s Hz\n')
        :format(
            verdict,
            advice ~= '' and (advice .. '\n') or '',
            '\n',
            'its own hidden track',
            tostring(T.on), tostring(valid),
            valid and reaper.TrackFX_GetCount(track) or 'n/a',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECMON') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECMODE') or '?',
            valid and reaper.GetMediaTrackInfo_Value(track, 'I_RECINPUT') or '?',
            GRead(GB + 5), JSFX_VERSION,
            GRead(GB + 5) == tonumber(JSFX_VERSION) and 'OK'
                or '*** MISMATCH: REAPER is running an old cached build ***',
            GRead(GB + 6), GRead(GB + 7), GRead(GB + 8), T.low_hz,
            GRead(GB + 28), GRead(GB + 29),
            GRead(GB + 28) ~= T.low_hz and '  *** MISMATCH ***' or '',
            T.rate or 0,
            dB(GRead(GB + 14)), GRead(GB + 15),
            GRead(GB + 16) > 0
                and ('%.2f Hz  (%s)'):format(GRead(GB + 16),
                    (FreqToNote(GRead(GB + 16), T.a4)))
                or 'none',
            GRead(GB + 0), GRead(GB + 1),
            dB(T.level),
            rms, dB(rms),
            dB(T.floor),
            20 * math.log(math.max(T.gate, T.floor * 2.5), 10),
            T.gate, 20 * math.log(T.gate, 10),
            GRead(GB + 3), T.a4))
    PrintTrace()
end

-- Opens the detector's own window, which draws the full size readout, and
-- centres it on the REAPER window (REAPER itself remembers wherever the
-- user drags it afterwards).
function OpenBigTuner()
    -- Opening the big readout in another project tab used to show a window
    -- that could never say anything, because the tuner is parked and stops
    -- publishing. Bring it over first, the same as clicking the fork does.
    if T.on and UpdateParked() then MoveTunerHere() end
    if not T.on then SetTunerEnabled(true) end

    local track = T.track
    if not track or not reaper.ValidatePtr(track, 'MediaTrack*') then
        track = EnsureTunerTrack()
    end
    -- Report and clear any error rather than leaving it set: a stale T.err
    -- was being shown by the NEXT thing that looked at it, long after the
    -- problem was fixed, and it also short circuited switching the tuner on.
    if T.err then
        reaper.MB(T.err, box_name, 0)
        T.err = nil
        SetTunerEnabled(false)
        return
    end
    if not track then return end
    local fx = FindTunerFX(track)
    if fx < 0 then return end

    reaper.TrackFX_Show(track, fx, 3)

    if not T.big_placed and reaper.TrackFX_GetFloatingWindow then
        local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
        if hwnd and reaper.JS_Window_GetRect then
            local ok, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
            local mok, ml, mt, mr, mb = reaper.JS_Window_GetRect(main_hwnd)
            if ok and mok then
                -- screen coordinates are y-flipped on macOS, so normalise
                local w = math.abs(r - l)
                local h = math.abs(b - t)
                local mw = math.abs(mr - ml)
                local mh = math.abs(mb - mt)
                local x = math.min(ml, mr) + (mw - w) // 2
                local y = math.min(mt, mb) + (mh - h) // 2
                reaper.JS_Window_SetPosition(hwnd, x, y, w, h)
            end
        end
        T.big_placed = true
    end
end

function SetTunerEnabled(enable)
    if enable == T.on then return end
    T.on = enable
    reaper.SetExtState(extname, 'is_on', enable and '1' or '0', true)
    T.hist = {}
    T.last_beat = -1
    T.last_beat_time = reaper.time_precise()
    if enable then
        AttachGmem(GMEM_NAME)
        GWrite(GB + 10, T.gate)
        GWrite(GB + 17, T.low_hz)
        -- Exactly one detector, one publisher. A track left in THIS project
        -- by a previous session is adopted where it sits rather than
        -- deleted and recreated at the end of the track list: re-using it
        -- is both tidier to look at and one fewer change to the project.
        local existing = FindTunerTrack()
        RemoveAllTunerTracks(existing)
        T.track = existing
        if existing then T.proj = reaper.EnumProjects(-1) end
        GWrite(GB + 9, 0)
        T.floor = 1
        EnsureTunerTrack()
        if T.err then
            reaper.MB(T.err, box_name, 0)
            T.err = nil
            T.on = false
            reaper.SetExtState(extname, 'is_on', '0', true)
            -- undo everything the failed attempt did, or a half made track
            -- is left in the project with the tuner reporting it is off
            RemoveAllTunerTracks()
        end
        SetDisplay('---', 0, false)
    else
        RemoveAllTunerTracks()
        T.parked = false
        SetDisplay('---', 0, false)
    end
    is_redraw = true
end

-- Moves the tuner into the project tab the user is looking at now. This is
-- the only thing that creates a track in a project the user did not turn
-- the tuner on in, and it only ever runs from a deliberate click.
function MoveTunerHere()
    RemoveAllTunerTracks()
    GWrite(GB + 9, 0)
    T.floor = 1
    T.hist = {}
    T.parked = false
    EnsureTunerTrack()
    if T.err then
        reaper.MB(T.err, box_name, 0)
        T.err = nil
        SetTunerEnabled(false)
    end
    is_redraw = true
end

-- A project saved while the tuner was on carries the hidden track. When the
-- tuner is off that track does nothing, and the user cannot see it in the
-- TCP or the mixer to remove it themselves, so it is ours to clean up.
--
-- The catch is that deleting a track marks the project as modified, and
-- doing that to a project somebody just opened would produce exactly the
-- "save changes?" prompt this script goes out of its way to avoid. So the
-- sweep waits until the project is already modified by something the user
-- did. Then it costs nothing: the prompt was coming anyway, and whenever
-- they do save, the leftover is already gone.
function SweepOrphanTracks()
    local proj = reaper.EnumProjects(-1)
    local cnt = reaper.CountTracks(0)
    -- nothing can have changed since the last look
    if proj == T.swept_proj and cnt == T.swept_cnt then return 0 end
    if reaper.IsProjectDirty(0) == 0 then return 0 end
    T.swept_proj, T.swept_cnt = proj, cnt

    local removed = 0
    for i = cnt - 1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        if track and track ~= T.track and
            reaper.GetSetMediaTrackInfo_String(track,
                'P_EXT:' .. TRACK_TAG, '', false) then
            reaper.PreventUIRefresh(1)
            reaper.DeleteTrack(track)
            reaper.PreventUIRefresh(-1)
            removed = removed + 1
        end
    end
    if removed > 0 then
        reaper.TrackList_AdjustWindows(false)
        T.swept_cnt = reaper.CountTracks(0)
    end
    return removed
end

-- One periodic pass: poll the detector, keep the track healthy, and park
-- the tuner when the user is looking at a different project tab. Lives here
-- rather than inline in Main so it can be driven directly by the tests.
-- Keeps the companion action's toolbar button honest, whatever changed the
-- tuner's state - the fork, the menu, a project tab switch, quitting.
function PublishLive()
    local live = TunerIsLive() and 1 or 0
    if live == T.pub_live then return end
    T.pub_live = live
    reaper.SetExtState(extname, 'is_live', tostring(live), false)
    SetToggleActionState(live)
end

-- The companion toggle action tells us its section and command id the
-- first time it runs, so its toolbar button can be kept in sync no matter
-- how the tuner was actually switched.
function SetToggleActionState(on)
    local id = reaper.GetExtState(extname, 'toggle_action')
    local sec2, cmd2 = id:match('^(%-?%d+) (%-?%d+)$')
    if not sec2 then return end
    sec2, cmd2 = tonumber(sec2), tonumber(cmd2)
    if not cmd2 or cmd2 == 0 then return end
    reaper.SetToggleCommandState(sec2, cmd2, on)
    reaper.RefreshToolbar2(sec2, cmd2)
end

-- The companion toggle action cannot switch the tuner on by itself: the
-- track has to be created by the script that owns it. So it leaves a
-- request here and we service it on the next pass.
function ServiceToggleRequest(time)
    -- tell the toggle action we are alive, and what state we are in
    if time > (T.alive_time or 0) + 0.5 then
        T.alive_time = time
        reaper.SetExtState(extname, 'alive', ('%.3f'):format(time), false)
    end

    PublishLive()

    local req = reaper.GetExtState(extname, 'request')
    if req == '' then return end
    reaper.SetExtState(extname, 'request', '', false)

    if req == 'on' then
        if UpdateParked() then MoveTunerHere()
        elseif not T.on then SetTunerEnabled(true) end
    elseif req == 'off' then
        if T.on then SetTunerEnabled(false) end
    else
        ToggleTuner()
    end
    PublishLive()
end

function TunerTick()
    local time = reaper.time_precise()

    ServiceToggleRequest(time)

    if T.on and not T.parked and time > T.poll_time + 0.02 then
        T.poll_time = time
        ReadTuner()
    end

    if time <= T.check_time + 1 then return end
    T.check_time = time

    if not T.on then
        SweepOrphanTracks()
        return
    end

    -- The tuner stays in the project it was switched on in. Being in
    -- another tab does NOT create a track there: inserting one marks that
    -- project as modified, and doing that to every tab somebody happens to
    -- open is not the script's business. The box goes quiet instead, and a
    -- click brings the tuner over.
    if UpdateParked() then return end

    -- Re-assert the settings the detector needs. They are written when they
    -- change, but a single lost write would leave the detector analysing a
    -- different range from the one the menu says, which is invisible unless
    -- you go looking. Two gmem writes a second cost nothing.
    GWrite(GB + 10, T.gate)
    GWrite(GB + 17, T.low_hz)

    MaintainTunerTrack()
    local track = T.track
    if not track or
        not reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*') then
        EnsureTunerTrack()
        if T.err then
            reaper.MB(T.err, box_name, 0)
            T.err = nil
            SetTunerEnabled(false)
        end
    end
end

-- Recomputes whether the tuner is in a project tab other than the one it
-- was switched on in. Called wherever the answer is about to be used, not
-- only on the periodic tick: a click arriving in the first second after a
-- tab switch was being answered with the previous tab's answer, so the
-- same click switched the tuner off instead of bringing it over.
function UpdateParked()
    local parked = T.on and T.proj ~= nil and
        reaper.EnumProjects(-1) ~= T.proj
    if parked ~= T.parked then
        T.parked = parked
        if parked then SetDisplay('---', 0, false) end
        is_redraw = true
    end
    return T.parked
end

-- What the hover tooltip says. Worth a little care: the hidden track is
-- deliberately not re-armed behind the user's back, so if they un-arm
-- everything the tuner goes quiet and this is where they find out why.
function TunerTooltip()
    if UpdateParked() then
        return 'Tuner is on in another project tab - click to bring it here'
    end
    if T.on then
        local track = T.track
        if track and reaper.ValidatePtr2(TunerProj(), track, 'MediaTrack*')
            and reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') ~= 1 then
            return 'Tuner track is not record armed - switch the tuner off \z
                and on to fix it'
        end
    end
    return 'Toggle tuner (right click for settings)'
end

-- What every click on the box does. Parked (the tuner is on but we are in
-- another project tab) means "bring it here", not "turn it off".
function ToggleTuner()
    if UpdateParked() then
        MoveTunerHere()
    else
        SetTunerEnabled(not T.on)
    end
end

-- Guards against NaN reaching the reference pitch, which would otherwise
-- survive the range check (every comparison against NaN is false) and then
-- crash FreqToNote on the next detected note.
function SetReferencePitch(a4)
    if type(a4) ~= 'number' or a4 ~= a4 then return end
    T.a4 = math.max(380, math.min(500, a4))
    reaper.SetExtState(extname, 'a4_ref', T.a4, true)
    T.hist = {}
    is_redraw = true
end

function SetTunerGate(gate)
    AttachGmem(GMEM_NAME)
    T.gate = gate
    reaper.SetExtState(extname, 'gate', gate, true)
    GWrite(GB + 10, gate)
    T.hist = {}
    is_redraw = true
end

-- One time reset of the reference pitch to 440 Hz. Anything the user sets
-- from here on is remembered as usual.
if reaper.GetExtState(extname, 'a4_reset') == '1' then
    T.a4 = tonumber(reaper.GetExtState(extname, 'a4_ref')) or 440
    if T.a4 ~= T.a4 or T.a4 < 380 or T.a4 > 500 then T.a4 = 440 end
else
    reaper.SetExtState(extname, 'a4_ref', 440, true)
    reaper.SetExtState(extname, 'a4_reset', '1', true)
end

AttachGmem(GMEM_NAME)
GWrite(GB + 10, T.gate)
GWrite(GB + 17, T.low_hz)

function GetTransportScale()
    local _, new_dpi = reaper.ThemeLayout_GetLayout('trans', -3)
    local _, layout = reaper.ThemeLayout_GetLayout('trans', -1)
    local scale = tonumber(new_dpi) / 256
    if type(layout) == 'string' and not attach_window_title then
        local layout_scale = tonumber(layout:match('^(%d+)%%'))
        if layout_scale then scale = scale * layout_scale / 100 end
    end
    return is_macos and 1 or scale, scale
end

function Scale(value, scale)
    if not tonumber(value) then return value end
    return math.floor(value * scale + 0.5)
end

local measure_scale, draw_scale = GetTransportScale()
-- Smallest size the box is allowed to have (width and height in pixels)
local min_box_size = Scale(12, measure_scale)

-------------------------------- FUNCTIONS -----------------------------------

AttachGmem(MOUSE_GMEM)
local mouse_pos_state = reaper.gmem_read(0)

local function GetMousePosition()
    AttachGmem(MOUSE_GMEM)
    local global_state = reaper.gmem_read(0)
    if global_state > mouse_pos_state then
        mouse_pos_state = global_state
        local mx, my = reaper.gmem_read(1), reaper.gmem_read(2)
        if mx % 1 ~= 0 or my % 1 ~= 0 then
            mx, my = reaper.GetMousePosition()
        end
        return mx // 1, my // 1
    else
        mouse_pos_state = mouse_pos_state + 1
        local x, y = reaper.GetMousePosition()
        reaper.gmem_write(0, mouse_pos_state)
        reaper.gmem_write(1, x)
        reaper.gmem_write(2, y)
        return x, y
    end
end

function EscapeString(str)
    local function EscapeChar(char)
        if char == ',' then return '\\,' end
        if char == ':' then return '\\:' end
        if char == '{' then return '\\[' end
        if char == '}' then return '\\]' end
        if char == '\\' then return '\\&' end
    end
    return str:gsub('[,:{}\\]', EscapeChar)
end

function UnEscapeString(str)
    local function UnEscapeChar(char)
        if char == ',' then return ',' end
        if char == ':' then return ':' end
        if char == '[' then return '{' end
        if char == ']' then return '}' end
        if char == '&' then return '\\' end
    end
    return str:gsub('\\([,:%[%]&])', UnEscapeChar)
end

function Serialize(value, add_newlines)
    local value_type = type(value)
    if value_type == 'string' then return 's:' .. EscapeString(value) end
    if value_type == 'number' then return 'n:' .. value end
    if value_type == 'boolean' then return 'b:' .. (value and 1 or 0) end
    if value_type == 'table' then
        local value_str = 't:{'
        local has_elems = false
        for key, elem in pairs(value) do
            if type(elem) ~= 'function' then
                -- Avoid adding protected elements that start with underscore
                local is_str_key = type(key) == 'string'
                if not is_str_key or key:sub(1, 1) ~= '_' then
                    if is_str_key then key = EscapeString(key) end
                    if not has_elems and add_newlines then
                        value_str = value_str .. '\n'
                    end
                    local entry = Serialize(elem, add_newlines)
                    value_str = value_str .. key .. ':' .. entry .. ','
                    if add_newlines then value_str = value_str .. '\n' end
                    has_elems = true
                end
            end
        end
        if has_elems then
            value_str = value_str:sub(1, -2)
            if add_newlines then value_str = value_str .. '\n' end
        end
        return value_str .. '}'
    end
    return ''
end

function Deserialize(value_str)
    local value_type, payload = value_str:sub(1, 1), value_str:sub(3)
    if value_type == 's' then return UnEscapeString(payload) end
    if value_type == 'n' then return tonumber(payload) end
    if value_type == 'b' then return payload == '1' end
    if value_type == 't' then
        local matches = {}
        local m = 0

        local function AddMatch(table_str)
            m = m + 1
            local match = {}
            local i = 1
            for value in (table_str .. ','):gmatch('(.-[^\\]),\r?\n?') do
                match[i] = value
                i = i + 1
            end
            matches[m] = match
            return m
        end

        local _, bracket_cnt = payload:gsub('{', '')
        for _ = 1, bracket_cnt do
            payload = payload:gsub('{\r?\n?([^{}]*)\r?\n?}', AddMatch, 1)
        end

        local function AssembleTable(match)
            local ret = {}
            for _, elem in ipairs(match) do
                local key, value = elem:match('^(.-[^\\]):(.-)$')
                key = tonumber(key) or UnEscapeString(key)
                if value:sub(1, 1) == 't' then
                    local n = tonumber(value:match('^t:(.-)$'))
                    ret[key] = AssembleTable(matches[n])
                else
                    ret[key] = Deserialize(value)
                end
            end
            return ret
        end
        return AssembleTable(matches[m])
    end
end

function ExtSave(key, value, is_temporary)
    if value == nil then
        reaper.DeleteExtState(extname, key, not is_temporary)
        return
    end
    local value_str = Serialize(value)
    if not value_str then return end
    reaper.SetExtState(extname, key, value_str, not is_temporary)
end

function ExtLoad(key, default)
    local value = default
    local value_str = reaper.GetExtState(extname, key)
    if value_str ~= '' then value = Deserialize(value_str) end
    return value
end

function GetStartupHookCommandID(no_register)
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 and no_register then return 0 end
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

-- read_only: just report, never touch the action list (menu building)
function IsStartupHookEnabled(opt_cmd_id, read_only)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = opt_cmd_id or GetStartupHookCommandID(read_only)
    if cmd_id == 0 then return false end
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

function CreateMenuRecursive(menu)
    local str = ''
    if menu.title then str = str .. '>' .. menu.title .. '|' end

    for _, entry in ipairs(menu) do
        if entry then
            local arg = entry.arg
            if entry.IsGrayed and entry.IsGrayed(arg) or entry.is_grayed then
                str = str .. '#'
            end
            if entry.IsChecked and entry.IsChecked(arg) or entry.is_checked then
                str = str .. '!'
            end
            if #entry > 0 then
                str = str .. CreateMenuRecursive(entry) .. '|'
            else
                if entry.title or entry.separator then
                    str = str .. (entry.title or '') .. '|'
                end
            end
        end
    end
    if menu.title then str = str .. '<' end
    return str
end

function ReturnMenuRecursive(menu, idx, i)
    i = i or 1
    for _, entry in ipairs(menu) do
        if entry then
            if #entry > 0 then
                i = ReturnMenuRecursive(entry, idx, i)
                if i < 0 then return i end
            elseif entry.title then
                if i == math.floor(idx) then
                    if entry.OnReturn then entry.OnReturn(entry.arg) end
                    return -1
                end
                i = i + 1
            end
        end
    end
    return i
end

local function ParseIni(content)
    local t = {}
    for line in content:gmatch('[^\r\n]+') do
        line = line:match('^%s*(.-)%s*$')
        if line ~= '' and line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
            local key, value = line:match('^([^=]+)%s*=%s*(.*)$')
            if key and value then
                local value_num = not key:match('_color$') and tonumber(value)
                t[key:match('^%s*(.-)%s*$')] = value_num or value
            end
        end
    end
    return t
end

function PrintIni()
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(prev_color_theme)
    local settings = theme_settings[theme_key]
    if settings then
        local sorted_settings = {}
        for k, v in pairs(settings) do
            sorted_settings[#sorted_settings + 1] = {key = k, value = v}
        end
        local function SortByName(t, key)
            local function Format(d) return ('%03d%s'):format(#d, d) end
            local function Compare(a, b)
                local ak, bk = tostring(a[key]), tostring(b[key])
                local ac, bc = ak:find('_color') ~= nil,
                    bk:find('_color') ~= nil
                if ac ~= bc then return bc end
                return ak:gsub('%d+', Format) < bk:gsub('%d+', Format)
            end
            table.sort(t, Compare)
        end
        SortByName(sorted_settings, 'key')

        reaper.ClearConsole()
        reaper.ShowConsoleMsg(box_name:lower() .. '.ini:\n\n')
        for _, entry in ipairs(sorted_settings) do
            reaper.ShowConsoleMsg(entry.key .. '=' .. entry.value .. '\n')
        end
    else
        reaper.ShowConsoleMsg('No saved settings')
    end
end

function LoadIntegratedSettings(theme_path)
    local file_name = box_name:lower() .. '.ini'
    if not theme_path:lower():match('%.reaperthemezip$') then
        -- Read theme file to get image resource path
        local theme_file = io.open(theme_path, 'r')
        if not theme_file then return nil, 'Could not read theme file' end
        local content = theme_file:read('*a')
        theme_file:close()

        local ui_img
        for line in content:gmatch('[^\r\n]+') do
            ui_img = line:match('^%s*ui_img=(.+)%s*$')
            if ui_img then break end
        end

        if not ui_img then return nil, 'Could not parse theme file' end

        local theme_dir = theme_path:match('^(.+)/')
        if is_windows then theme_dir = theme_path:match('^(.+)\\') end

        if ui_img:lower():match('%.reaperthemezip$') then
            -- Image resource path is a zipped
            theme_path = ConcatPath(theme_dir, ui_img)
        else
            -- Image resource path is unzipped
            local config_path = ConcatPath(theme_dir, ui_img, file_name)
            if not reaper.file_exists(config_path) then return nil, 'No config' end

            local config_file = io.open(config_path, 'r')
            if not config_file then return nil, 'Could not read config file' end
            content = config_file:read('*a')
            config_file:close()

            local config = ParseIni(content)
            if not next(config) then return nil, 'Empty config' end
            return config
        end
    end

    local zip, err = reaper.JS_Zip_Open(theme_path, 'r', 0)
    if err ~= 0 then return nil, reaper.JS_Zip_ErrorString(err) end

    local count, list = reaper.JS_Zip_ListAllEntries(zip)
    if count < 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(count)
    end

    local found_entry = nil
    for entry in list:gmatch('[^%z]+') do
        if entry:find(file_name, 1, true) then
            found_entry = entry
            break
        end
    end

    if not found_entry then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, 'Entry not found: ' .. file_name
    end

    local ret = reaper.JS_Zip_Entry_OpenByName(zip, found_entry)
    if ret ~= 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(ret)
    end

    local bytes, content = reaper.JS_Zip_Entry_ExtractToMemory(zip)
    reaper.JS_Zip_Entry_Close(zip)
    reaper.JS_Zip_Close(theme_path, zip)

    if bytes < 0 then
        return nil, reaper.JS_Zip_ErrorString(bytes)
    end

    local config = ParseIni(content)
    if not next(config) then return nil, 'Empty config' end
    return config
end

function SetThemeIntegration(value)
    local i = 0
    local param_pattern = box_name:lower()
    repeat
        local ret, desc, val, def, min, max = reaper.ThemeLayout_GetParameter(i)
        if desc and desc:lower():match(param_pattern) then
            if val ~= value and def == 0 and min == 0 and max == 1 then
                reaper.ThemeLayout_SetParameter(i, value, false)
                reaper.ThemeLayout_RefreshAll()
            end
            break
        end
        i = i + 1
    until not ret
end

function GetThemeKey(path)
    if not path then path = reaper.GetLastColorThemeFile() or '' end
    if path == '' then
        -- Note: Theme path can be empty in new REAPER installations?
        local reaper_version = reaper.GetAppVersion():match('[%d]+')
        return ('ColorThemes/Default_%s.0'):format(reaper_version)
    end
    -- Use relative path if inside resource directory
    local resource_dir = reaper.GetResourcePath()
    -- Note: Using find to suppress matching special characters in path
    local _, end_idx = path:find(resource_dir, 0, true)
    if end_idx then path = path:sub(end_idx + 2) end

    -- Replace windows path separator with unix (make cross-platform)
    if is_windows then path = path:gsub('\\', '/') end
    -- Remove file extension
    path = path:gsub('%.([^./]+)$', '')
    return path
end

function GetThemeFromKey(key)
    local theme_name = key:match('([^/]+)$')
    if is_windows then key = key:gsub('/', '\\') end

    local function FindInDir(dir)
        local fallback = nil
        local i = 0
        repeat
            local file_name = reaper.EnumerateFiles(dir, i)
            if file_name then
                local file_name_no_ext = file_name:gsub('%.([^./\\]+)$', '')
                if file_name_no_ext == theme_name then
                    if file_name:lower():match('%.reaperthemezip$') then
                        return ConcatPath(dir, file_name)
                    else
                        fallback = ConcatPath(dir, file_name)
                    end
                end
            end
            i = i + 1
        until not file_name
        return fallback
    end

    local dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    local result = FindInDir(dir)
    if result then return result end

    key = ConcatPath(reaper.GetResourcePath(), key)
    dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    return FindInDir(dir)
end

function LoadThemeSettings(theme_path, only_appeareance)
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)
    local settings = theme_settings[theme_key]

    if not settings then
        local theme_file = GetThemeFromKey(theme_key)
        if theme_file then
            local integrated_settings = LoadIntegratedSettings(theme_file)
            if integrated_settings then
                settings = integrated_settings
                SetEditMode(false)
            end
        end
    end

    local has_settings = settings ~= nil
    settings = settings or {}

    local function SafeColor(v)
        -- a non integer here (an old serialised setting, a hand edited ini)
        -- would make ('%X'):format throw rather than just be ignored
        if type(v) == 'number' then
            if v ~= v or v % 1 ~= 0 or v < 0 then return nil end
            v = ('%X'):format(v)
        end
        if type(v) ~= 'string' then return nil end
        v = v:gsub('^#', '')
        if #v > 8 or not tonumber(v, 16) then return nil end
        return v
    end

    user_bg_color = SafeColor(settings.bg_color)
    user_text_color = SafeColor(settings.text_color)
    user_border_color = SafeColor(settings.border_color)
    user_swing_color = SafeColor(settings.swing_color)
    user_adaptive_color = SafeColor(settings.adaptive_color)
    user_font_height = settings.font_height
    user_font_family = settings.font_family
    user_font_weight = settings.font_weight
    user_font_yoffs = settings.font_yoffs
    user_corner_radius = settings.corner_radius
    user_snap_size = settings.snap_size
    user_snap_on_color = SafeColor(settings.snap_on_color)
    user_snap_off_color = SafeColor(settings.snap_off_color)
    user_snap_sep_color = SafeColor(settings.snap_sep_color)

    if settings.draw_scale and settings.draw_scale ~= draw_scale then
        local scale_factor = draw_scale / settings.draw_scale
        user_font_height = Scale(user_font_height, scale_factor)
        user_font_yoffs = Scale(user_font_yoffs, scale_factor)
        user_corner_radius = Scale(user_corner_radius, scale_factor)
        user_snap_size = Scale(user_snap_size, scale_factor)
    end

    if only_appeareance then return has_settings end

    if attach_window_title then
        settings = ExtLoad('attach_settings') or settings
    end

    local function SafeNumber(v)
        if type(v) ~= 'number' or v ~= v then return nil end
        return v
    end

    attach_x = SafeNumber(settings.attach_x)
    attach_mode = SafeNumber(settings.attach_mode)
    attach_center_x = SafeNumber(settings.attach_center_x)
    attach_center_mode = SafeNumber(settings.attach_center_mode)

    local new_box_x = SafeNumber(settings.box_x)
    local new_box_y = SafeNumber(settings.box_y)
    local new_box_w = SafeNumber(settings.box_w)
    local new_box_h = SafeNumber(settings.box_h)
    if not new_box_x or not new_box_y or not new_box_w or not new_box_h or
        new_box_w <= 0 or new_box_h <= 0 then
        return false
    end

    local saved_measure_scale = SafeNumber(settings.measure_scale)
    if saved_measure_scale and saved_measure_scale > 0 and
        saved_measure_scale ~= measure_scale then
        local scale_factor = measure_scale / saved_measure_scale
        new_box_x = Scale(new_box_x, scale_factor)
        new_box_y = Scale(new_box_y, scale_factor)
        new_box_w = Scale(new_box_w, scale_factor)
        new_box_h = Scale(new_box_h, scale_factor)
        attach_x = Scale(attach_x, scale_factor)
        attach_center_x = Scale(attach_center_x, scale_factor)
    end

    if attach_x or attach_center_x then
        local attached_box_x = GetAttachPosition()
        if attached_box_x then
            new_box_x = attached_box_x
        else
            -- The rectangle is still usable even if its relative anchor is
            -- incomplete. Keep its exact position and stop tracking the bad
            -- anchor instead of rebuilding a toolbar-sized default box.
            attach_x, attach_mode = nil, nil
            attach_center_x, attach_center_mode = nil, nil
        end
    end
    SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
    return has_settings or attach_window_title ~= nil
end

function SaveThemeSettings(theme_path)
    local settings = {
        box_x = box_x,
        box_y = box_y,
        box_w = box_w,
        box_h = box_h,
        attach_x = attach_x,
        attach_mode = attach_mode,
        attach_center_x = attach_center_x,
        attach_center_mode = attach_center_mode,
        bg_color = user_bg_color,
        text_color = user_text_color,
        border_color = user_border_color,
        swing_color = user_swing_color,
        adaptive_color = user_adaptive_color,
        font_height = user_font_height,
        font_family = user_font_family,
        font_weight = user_font_weight,
        font_yoffs = user_font_yoffs,
        corner_radius = user_corner_radius,
        snap_size = user_snap_size,
        snap_on_color = user_snap_on_color,
        snap_off_color = user_snap_off_color,
        snap_sep_color = user_snap_sep_color,
        draw_scale = draw_scale,
        measure_scale = measure_scale,
    }

    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)

    if attach_window_title then
        local attach_settings = {
            box_x = box_x,
            box_y = box_y,
            box_w = box_w,
            box_h = box_h,
            attach_x = attach_x,
            attach_mode = attach_mode,
            measure_scale = measure_scale,
        }
        ExtSave('attach_settings', attach_settings)

        local prev_settings = theme_settings[theme_key]
        if prev_settings then
            for key in pairs(attach_settings) do
                settings[key] = prev_settings[key]
            end
        end
    end

    theme_settings[theme_key] = settings
    ExtSave('theme_settings', theme_settings)
end

function GetThemeColor(key, flag)
    local color = reaper.GetThemeColor(key, flag or 0)
    if is_windows then
        local r, g, b = reaper.ColorFromNative(color)
        color = r * 65536 + g * 256 + b
    end
    return color
end

function RGBAToHex(r, g, b, a)
    local int_color = r * 65536 + g * 256 + b
    if not a or a == 255 then return ('#%06x'):format(int_color) end
    return ('#%06x%02x'):format(int_color, a)
end

function IntToHex(int_color)
    local r, g, b = reaper.ColorFromNative(int_color)
    return RGBAToHex(r, g, b)
end

function TintIntColor(color, factor)
    local a = color & 0xFF000000
    local r = (color & 0xFF0000) >> 16
    local g = (color & 0x00FF00) >> 8
    local b = (color & 0x0000FF)

    r = (r * factor) // 1
    g = (g * factor) // 1
    b = (b * factor) // 1

    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b

    return (r * 65536 + g * 256 + b) | a
end

function GetUserColor()
    local ret, color = reaper.GR_SelectColor(main_hwnd)
    if ret ~= 0 then return IntToHex(color):gsub('#', '') end
end

function SetCustomSize()
    local title = 'Size/Position'
    local captions = 'Width:,Height:,X pos:,Y pos:'

    local floor = math.floor
    local curr_vals = {floor(box_w), floor(box_h), floor(box_x), floor(box_y)}
    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 4, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = tonumber(input)
    end

    local x, y, w, h
    if input_vals[1] then w = floor(input_vals[1] + 0.5) end
    if input_vals[2] then h = floor(input_vals[2] + 0.5) end
    if input_vals[3] then x = floor(input_vals[3] + 0.5) end
    if input_vals[4] then y = floor(input_vals[4] + 0.5) end
    SetBoxCoords(x, y, w, h)

    UpdateAttachPosition()
    EnsureBoxVisible()

    SaveThemeSettings(prev_color_theme)
end

function SetCustomCornerRadius()
    local title = 'Corners'
    local captions = 'Corner radius: (e.g. 4)'

    local curr_vals_str = ('%s'):format(user_corner_radius or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_corner_radius = tonumber(input_vals[1])
    user_corner_radius = user_corner_radius and math.floor(user_corner_radius)
    is_redraw = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomFont()
    local title = 'Font'
    local captions = 'Height: (e.g.42),Family (e.g. Comic Sans):,\z
        Weight (0/400/700):,Y offset:,extrawidth=50'

    local curr_vals_str = ('%s,%s,%s,%s'):format(
        user_font_height or '',
        user_font_family or '',
        user_font_weight or '',
        user_font_yoffs or ''
    )

    local ret, inputs = reaper.GetUserInputs(title, 4, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_font_height = tonumber(input_vals[1])
    user_font_family = input_vals[2]
    if user_font_family == '' then user_font_family = nil end
    user_font_weight = tonumber(input_vals[3])
    user_font_yoffs = tonumber(input_vals[4])
    is_resize = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomSnapSize()
    local title = 'Icon'
    local captions = 'Icon size: (e.g.10),extrawidth=50'

    local curr_vals_str = ('%s'):format(
        user_snap_size or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_snap_size = tonumber(input_vals[1])
    is_resize = true

    SaveThemeSettings(prev_color_theme)

    if user_snap_size and user_snap_size * 2.5 > box_w / 1.3 then
        local msg = 'You entered a large size. The icon will not be \z
        visible.\n\nReduce the size or make the box wider.'
        reaper.MB(msg, 'Warning', 0)
    end
end

function SetCustomColors()
    local title = 'Custom Colors'
    local captions = 'Background: (e.g. #525252),Text:,Border:,Arrow (off pitch):,\z
        Arrow (in tune):,Icon on:,Icon off:,Lines and idle arrows:'

    local curr_vals = {}
    local function AddCurrentValue(color)
        local hex_num = color and tonumber(color, 16)
        local pattern = color and #color == 8 and ('#%.8X') or ('#%.6X')
        curr_vals[#curr_vals + 1] = hex_num and pattern:format(hex_num) or ''
    end

    AddCurrentValue(user_bg_color)
    AddCurrentValue(user_text_color)
    AddCurrentValue(user_border_color)
    AddCurrentValue(user_swing_color)
    AddCurrentValue(user_adaptive_color)
    AddCurrentValue(user_snap_on_color)
    AddCurrentValue(user_snap_off_color)
    AddCurrentValue(user_snap_sep_color)

    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 8, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local colors = {}
    local has_invalid_color = false

    local function ValidateColor(color)
        local is_valid = #color <= 8 and tonumber(color, 16)
        if not is_valid then has_invalid_color = true end
        return is_valid and color or nil
    end

    local i = 1
    for input in (inputs .. ','):gmatch('[^,]*') do
        input = input:gsub('^#', '')
        if input == '' then input = nil else input = ValidateColor(input) end
        colors[i] = input
        i = i + 1
    end

    user_bg_color = colors[1]
    user_text_color = colors[2]
    user_border_color = colors[3]
    user_swing_color = colors[4]
    user_adaptive_color = colors[5]
    user_snap_on_color = colors[6]
    user_snap_off_color = colors[7]
    user_snap_sep_color = colors[8]

    SaveThemeSettings(prev_color_theme)
    is_redraw = true

    if has_invalid_color then
        local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
        reaper.MB(msg, 'Invalid input', 0)
    end
end

function InvalidateBoxRect()
    if not box_x then return end
    reaper.JS_Window_InvalidateRect(window_hwnd, box_x, box_y,
        box_x + box_w, box_y + box_h, false)
end

function GetBitmapSize()
    local pixel_ratio = draw_scale / measure_scale
    local bm_w, bm_h = box_w * pixel_ratio, box_h * pixel_ratio
    return math.floor(bm_w), math.floor(bm_h)
end

function ClearBitmap(bm, color)
    -- Note: Clear to transparent avoids artifacts on aliased rect corners
    if is_windows then
        reaper.JS_LICE_Clear(bm, 0x00000000)
    else
        reaper.JS_LICE_Clear(bm, color & 0x00FFFFFF)
    end
end

function DrawRect(bm, color, x, y, w, h, fill, r, a)
    if a == 0 then return end
    fill = fill or 0
    r = r or 0
    a = a or 1

    if not fill or fill == 0 then
        local LICE_RoundRect = reaper.JS_LICE_RoundRect
        for _ = 1, math.max(1, draw_scale) do
            LICE_RoundRect(bm, x, y, w - 1, h - 1, r, color, a, '', true)
            x, y, w, h = x + 1, y + 1, w - 2, h - 2
        end
        return
    end

    if not r or r == 0 then
        -- Body
        reaper.JS_LICE_FillRect(bm, x, y, w, h, color, a, '')
        return
    end

    if h <= 2 * r then r = math.floor(h / 2 - 1) end
    if w <= 2 * r then r = math.floor(w / 2 - 1) end

    -- Top left corner
    local LICE_FillCircle = reaper.JS_LICE_FillCircle
    LICE_FillCircle(bm, x + r, y + r, r, color, a, '', true)
    -- Top right corner
    LICE_FillCircle(bm, x + w - r - 1, y + r, r, color, a, '', true)
    -- Bottom right corner
    LICE_FillCircle(bm, x + w - r - 1, y + h - r - 1, r, color, a, '', true)
    -- Bottom left corner
    LICE_FillCircle(bm, x + r, y + h - r - 1, r, color, a, '', true)
    -- Ends
    reaper.JS_LICE_FillRect(bm, x, y + r, r, h - r * 2, color, a, '')
    reaper.JS_LICE_FillRect(bm, x + w - r, y + r, r, h - r * 2, color, a, '')
    -- Body and sides
    reaper.JS_LICE_FillRect(bm, x + r, y, w - r * 2, h, color, a, '')
end

function DrawBackground(bm, bg_color, w, h, corner_r, a)
    if a == 0 then return end
    if not bg_bitmap then
        bg_bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
        prev_bg_color = nil
    end

    if bg_color ~= prev_bg_color or corner_r ~= prev_bg_corner_r then
        prev_bg_color = bg_color
        prev_bg_corner_r = corner_r
        prev_snap_color = nil
        ClearBitmap(bg_bitmap, bg_color)
        DrawRect(bg_bitmap, bg_color, 0, 0, w, h, true, corner_r)
    end
    reaper.JS_LICE_Blit(bm, 0, 0, bg_bitmap, 0, 0, w, h, a, 'COPY')
end


-- ---------------------------------------------------------------------------
-- Tuning fork icon
--
-- Rasterised from its SVG path (8x8 viewBox) rather than approximated with
-- primitives, so it stays true at any size:
--   M2 0h1v4q1.5 2 3 0V0h1v4c0 3-5 3-5 0m2 1h1v3H4
-- The coverage mask is built once per pixel size and cached, so drawing is
-- just a walk over a precomputed list.
-- ---------------------------------------------------------------------------

local fork_polys
local fork_cache = {}
local fork_cache_n = 0

local function BuildForkPolys()
    local outer = {{2, 0}, {3, 0}, {3, 4}}
    for i = 1, 16 do                       -- q1.5 2 3 0
        local t = i / 16
        local a = 1 - t
        outer[#outer + 1] = {a * a * 3 + 2 * a * t * 4.5 + t * t * 6,
                             a * a * 4 + 2 * a * t * 6 + t * t * 4}
    end
    outer[#outer + 1] = {6, 0}             -- V0
    outer[#outer + 1] = {7, 0}             -- h1
    outer[#outer + 1] = {7, 4}             -- v4
    for i = 1, 16 do                       -- c0 3 -5 3 -5 0
        local t = i / 16
        local a = 1 - t
        outer[#outer + 1] = {
            a ^ 3 * 7 + 3 * a * a * t * 7 + 3 * a * t * t * 2 + t ^ 3 * 2,
            a ^ 3 * 4 + 3 * a * a * t * 7 + 3 * a * t * t * 7 + t ^ 3 * 4}
    end
    fork_polys = {outer, {{4, 5}, {5, 5}, {5, 8}, {4, 8}}}
end

local function PointInPoly(poly, x, y)
    local inside = false
    local n = #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i][1], poly[i][2]
        local xj, yj = poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and
            x < (xj - xi) * (y - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Grid fitting, the way a font rasteriser hints a glyph. Every straight
-- edge of the fork sits on a whole unit of the 8 unit grid (both prongs and
-- the stem are exactly one unit wide), so snapping those unit boundaries to
-- whole pixels puts every vertical edge on a pixel boundary at ANY size.
-- Only the bowl of the U is left to antialiasing.
local function SnapUnit(v, u)
    local k = math.floor(v)
    if k >= 8 then return math.floor(8 * u + 0.5) end
    local a = math.floor(k * u + 0.5)
    local b = math.floor((k + 1) * u + 0.5)
    return a + (b - a) * (v - k)
end

-- Scanline rasteriser. Coverage is exact horizontally and 4x supersampled
-- vertically, which is both better looking and roughly 60x cheaper than
-- point sampling every pixel (that cost 66 ms for a 52 px icon, a visible
-- hitch every time the box was resized).
local SUB = 4

local function ScanSpans(poly, y, out)
    local n = #poly
    local xs = {}
    local j = n
    for i = 1, n do
        local x1, y1 = poly[i][1], poly[i][2]
        local x2, y2 = poly[j][1], poly[j][2]
        if (y1 > y) ~= (y2 > y) then
            xs[#xs + 1] = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
        end
        j = i
    end
    table.sort(xs)
    for i = 1, #xs - 1, 2 do
        if xs[i + 1] > xs[i] then out[#out + 1] = {xs[i], xs[i + 1]} end
    end
end

function GetForkMask(size)
    if fork_cache[size] then return fork_cache[size] end
    if not fork_polys then BuildForkPolys() end
    if fork_cache_n > 8 then fork_cache = {}; fork_cache_n = 0 end

    -- grid fit the outline into pixel space
    local u = size / 8
    local hinted = {}
    for i = 1, #fork_polys do
        local src, dst = fork_polys[i], {}
        for j = 1, #src do
            dst[j] = {SnapUnit(src[j][1], u), SnapUnit(src[j][2], u)}
        end
        hinted[i] = dst
    end

    local cov = {}
    for sy = 0, size * SUB - 1 do
        local y = (sy + 0.5) / SUB
        local row = math.floor(y) * size

        -- spans of each subpath, then their union (the stem overlaps the
        -- bowl of the U, so an even-odd merge would cancel it out)
        local spans = {}
        ScanSpans(hinted[1], y, spans)
        ScanSpans(hinted[2], y, spans)
        table.sort(spans, function(a, b) return a[1] < b[1] end)

        local ca, cb
        for i = 1, #spans + 1 do
            local sp = spans[i]
            if sp and ca and sp[1] <= cb then
                if sp[2] > cb then cb = sp[2] end
            else
                if ca then
                    -- accumulate exact horizontal coverage
                    local px = math.floor(ca)
                    while px < cb do
                        local a = ca > px and ca or px
                        local b = cb < px + 1 and cb or px + 1
                        if b > a and px >= 0 and px < size then
                            local k = row + px
                            cov[k] = (cov[k] or 0) + (b - a) / SUB
                        end
                        px = px + 1
                    end
                end
                if sp then ca, cb = sp[1], sp[2] end
            end
        end
    end

    -- Merge the coverage grid into rectangles. The glyph is mostly solid
    -- bars - two prongs, the bowl of the U and the stem - so filling it a
    -- pixel at a time meant ~120 LICE calls per redraw at a 26 px box and
    -- ~400 at 200% theme scaling, on every frame a ringing string moved the
    -- readout. Runs are merged horizontally and then vertically, which
    -- brings the same picture down to a dozen or so rectangles.
    --
    -- Coverage is quantised to 1/255 first, because that is the resolution
    -- the alpha channel has anyway: it costs nothing visually and lets
    -- neighbouring pixels of a solid area compare equal.
    local q = {}
    for k, v in pairs(cov) do
        if v > 0.002 then
            q[k] = math.floor((v < 1 and v or 1) * 255 + 0.5)
        end
    end

    local runs = {}
    for y = 0, size - 1 do
        local row = y * size
        local x = 0
        while x < size do
            local v = q[row + x]
            if v then
                local w = 1
                while x + w < size and q[row + x + w] == v do w = w + 1 end
                runs[#runs + 1] = {x, y, w, 1, v}
                x = x + w
            else
                x = x + 1
            end
        end
    end

    local mask, open = {}, {}
    for i = 1, #runs do
        local r = runs[i]
        local key = r[1] * 1000000 + r[3] * 1000 + r[5]
        local prev = open[key]
        if prev and prev[2] + prev[4] == r[2] then
            prev[4] = prev[4] + 1
        else
            mask[#mask + 1] = r
            open[key] = r
        end
    end

    fork_cache[size] = mask
    fork_cache_n = fork_cache_n + 1
    return mask
end

-- cx, cy is where the visible glyph should be centred
function DrawTuningFork(bm, color, cx, cy, size, a)
    if a == 0 or size < 6 then return end
    local u = size / 8
    local mask = GetForkMask(size)
    -- offsets are whole pixels so the hinted edges stay on the grid
    local ox = math.floor(cx - (SnapUnit(2, u) + SnapUnit(7, u)) / 2 + 0.5)
    local oy = math.floor(cy - size / 2 + 0.5)
    local FillRect = reaper.JS_LICE_FillRect
    for i = 1, #mask do
        local p = mask[i]
        FillRect(bm, ox + p[1], oy + p[2], p[3], p[4], color,
            a * p[5] / 255, '')
    end
end

-- ---------------------------------------------------------------------------
-- Fixed cell text metrics
--
-- Real tuners never let the note move. Every glyph gets a cell of a fixed
-- width, measured once per font change, so the cluster width does not depend
-- on what is being displayed.
-- ---------------------------------------------------------------------------

glyph = glyph or {}

function MeasureGlyphs()
    local g = {}
    local digit_w = 0
    for i = 0, 9 do
        local c = tostring(i)
        g[c] = gfx.measurestr(c)
        if g[c] > digit_w then digit_w = g[c] end
    end
    local letter_w = 0
    for c in ('ABCDEFG'):gmatch('.') do
        g[c] = gfx.measurestr(c)
        if g[c] > letter_w then letter_w = g[c] end
    end
    for _, c in ipairs({'#', '-', '+', ' '}) do g[c] = gfx.measurestr(c) end
    g.digit_w = digit_w
    g.letter_w = letter_w
    g.sign_w = math.max(g['-'], g['+'])
    g.sharp_w = g['#']
    -- widest possible note is letter + sharp; the octave is not shown
    g.note_w = letter_w + g.sharp_w
    glyph = g
end

-- Filled triangle drawn as scanlines. dir = 1 points right, -1 points left.
function DrawTriangle(bm, color, x, y, w, h, dir, a)
    if a == 0 or w < 1 or h < 1 then return end
    local FillRect = reaper.JS_LICE_FillRect
    local half = (h - 1) / 2
    for j = 0, h - 1 do
        local d = math.abs(j - half)
        local len = math.floor(w * (1 - d / (half + 0.5)) + 0.5)
        if len > 0 then
            local px = dir > 0 and x or (x + w - len)
            FillRect(bm, px, y + j, len, 1, color, a, '')
        end
    end
end

function DrawBitmap(bm, w, h)
    local alpha = 0xFF000000

    -- ------------------------------------------------------------------
    -- Background and border
    -- ------------------------------------------------------------------
    local bg_color = tonumber(user_bg_color or '242424', 16)
    local bg_alpha = 1
    if user_bg_color and #user_bg_color > 6 then
        bg_alpha = (bg_color >> 24) / 255
    end
    bg_color = bg_color | alpha

    ClearBitmap(bm, bg_color)

    local corner_radius
    if user_corner_radius then
        corner_radius = math.floor(user_corner_radius)
    else
        -- 5, not 6: 10 px at 200%, which is what the box looks right at
        -- next to REAPER's own transport controls on the stock theme.
        corner_radius = Scale(5, draw_scale)
    end
    DrawBackground(bm, bg_color, w, h, corner_radius, bg_alpha)

    local border_color
    local border_alpha = 1
    if user_border_color then
        border_color = tonumber(user_border_color or '242424', 16)
        if #user_border_color > 6 then
            border_alpha = (border_color >> 24) / 255
        end
        border_color = border_color | alpha
    end
    if border_color then
        DrawRect(bm, border_color, 0, 0, w, h, false,
            corner_radius, border_alpha)
    end

    -- ------------------------------------------------------------------
    -- Colors
    -- ------------------------------------------------------------------
    local arrow_color                       -- lit, note needs adjusting
    local arrow_alpha = 1
    if user_swing_color then
        arrow_color = tonumber(user_swing_color, 16)
        if #user_swing_color > 6 then arrow_alpha = (arrow_color >> 24) / 255 end
        arrow_color = arrow_color | alpha
    else
        arrow_color = 0xD04A4A | alpha
    end

    -- In tune defaults to the theme's own accent colour, the same one
    -- Gridbox uses. That is green on the stock REAPER theme and picks up
    -- whatever a custom theme uses, and it is still overridable per theme.
    local tune_color
    if user_adaptive_color then
        tune_color = tonumber(user_adaptive_color, 16) | alpha
    else
        tune_color = GetThemeColor('areasel_outline') | alpha
    end

    local dim_color = tonumber(user_snap_sep_color or '3a3a3b', 16) | alpha

    -- ------------------------------------------------------------------
    -- Measure the readout first: the on/off dot is only shown when the
    -- box is wide enough to hold it AND the whole readout comfortably.
    -- ------------------------------------------------------------------
    if not glyph.digit_w then MeasureGlyphs() end

    local _, text_h = gfx.measurestr('E')
    local tri_h = math.max(3, math.floor(text_h * 0.62))
    if tri_h % 2 == 0 then tri_h = tri_h + 1 end
    local tri_w = math.max(2, math.floor(tri_h * 0.7))
    local gap = Scale(5, draw_scale)
    local cluster_w = 2 * (tri_w + gap) + glyph.note_w
    local m = Scale(2, draw_scale)

    -- Icon geometry. icon_h is the height of the glyph itself; the left
    -- section is sized from the glyph WIDTH plus generous padding, because
    -- the tuning fork is far narrower than the old dot and inherited its
    -- cramped margins otherwise.
    -- Same height rule the Gridbox snap icon uses, so the two sit side by
    -- side at matching weight at any theme scaling.
    local icon_h = user_snap_size
    icon_h = icon_h or h - 2 * math.max(Scale(4, draw_scale), h // 4)
    icon_h = math.max(6, math.floor(icon_h + 0.5))

    local icon_w = icon_h * 5 / 8
    -- Horizontal breathing room only. The vertical padding comes from
    -- icon_h itself (same rule as the Gridbox snap icon), so it is left
    -- alone; this widens the left section by 4 px a side at 100%, 8 at
    -- 200%, and so on.
    local icon_pad = math.max(Scale(7, draw_scale), icon_w * 0.95)
        + Scale(4, draw_scale)
    local left_w = math.floor(icon_w + 2 * icon_pad + 0.5)

    local show_dot = not hide_snap and icon_h > 0 and left_w > 0 and
        left_w + cluster_w + 4 * m <= w
    if not show_dot then left_w = 0 end

    snap_w = left_w * measure_scale / draw_scale
    local right_w = w - left_w

    -- ------------------------------------------------------------------
    -- Left section: on/off dot
    -- ------------------------------------------------------------------
    if show_dot then
        local on_color, off_color
        local on_alpha, off_alpha = 1, 1
        if user_snap_on_color then
            on_color = tonumber(user_snap_on_color, 16)
            if #user_snap_on_color > 6 then
                on_alpha = (on_color >> 24) / 255
            end
            on_color = on_color | alpha
        else
            on_color = tune_color
        end
        off_color = tonumber(user_snap_off_color or '787878', 16)
        if user_snap_off_color and #user_snap_off_color > 6 then
            off_alpha = (off_color >> 24) / 255
        end
        off_color = off_color | alpha

        local live = TunerIsLive()
        local dot_alpha = live and on_alpha or off_alpha
        local dot_color = live and on_color or off_color
        if prev_is_snap_hovered then
            dot_color = TintIntColor(dot_color, 1.145)
        end

        local sep_m = math.max(Scale(4, draw_scale), h // 14)
        local sep_w = math.max(1, Scale(1, draw_scale))

        DrawTuningFork(bm, dot_color, math.floor((left_w - sep_w) / 2),
            math.floor(h / 2), icon_h, dot_alpha)

        DrawRect(bm, dim_color, left_w - sep_w, sep_m, sep_w, h - 2 * sep_m,
            true, 0, 1)
    end

    -- ------------------------------------------------------------------
    -- Fine deviation bar along the bottom
    -- ------------------------------------------------------------------
    local bar_m = Scale(4, draw_scale)
    local bar_h = math.max(2, Scale(4, draw_scale))
    local bar_reserve = bar_h
    local y_offs = border_color and Scale(1, draw_scale) or 0
    local bar_x = left_w + bar_m
    local bar_w = right_w - 2 * bar_m
    -- how many cents the bar needs to move to change by one pixel; SetDisplay
    -- uses this to avoid redrawing the whole box for sub pixel movement
    T.disp_step = 100 / (bar_w > 1 and bar_w or 1)
    local bar_y = h - bar_h - y_offs
    local bar_mid = bar_x + bar_w // 2

    -- The bar only exists to show how far there is to go, so it is drawn
    -- only while the note is off pitch. Its vertical space is still
    -- reserved either way, otherwise the note would hop up and down.
    local show_bar = TunerIsLive() and T.has_pitch and T.settled
        and not T.in_tune
    if bar_w <= Scale(10, draw_scale) then
        bar_h = 0
        bar_reserve = 0
    elseif show_bar then
        local tick_w = math.max(1, Scale(1, draw_scale))
        DrawRect(bm, dim_color, bar_mid, bar_y, tick_w, bar_h, true, 0, 1)

        local norm = T.disp / 50
        if norm > 1 then norm = 1 end
        if norm < -1 then norm = -1 end
        local len = math.ceil(math.abs(norm) * bar_w / 2)
        if len < tick_w then len = tick_w end
        local x_offs = bar_mid
        if norm < 0 then x_offs = bar_mid - len end
        DrawRect(bm, arrow_color, x_offs, bar_y, len, bar_h, true, 0,
            arrow_alpha)
    end

    -- ------------------------------------------------------------------
    -- Triangles and note letter
    -- ------------------------------------------------------------------
    -- Centre on the full height of the box. The bar lives in the bottom
    -- margin and is not part of the readout, so reserving space for it made
    -- the note sit visibly high whenever the bar was not being drawn.
    local text_y = (h - text_h) // 2

    -- Only on a box too short to fit both, push the text up. This uses the
    -- reserved height rather than whether the bar is currently drawn, so it
    -- can never make the note hop between states.
    local bar_top = h - bar_reserve - y_offs
    if bar_reserve > 0 and text_y + text_h > bar_top then
        text_y = bar_top - text_h
    end
    if text_y < 0 then text_y = 0 end

    if is_macos then text_y = text_y + 1 end
    text_y = text_y + (user_font_yoffs or 0)

    -- Triangles align to the centre of the text block, not to the box, so
    -- they always agree with the letter whatever the font metrics are.
    -- Clamped so that a font taller than the box (possible on an extreme
    -- theme layout) can never push them outside the bitmap.
    if tri_h > h then tri_h = h end
    local tri_y = text_y + (text_h - tri_h) // 2
    if tri_y + tri_h > h then tri_y = h - tri_h end
    if tri_y < 0 then tri_y = 0 end

    local show_tris = cluster_w <= right_w - 2 * m
    local x
    if show_tris then
        x = left_w + math.floor((right_w - cluster_w) / 2)
    else
        x = left_w + math.floor((right_w - glyph.note_w) / 2)
    end
    local note_x = show_tris and (x + tri_w + gap) or x

    local text_color = tonumber(user_text_color or 'a9a9a9', 16) | alpha
    reaper.JS_LICE_SetFontColor(lice_font, text_color)

    if not (TunerIsLive() and T.has_pitch) then
        local w_txt = gfx.measurestr(T.text)
        local tx = left_w + math.floor((right_w - w_txt) / 2)
        if tx < left_w then tx = left_w end
        reaper.JS_LICE_DrawText(bm, lice_font, T.text, T.text:len(),
            tx, text_y, w, h)
        if show_tris then
            DrawTriangle(bm, dim_color, x, tri_y, tri_w, tri_h, 1, 1)
            DrawTriangle(bm, dim_color, x + cluster_w - tri_w, tri_y,
                tri_w, tri_h, -1, 1)
        end
        return
    end

    -- Note name without the octave, centred inside a fixed width zone so
    -- that it reads as centred while the triangles never move.
    local name = T.text:gsub('%d', '')
    local name_w = gfx.measurestr(name)
    local nx = note_x + math.floor((glyph.note_w - name_w) / 2)
    if nx < left_w then nx = left_w end
    reaper.JS_LICE_DrawText(bm, lice_font, name, name:len(), nx, text_y, w, h)

    if not show_tris then return end

    -- Neutral until the attack has settled, so a string that is actually in
    -- tune never flashes red on the way in.
    local left_color, right_color = dim_color, dim_color
    if T.settled then
        if T.in_tune then
            left_color, right_color = tune_color, tune_color
        elseif T.disp < 0 then
            left_color = arrow_color
        else
            right_color = arrow_color
        end
    end

    DrawTriangle(bm, left_color, x, tri_y, tri_w, tri_h, 1, arrow_alpha)
    DrawTriangle(bm, right_color, x + cluster_w - tri_w, tri_y, tri_w, tri_h,
        -1, arrow_alpha)
end

local LoadCursor = reaper.JS_Mouse_LoadCursor
local normal_cursor = LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = LoadCursor(32644)
local vert_resize_cursor = LoadCursor(32645)
local move_cursor = LoadCursor(32646)

local Intercept = reaper.JS_WindowMessage_Intercept
local Release = reaper.JS_WindowMessage_Release
local Peek = reaper.JS_WindowMessage_Peek

local is_edit_mode = ExtLoad('is_edit_mode', true)

local prev_cursor = normal_cursor
local is_intercept = false

local intercepts = {
    {timestamp = 0, passthrough = false, message = 'WM_SETCURSOR'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_MOUSEWHEEL'},
}

function SetCursor(cursor)
    if not is_intercept then return end
    reaper.JS_Mouse_SetCursor(cursor)
    prev_cursor = cursor
end

function StartIntercepts()
    if is_intercept then return end
    is_intercept = true
    local _, intercept_str = reaper.JS_WindowMessage_ListIntercepts(window_hwnd)
    local blocked_messages = {}
    for entry in (intercept_str .. ','):gmatch('(.-),') do
        local blocked_message = entry:match('(.-):block')
        if blocked_message then blocked_messages[blocked_message] = true end
    end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        if blocked_messages[msg] then
            is_intercept = false
            return
        end
    end
    for _, intercept in ipairs(intercepts) do
        Intercept(window_hwnd, intercept.message, intercept.passthrough)
    end
end

function EndIntercepts()
    if not is_intercept then return end
    if prev_cursor ~= normal_cursor then
        SetCursor(normal_cursor)
    end
    for _, intercept in ipairs(intercepts) do
        Release(window_hwnd, intercept.message)
        intercept.timestamp = 0
    end
    is_intercept = false
    prev_cursor = -1
end

function SetEditMode(mode)
    is_edit_mode = mode
    ExtSave('is_edit_mode', mode)
end


function PeekIntercepts(m_x, m_y)
    if not is_intercept then return end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        local ret, _, time, _, wph = Peek(window_hwnd, msg)

        if ret and time ~= intercept.timestamp then
            intercept.timestamp = time

            if msg == 'WM_LBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_left_click = true
                if is_edit_mode then
                    drag_x = m_x
                    drag_y = m_y
                end
            end

            if msg == 'WM_LBUTTONUP' then
                if not is_left_click then return end

                local all_mods_pressed = reaper.JS_Mouse_GetState(28) == 28
                if all_mods_pressed then
                    PrintIni()
                    return
                end

                -- Ctrl+click prints the detector status to the console.
                -- Kept out of the menu on purpose so it always works.
                if reaper.JS_Mouse_GetState(4) == 4 then
                    ShowTunerStatus()
                    return
                end

                -- Alt+click resets the A4 reference to 440 Hz
                if reaper.JS_Mouse_GetState(16) == 16 then
                    T.a4 = 440
                    reaper.SetExtState(extname, 'a4_ref', T.a4, true)
                    is_redraw = true
                    return
                end

                if resize_flags == 0 or
                    math.min(box_w, box_h) < min_box_size * 1.5 then
                    -- The tuning fork is the on/off button; clicking the
                    -- readout opens the full size window instead. With the
                    -- icon hidden there is nothing else to click, so the
                    -- box keeps toggling.
                    if snap_w > 0 and m_x - box_x < snap_w then
                        ToggleTuner()
                    elseif snap_w > 0 then
                        OpenBigTuner()
                    else
                        ToggleTuner()
                    end
                end
            end

            if msg == 'WM_RBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_right_click = true
            end

            if msg == 'WM_RBUTTONUP' then
                if not is_right_click then return end
                ShowRightClickMenu()
            end

            -- The wheel is deliberately NOT bound to anything. It used to
            -- nudge the reference pitch, which meant a stray scroll over the
            -- transport left people tuning to 442 Hz with nothing on screen
            -- saying so. A4 is a thing you set once, from the menu.
        end
    end
end

-- ---------------------------------------------------------------------------
-- The right click menu
--
-- Built as nested submenus, the way Gridbox does it, and rendered by
-- Gridbox's CreateMenuRecursive / ReturnMenuRecursive (see ShowMenu). A
-- submenu is simply an entry that is itself a list with a title.
--
-- Every title goes through Add(), which strips '|': a device or theme name
-- containing one would insert a phantom field and shift every action after
-- it. menus_test.lua walks the built tree and fires every entry, so the
-- index accounting is verified rather than assumed.
-- ---------------------------------------------------------------------------

function NewMenu(title)
    local menu = {title = title and tostring(title):gsub('|', ' ') or nil}

    function menu.Add(entry_title, on_return, is_checked, is_grayed)
        menu[#menu + 1] = {title = tostring(entry_title):gsub('|', ' '),
            OnReturn = on_return, is_checked = is_checked,
            is_grayed = is_grayed}
        return menu[#menu]
    end

    function menu.Separator()
        menu[#menu + 1] = {separator = true}
    end

    -- Adds a submenu and returns it, so the caller can fill it in.
    function menu.Sub(sub_title)
        local sub = NewMenu(sub_title)
        menu[#menu + 1] = sub
        return sub
    end

    return menu
end

-- ------------------------------------------------------------------ input --
function BuildInputMenu(m)
    local num_inputs = reaper.GetNumAudioInputs()
    if num_inputs == 0 then
        m.Add('No audio inputs found', nil, false, true)
        return
    end
    for i = 0, num_inputs - 1 do
        local name = reaper.GetInputChannelName(i)
        if not name or name == '' then name = tostring(i + 1) end
        m.Add(('Input %d: %s'):format(i + 1, name),
            function() SetTunerInput(i) end, T.input == i)
    end
    for i = 0, num_inputs - 2, 2 do
        m.Add(('Input %d/%d (stereo)'):format(i + 1, i + 2),
            function() SetTunerInput(1024 + i) end, T.input == 1024 + i)
    end
end

-- ------------------------------------------------------------- appearance --
function BuildAppearanceMenu(m)
    m.Add('Size and position...', SetCustomSize)
    m.Add('Font...', SetCustomFont)
    m.Add('Icon size...', SetCustomSnapSize)
    m.Add('Corners...', SetCustomCornerRadius)
    m.Add('Colors...', SetCustomColors)

    m.Separator()

    m.Add('Show on/off icon (when there is room)', function()
        hide_snap = not hide_snap
        reaper.SetExtState(extname, 'hide_snap', hide_snap and 1 or 0, true)
        is_redraw = true
    end, not hide_snap)

    -- These do not move the box. They choose which edge the saved position
    -- is measured from, so the box stays put when the transport is resized.
    local anchor = m.Sub('Keep distance from')
    local curr = GetAttachMode()
    local function Anchor(title, mode)
        anchor.Add(title, function()
            SetAttachMode(mode)
            UpdateAttachPosition()
            SaveThemeSettings(prev_color_theme)
        end, curr == mode)
    end
    Anchor('Left status edge', 3)
    Anchor('Right status edge', 4)
    Anchor('Left window edge', 1)
    Anchor('Right window edge', 2)

    m.Separator()

    -- Appearance saved for other themes
    local curr_theme_key = GetThemeKey(prev_color_theme)
    local theme_settings = ExtLoad('theme_settings', {})
    local other_themes = {}
    for theme_key in pairs(theme_settings) do
        if theme_key ~= curr_theme_key then
            other_themes[#other_themes + 1] = theme_key
        end
    end
    table.sort(other_themes)

    if #other_themes > 0 then
        local copy = m.Sub('Copy from another theme')
        for _, theme_key in ipairs(other_themes) do
            local label = theme_key:match('([^/\\]+)$') or theme_key
            if not GetThemeFromKey(theme_key) then
                label = label .. ' (not found)'
            end
            copy.Add(label, function()
                if reaper.JS_Mouse_GetState(8) == 8 then
                    local msg = 'Permanently delete the saved appearance for \z
                        this theme?\n\n%s'
                    if reaper.MB(msg:format(theme_key), 'Warning', 1) == 1 then
                        SaveThemeSettings(prev_color_theme)
                        theme_settings[theme_key] = nil
                        ExtSave('theme_settings', theme_settings)
                        prev_color_theme = nil
                    end
                    return
                end
                local ret = reaper.MB('Also copy size and position?',
                    'Settings', 3)
                if ret >= 6 then
                    LoadThemeSettings(theme_key .. '.ReaperTheme', ret ~= 6)
                    SaveThemeSettings(prev_color_theme)
                    prev_color_theme = nil
                end
            end)
        end
    end

    m.Add('Export appearance for a theme (console)', PrintIni)

    m.Add('Reset appearance for this theme', function()
        local msg = 'This will clear all customizations you made for the \z
            active theme.\n\nProceed?'
        if reaper.MB(msg, 'Warning', 4) ~= 6 then return end
        local settings = ExtLoad('theme_settings', {})
        settings[GetThemeKey(prev_color_theme)] = nil
        ExtSave('theme_settings', settings)
        prev_color_theme = nil
        if attach_window_title then
            if reaper.MB(('Move %s back to transport?'):format(box_name),
                box_name, 4) == 6 then
                SaveAttachedWindow(nil)
                EndIntercepts()
                window_hwnd = nil
                prev_top_window_cnt = nil
            end
        end
    end)
end

-- --------------------------------------------------------------- advanced --
function BuildAdvancedMenu(m)
    m.Add(('Noise gate: %.0f dB'):format(20 * math.log(T.gate, 10)), function()
        local db = ('%.0f'):format(20 * math.log(T.gate, 10))
        local ret, input = reaper.GetUserInputs('Noise gate', 1,
            'dBFS (lower = more sensitive):,extrawidth=40', db)
        if not ret then return end
        local val = tonumber(input)
        if not val then return end
        SetTunerGate(10 ^ (math.max(-90, math.min(-10, val)) / 20))
    end)

    m.Add('Detector status  (or ctrl+click the box)', ShowTunerStatus)

    m.Add('Reinstall detector JSFX', function()
        -- Only ever delete the copy this script wrote. If ReaPack installed
        -- one, that file belongs to ReaPack and reinstalling it is its job,
        -- so say so instead of silently doing nothing.
        DeleteFile(GetJSFXPath())
        if FindInstalledJSFX() then
            reaper.MB('The detector was installed by ReaPack, so it is kept \z
                up to date with the script itself.\n\nTo replace it, \z
                reinstall TunerBox from ReaPack.', box_name, 0)
            return
        end
        if InstallJSFX() then
            if T.on then
                SetTunerEnabled(false)
                SetTunerEnabled(true)
            end
            reaper.MB('Detector JSFX reinstalled.', box_name, 0)
        else
            reaper.MB(T.err or 'Failed', box_name, 0)
            T.err = nil
        end
    end)

    m.Separator()

    if is_windows then
        m.Add(('Anti-flickering: %s FPS'):format(comp_fps), function()
            local ret, input = reaper.GetUserInputs(
                'Limit underlying window frame rate', 1,
                'FPS (0 = no limit):', comp_fps)
            if not ret then return end
            comp_fps = math.max(0, tonumber(input) or 30)
            comp_delay = comp_fps == 0 and 0 or 1 / comp_fps
            reaper.SetExtState(extname, 'comp_fps', comp_fps, true)
            is_resize = true
        end)
    end
end

-- ---------------------------------------------------------------- top level
function BuildRightClickMenu()
    local m = NewMenu()

    m.Add(T.on and (T.parked and 'Bring the tuner to this project tab'
        or 'Turn tuner off') or 'Turn tuner on', ToggleTuner, TunerIsLive())

    m.Add('Open big tuner', OpenBigTuner)

    m.Add(('Reference pitch: A4 = %g Hz'):format(T.a4), function()
        local ret, input = reaper.GetUserInputs('Reference pitch', 1,
            'A4 in Hz:', T.a4)
        if not ret then return end
        SetReferencePitch(tonumber(input))
    end)

    m.Separator()

    BuildInputMenu(m.Sub('Input'))
    BuildAppearanceMenu(m.Sub('Appearance'))
    BuildAdvancedMenu(m.Sub('Advanced'))

    m.Separator()

    m.Add('Lock position', function() SetEditMode(not is_edit_mode) end,
        not is_edit_mode)

    m.Add('Run script on startup', function()
        SetStartupHookEnabled(not IsStartupHookEnabled(),
            'Start script: TunerBox', 'tuner_box_cmd_name')
    end, IsStartupHookEnabled(nil, true))

    return m
end

function ShowRightClickMenu()
    ShowMenu(BuildRightClickMenu())
end

-- ---------------------------------------------------------------------------
-- Menu building
--
-- This uses Gridbox's own CreateMenuRecursive / ReturnMenuRecursive, which
-- have been in the field long enough to have every gfx.showmenu counting
-- quirk shaken out of them. The rules they encode:
--
--   * a submenu is an entry that is itself an array (#entry > 0) with a title
--   * gfx.showmenu's returned index counts only entries that HAVE a title
--     and are not submenu headers, walking submenus in place
--   * separators are entries with separator = true and no title, and are
--     not counted
--
-- Anything that builds a menu here goes through NewMenu below, so a '|' in
-- a device or theme name can never insert a phantom field.
-- ---------------------------------------------------------------------------

function ShowMenu(menu)
    SetCursor(normal_cursor)

    local focus_hwnd = reaper.JS_Window_GetFocus()
    -- Open gfx window
    gfx.clear = GetThemeColor('col_main_bg2')
    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local window_x, window_y = ClientToScreen(window_hwnd, 0, 0)
    local m = Scale(4, measure_scale)
    gfx.init('TunerBox Menu', Scale(24, measure_scale), 0, 0, window_x + m,
        window_y + m)

    -- Open menu at bottom left corner
    local menu_x, menu_y = ClientToScreen(window_hwnd, box_x, box_y + box_h)
    gfx.x, gfx.y = gfx.screentoclient(menu_x, menu_y)

    -- Hide gfx window
    local gfx_hwnd = reaper.JS_Window_Find('TunerBox Menu', true)
    reaper.JS_Window_SetOpacity(gfx_hwnd, 'ALPHA', 0)

    if is_linux then
        reaper.JS_Window_SetStyle(gfx_hwnd, 'POPUP')
    else
        reaper.JS_Window_Show(gfx_hwnd, 'HIDE')
        if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    end

    -- Show menu
    local ret = gfx.showmenu(CreateMenuRecursive(menu))
    gfx.quit()

    if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    if ret > 0 then ReturnMenuRecursive(menu, ret) end

    -- Make sure that user can click box to close menu
    menu_time = reaper.time_precise()
    is_left_click = false
    is_right_click = false
    drag_x = nil
end

function GetStatusWindowClientRect()
    -- Get status window coordinates
    local status_hwnd = reaper.JS_Window_FindChildByID(window_hwnd, 1010)
    if not status_hwnd then return 0, 0, 0, window_h or 0 end
    local ok, st_l, st_t, st_r, st_b = reaper.JS_Window_GetRect(status_hwnd)
    if not ok or not st_l then return 0, 0, 0, window_h or 0 end
    st_l, st_t = reaper.JS_Window_ScreenToClient(window_hwnd, st_l, st_t)
    st_r, st_b = reaper.JS_Window_ScreenToClient(window_hwnd, st_r, st_b)

    -- Note: Window can be out of transport bounds
    st_l = math.max(st_l, 0)
    st_t = math.max(st_t, 0)
    st_r = math.min(st_r, window_w)
    st_b = math.min(st_b, window_h)

    return st_l, st_t, st_r, st_b
end

function SetBoxCoords(x, y, w, h)
    if w == 0 or h == 0 then return end
    local has_pos_changed = x and x ~= box_x or y and y ~= box_y
    local has_size_changed = w and w ~= box_w or h and h ~= box_h
    if not has_pos_changed and not has_size_changed then return end

    if has_pos_changed then is_redraw = true end
    if has_size_changed then is_resize = true end

    -- Redraw previous area
    InvalidateBoxRect()

    box_x, box_y, box_w, box_h = x or box_x, y or box_y, w or box_w, h or box_h

    -- Redraw new area
    InvalidateBoxRect()

    if not is_resize then
        -- Change bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap, 0, 0,
            GetBitmapSize())
    end
end

function UpdateAttachPosition()
    local mode = GetAttachMode()
    if not box_x or not window_w then return end
    local new_x
    if mode == 1 then new_x = box_x end
    if mode == 2 then new_x = box_x - window_w end
    if mode == 3 then
        local st_l = GetStatusWindowClientRect()
        new_x = box_x - st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_x = box_x - st_r
    end
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if not attach_window_title and is_centered then
        attach_center_x = new_x
    else
        attach_x = new_x
    end
end

function GetAttachMode()
    local mode = attach_mode or attach_center_mode
    if attach_window_title then
        -- Note: Status window options are only valid when attached to transport
        if mode and mode > 2 then mode = mode - 2 end
    else
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then mode = attach_center_mode or attach_mode end
    end
    return mode
end

function SetAttachMode(mode)
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if attach_window_title or not is_centered then
        attach_mode = mode
    else
        attach_center_mode = mode
    end
end

function GetAttachPosition()
    local x = attach_x or attach_center_x
    if not x then return end
    if not attach_window_title then
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then x = attach_center_x or attach_x end
    end

    local mode = GetAttachMode()
    local new_box_x
    if mode == 1 then
        new_box_x = x
    end
    if mode == 2 then
        new_box_x = x + window_w
    end
    if mode == 3 or mode == 4 then
        local st_l = GetStatusWindowClientRect()
        new_box_x = x + st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_box_x = x + st_r
    end
    return new_box_x
end

function EnsureBoxVisible()
    -- Ensure position/size is within bounds
    if window_w == 0 or window_h == 0 then return end
    local w = math.max(min_box_size, math.min(box_w, window_w))
    local h = math.max(min_box_size, math.min(box_h, window_h))

    local x = math.max(0, math.min(window_w - w, box_x))
    local y = math.max(0, math.min(window_h - h, box_y))

    if attach_window_title then
        SetBoxCoords(x, y, w, h)
        return
    end

    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()

    local st_x = st_l
    local st_y = st_t
    local st_w = st_r - st_l
    local st_h = math.abs(st_b - st_t)

    -- Check if bitmap overlaps or contains status window
    local is_left = x + w < st_x
    local is_right = x > st_x + st_w
    local is_above = y + h < st_y
    local is_below = y > st_y + st_h

    local is_overlap = not (is_left or is_right or is_above or is_below)
    local is_contained = x > st_l and x < st_r and y > st_t and y < st_b

    if is_overlap or is_contained then
        -- Move bitmap to not overlap with status window
        local space_l = st_l
        local space_r = window_w - st_r
        local space_t = st_t
        local space_b = window_h - st_b

        local new_l_x = st_l - w
        local new_r_x = st_r
        local new_t_y = st_t - h
        local new_b_y = st_b

        local move_x = 0
        local move_y = 0

        if space_l >= w or space_r >= w then
            if space_l >= w and space_r >= w then
                -- Space on both sides, move to closest position
                move_x = x - new_l_x < new_r_x - x and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_x = space_r > space_l and 1 or -1
            end
        elseif space_t >= h or space_b >= h then
            if space_t >= h and space_b >= h then
                -- Space on both sides, move to closest position
                move_y = y - new_t_y < new_b_y - y and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_y = space_b > space_t and 1 or -1
            end
        else
            -- Check if more vertical or horizontal space, move accordingly
            if math.max(space_l, space_r) > math.max(space_t, space_b) then
                move_x = space_r > space_l and 1 or -1
            else
                move_y = space_b > space_t and 1 or -1
            end
        end

        if move_x == -1 then
            -- Move left
            x = new_l_x
            w = math.min(w, space_l)
        end
        if move_x == 1 then
            -- Move right
            x = new_r_x
            w = math.min(w, space_r)
        end
        if move_y == -1 then
            -- Move top
            y = new_t_y
            h = math.min(h, space_t)
        end
        if move_y == 1 then
            -- Move bottom
            y = new_b_y
            h = math.min(h, space_b)
        end

        -- Ensure position/size is within bounds after move
        w = math.max(min_box_size, math.min(w, window_w))
        h = math.max(min_box_size, math.min(h, window_h))

        x = math.max(0, math.min(window_w - w, x))
        y = math.max(0, math.min(window_h - h, y))
    end

    SetBoxCoords(x, y, w, h)
end

function FindInitialPosition()
    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()
    local st_y = st_t
    local st_h = math.abs(st_b - st_t)

    -- Set initial position that matches status window
    box_x = 0
    box_y = st_y
    box_w = st_h * 7 // 2
    box_h = st_h

    -- Add small vertical margin if status window takes up full transport height
    if st_h >= window_h - Scale(4, measure_scale) then
        box_y = box_y + Scale(2, measure_scale)
        box_h = box_h - Scale(4, measure_scale)
    end

    -- Now we'll use GetThingFromPoint to get empty transport areas on x axis
    local st_mid_y = st_y + box_h // 2
    local empty_areas = {}

    local size = 0
    local sel_cnt = 0
    local bpm_x

    local function AddEmptyArea(x, y, align)
        local _, thing = reaper.GetThingFromPoint(x, y)

        if thing == 'trans' then
            -- Empty transport area, increase size
            size = size + 1
        else
            -- Remember x position of BPM button
            if not bpm_x and type(thing) == 'string' and
                thing:sub(1, 9) == 'trans.bpm' then
                bpm_x = x
            end
            if size > 0 then
                -- Add previous area
                if sel_cnt == 0 and size > min_box_size then
                    local area = {size = size, r = x, align = align}
                    empty_areas[#empty_areas + 1] = area
                end
                size = 0
                sel_cnt = 0
            end

            -- Skip areas to the right of selection (selection textboxes)
            if thing == 'trans.sel' then sel_cnt = sel_cnt + 1 end
        end
    end

    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local x_start, y = ClientToScreen(window_hwnd, 0, st_mid_y)
    local x_end = ClientToScreen(window_hwnd, st_l, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, 1)
    end
    AddEmptyArea(x_end, -1, 1)

    x_start = ClientToScreen(window_hwnd, st_r, st_mid_y)
    x_end = ClientToScreen(window_hwnd, window_w, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, -1)
    end
    AddEmptyArea(x_end, -1, 1)

    local target_area

    if bpm_x then
        local min_bpm_distance
        for _, area in ipairs(empty_areas) do
            -- Check if area is large enough
            if area.size > box_w * 0.7 then
                local area_x = area.r > bpm_x and area.r or area.r - area.size
                local diff = bpm_x - area_x
                local distance = math.abs(diff)
                -- Check distance to bpm window
                if not min_bpm_distance or distance < min_bpm_distance then
                    min_bpm_distance = distance
                    target_area = area
                    target_area.align = area.r > bpm_x and -1 or 1
                end
            end
        end
    end

    if not target_area then
        -- Find largest empty area
        local largest_area_size = 0
        for _, area in ipairs(empty_areas) do
            if area.size > largest_area_size then
                target_area = area
                largest_area_size = area.size
            end
        end
    end

    if not target_area and window_w and box_w then
        box_x = math.max(0, (window_w - box_w) // 2)
    end

    if target_area then
        -- Make bitmap a bit larger if it'll then fully fit empty space
        if target_area.size < box_w * 1.5 then box_w = target_area.size end

        -- Add margin
        local m = box_h // 6
        box_w = math.max(min_box_size, math.min(target_area.size - 2 * m, box_w))

        -- Convert back to client coordinates
        local r = target_area.r
        r = reaper.JS_Window_ScreenToClient(window_hwnd, r, st_mid_y)

        -- Place bitmap (x pos) in empty target area (based on alignment)
        if target_area.align > 0 then
            box_x = math.max(0, r - box_w - m)
            SetAttachMode(box_x < st_r and 3 or 2)
        else
            box_x = math.max(0, r - target_area.size + m)
            SetAttachMode(box_x < st_r and 1 or 4)
        end
    else
        SetAttachMode(box_x < st_r and 1 or 2)
    end
    UpdateAttachPosition()
end

function WaitForAttachedWindow()
    if attach_window_title == 'REAPER Main Window' then return true end
    if attach_window_title == 'Active MIDI editor' then return true end
    return attach_window_wait == attach_window_title
end

function FindAttachedWindow()
    local hwnd
    local window_cnt = 0
    if attach_window_title == 'REAPER Main Window' then
        hwnd = main_hwnd
    elseif attach_window_title == 'Active MIDI editor' then
        hwnd = reaper.MIDIEditor_GetActive()
    else
        local title = attach_window_title or transport_title
        local cnt, list = reaper.JS_Window_ListFind(title, true)
        window_cnt = cnt
        if window_cnt > 0 then
            local first_hwnd
            local main_child
            for addr in (list .. ','):gmatch('(.-),') do
                local handle = reaper.JS_Window_HandleFromAddress(addr)
                first_hwnd = first_hwnd or handle
                -- Check if only one of the windows is child of main window
                -- (for case when running multiple reaper instances)
                if reaper.JS_Window_IsChild(main_hwnd, handle) then
                    if main_child then
                        main_child = nil
                        break
                    else
                        main_child = handle
                    end
                end
            end
            if main_child then
                hwnd = main_child
                window_cnt = 1
            else
                hwnd = first_hwnd
            end
        end

        if hwnd and attach_window_title then
            reaper.SetExtState(extname, 'attach_wait', attach_window_title, true)
        end
    end
    if hwnd and attach_window_child_id then
        local child = reaper.JS_Window_FindChildByID(hwnd, attach_window_child_id)
        if child then
            hwnd = child
        else
            attach_window_child_id = nil
            reaper.SetExtState(extname, 'attach_child_id', '', true)
        end
    end
    return hwnd, window_cnt
end

function SaveAttachedWindow(title, child_id)
    if not title or title == transport_title and not child_id then
        attach_window_title = nil
        attach_window_child_id = nil
        reaper.SetExtState(extname, 'attach_title', '', true)
        reaper.SetExtState(extname, 'attach_child_id', '', true)
        reaper.SetExtState(extname, 'attach_wait', '', true)
        ExtSave('attach_settings', nil)
    else
        attach_window_title = title
        attach_window_child_id = child_id
        reaper.SetExtState(extname, 'attach_title', title, true)
        reaper.SetExtState(extname, 'attach_child_id', child_id or '', true)
        reaper.SetExtState(extname, 'attach_wait', '', true)
    end
end

function Main()
    TunerTick()

    -- Find window
    if not window_hwnd or not reaper.ValidatePtr(window_hwnd, 'HWND*') then
        local time = reaper.time_precise()
        if not prev_time or time > prev_time + 0.5 then
            prev_time = time
            local top_window_cnt = reaper.JS_Window_ArrayAllTop(top_window_array)
            if top_window_cnt ~= prev_top_window_cnt then
                prev_top_window_cnt = top_window_cnt
                window_hwnd = FindAttachedWindow()
                is_resize = true
            end
        end
    elseif attach_window_title and not attach_window_child_id and not drag_x then
        -- Check attached window title changes (e.g. when switching toolbar)
        local curr_title = reaper.JS_Window_GetTitle(window_hwnd)
        if curr_title ~= attach_window_title then
            if bitmap then
                reaper.JS_Composite_Unlink(window_hwnd, bitmap)
                reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
            end
            EndIntercepts()
            InvalidateBoxRect()
            prev_window_hwnd = window_hwnd
            window_hwnd = nil
        end
    end

    if prev_window_hwnd and reaper.ValidatePtr(prev_window_hwnd, 'HWND*') and
        reaper.JS_Window_GetTitle(prev_window_hwnd) == attach_window_title then
        window_hwnd = prev_window_hwnd
        prev_window_hwnd = nil
    end

    -- Go idle if window is not found/visible
    if not window_hwnd or not reaper.JS_Window_IsVisible(window_hwnd) then
        reaper.defer(Main)
        return
    end

    mouse_x, mouse_y = GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(mouse_x, mouse_y)

    do
        local ok, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
        if not ok or type(w) ~= 'number' or type(h) ~= 'number' or
            w <= 0 or h <= 0 then
            window_hwnd = nil
            reaper.defer(Main)
            return
        end
        window_w, window_h = w, h
    end

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        SetThemeIntegration(1)
        prev_color_theme = color_theme
        if not LoadThemeSettings(color_theme) then
            FindInitialPosition()
        end
        EnsureBoxVisible()
        is_resize = true
    end

    -- Detect changes to window size
    if window_w ~= prev_window_w or window_h ~= prev_window_h then
        local prev_measure_scale, prev_draw_scale = measure_scale, draw_scale
        measure_scale, draw_scale = GetTransportScale()

        if draw_scale ~= prev_draw_scale then
            local scale_factor = draw_scale / prev_draw_scale
            user_font_height = Scale(user_font_height, scale_factor)
            user_font_yoffs = Scale(user_font_yoffs, scale_factor)
            user_corner_radius = Scale(user_corner_radius, scale_factor)
            user_snap_size = Scale(user_snap_size, scale_factor)
            is_resize = true
        end
        if measure_scale ~= prev_measure_scale then
            min_box_size = Scale(12, measure_scale)

            local scale_factor = measure_scale / prev_measure_scale
            local new_box_x = Scale(box_x, scale_factor)
            local new_box_y = Scale(box_y, scale_factor)
            local new_box_w = Scale(box_w, scale_factor)
            local new_box_h = Scale(box_h, scale_factor)

            attach_x = Scale(attach_x, scale_factor)
            attach_center_x = Scale(attach_center_x, scale_factor)
            if attach_x or attach_center_x then new_box_x = GetAttachPosition() end

            SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
            EnsureBoxVisible()
            is_resize = true
        end
        if prev_window_w then
            -- Move bitmap based on attached position
            local new_box_x = GetAttachPosition()
            if new_box_x then SetBoxCoords(new_box_x) end
            EnsureBoxVisible()
        end
        prev_window_w = window_w
        prev_window_h = window_h
    end

    -- Detect centered transport toggle
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if is_centered ~= prev_is_centered then
        prev_is_centered = is_centered
        local new_box_x = GetAttachPosition()
        if new_box_x then SetBoxCoords(new_box_x) end
        EnsureBoxVisible()
    end


    local is_snap_hovered = false
    local is_hovered = false

    if hover_hwnd == window_hwnd or drag_x then
        local ScreenToClient = reaper.JS_Window_ScreenToClient
        local m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)
        -- Handle drag move/resize
        if drag_x and (drag_x ~= m_x or drag_y ~= m_y) then
            if resize_flags > 0 then
                if resize_flags & 1 == 1 then
                    local box_r = box_x + box_w
                    local new_box_w = math.max(min_box_size, box_r - m_x)
                    local new_box_x = box_r - new_box_w
                    SetBoxCoords(new_box_x, nil, new_box_w, nil)
                end
                if resize_flags & 2 == 2 then
                    local box_b = box_y + box_h
                    local new_box_h = math.max(min_box_size, box_b - m_y)
                    local new_box_y = box_b - new_box_h
                    SetBoxCoords(nil, new_box_y, nil, new_box_h)
                end
                if resize_flags & 4 == 4 then
                    local new_box_w = math.max(min_box_size, m_x - box_x)
                    SetBoxCoords(nil, nil, new_box_w, nil)
                end
                if resize_flags & 8 == 8 then
                    local new_box_h = math.max(min_box_size, m_y - box_y)
                    SetBoxCoords(nil, nil, nil, new_box_h)
                end
                is_resize = true
            else
                prev_box_w = prev_box_w or box_w
                prev_box_h = prev_box_h or box_h
                prev_box_x = prev_box_x or box_x
                prev_box_y = prev_box_y or box_y

                -- Move box to hovered window
                if hover_hwnd and hover_hwnd ~= window_hwnd then
                    prev_attach_hwnd = prev_attach_hwnd or window_hwnd
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
                    -- Redraw previous area
                    window_hwnd = hover_hwnd
                    reaper.JS_Window_SetFocus(hover_hwnd)

                    -- Get relative position to bitmap top left corner
                    local drag_x_diff = drag_x - box_x
                    local drag_y_diff = drag_y - box_y

                    -- Get new mouse window position
                    m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)

                    -- Set bitmap coordinates with relative position
                    -- Note: Avoid SetBoxCoords as it doesn't allow going out
                    -- of bounds
                    box_x = m_x - drag_x_diff
                    box_y = m_y - drag_y_diff
                    drag_x = box_x + drag_x_diff
                    drag_y = box_y + drag_y_diff

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                else
                    -- Move box inside window
                    local new_box_x = box_x + m_x - drag_x
                    local new_box_y = box_y + m_y - drag_y
                    SetBoxCoords(new_box_x, new_box_y)
                end
                if m_x > 0 and m_y > 0 and m_x < window_w and m_y < window_h then
                    SetCursor(move_cursor)
                    resize_flags = -1
                    resize_cursor = nil
                end
            end
            drag_x = m_x
            drag_y = m_y
            is_left_click = false
        end

        local m = Scale(4, measure_scale)
        is_hovered = m_x > box_x - m and m_y > box_y - m and
            m_x < box_x + box_w + m and m_y < box_y + box_h + m

        if is_hovered and hover_hwnd == window_hwnd then
            StartIntercepts()
            PeekIntercepts(m_x, m_y)
            if is_edit_mode and not drag_x and not swing_drag_x then
                local new_resize = 0
                local cursor = normal_cursor

                local diff_l = math.abs(box_x - m_x)
                local diff_t = math.abs(box_y - m_y)
                local diff_r = math.abs(box_x + box_w - m_x)
                local diff_b = math.abs(box_y + box_h - m_y)

                if diff_l < m then
                    new_resize = 1
                    cursor = horz_resize_cursor
                end

                if diff_t < m then
                    new_resize = 2
                    cursor = vert_resize_cursor
                end

                if diff_r < m then
                    new_resize = 4
                    cursor = horz_resize_cursor
                end

                if diff_b < m then
                    new_resize = 8
                    cursor = vert_resize_cursor
                end

                local d_m = 2 * m

                if diff_l < d_m and diff_t < d_m then
                    new_resize = 3
                    cursor = diag2_resize_cursor
                end

                if diff_t < d_m and diff_r < d_m then
                    new_resize = 6
                    cursor = diag1_resize_cursor
                end

                if diff_r < d_m and diff_b < d_m then
                    new_resize = 12
                    cursor = diag2_resize_cursor
                end

                if diff_b < d_m and diff_l < d_m then
                    new_resize = 9
                    cursor = diag1_resize_cursor
                end

                if resize_flags ~= new_resize then
                    resize_flags = new_resize
                    resize_cursor = cursor
                    is_redraw = true
                end
            end
            if not swing_drag_x and snap_w > 0 and m_x - box_x < snap_w then
                is_snap_hovered = true
            end
            if resize_cursor then
                SetCursor(resize_cursor)
            elseif not drag_x then
                SetCursor(normal_cursor)
            end

            if is_snap_hovered then
                if m_x == prev_hover_m_x and m_y == prev_hover_m_y then
                    hover_cnt = hover_cnt + 1
                else
                    hover_cnt = 0
                end
                prev_hover_m_x, prev_hover_m_y = m_x, m_y

                if hover_cnt > 11 then
                    local tooltip = TunerTooltip()
                    if tooltip ~= prev_tooltip then
                        prev_tooltip = tooltip
                        local offs = Scale(17, measure_scale)
                        reaper.TrackCtl_SetToolTip(tooltip, mouse_x + offs,
                            mouse_y + offs, true)
                    end
                elseif prev_tooltip then
                    prev_tooltip = nil
                end
            end
        else
            is_left_click = false
            is_right_click = false
            if resize_flags > 0 and not drag_x then
                resize_flags = 0
                resize_cursor = nil
                is_redraw = true
            end
            EndIntercepts()
        end

        -- Release drags / left clicks / right clicks
        if drag_x and reaper.JS_Mouse_GetState(3) == 0 then
            -- Check if new attached window is valid
            if drag_x and prev_attach_hwnd and window_hwnd ~= prev_attach_hwnd then
                local is_reset = false
                local target_hwnd = window_hwnd
                local title = reaper.JS_Window_GetTitle(target_hwnd)

                local child_id = nil
                -- If window has no title, check if window has ID and parent has title
                if title == '' then
                    local parent_hwnd = reaper.JS_Window_GetParent(target_hwnd)
                    if reaper.ValidatePtr(parent_hwnd, 'HWND*') then
                        local id = reaper.JS_Window_GetLong(target_hwnd, 'ID')
                        id = tonumber(id)
                        if id and id > 0 then
                            child_id = id
                            title = reaper.JS_Window_GetTitle(parent_hwnd)
                            target_hwnd = parent_hwnd
                        end
                    end
                end

                -- Do not allow windows with empty titles
                if title == '' then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Window does not have a title.'
                    reaper.MB(msg:format(box_name), 'Notice', 0)
                    is_reset = true
                end

                -- Do not allow titles with newline characters
                if not is_reset and title:match('\n') then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Invalid window title:\n\nTITLE: %s'
                    reaper.MB(msg:format(box_name, title), 'Notice', 0)
                end

                local found_hwnd
                if not is_reset then
                    -- Check if new attached window can be found via Window_Find
                    local window_cnt, list = reaper.JS_Window_ListFind(title, 1)
                    if window_cnt > 1 then
                        local msg = 'Can not attach %s to this window. \z
                            %d windows have the same title!\n\n\z
                            TITLE: %s\n\nIf this window is a toolbar, make sure \z
                            that it is only open once (not in toolbar docker) and \z
                            consider giving it a unique title.'
                        msg = msg:format(box_name, window_cnt, title)
                        reaper.MB(msg, 'Notice', 0)
                        is_reset = true
                    elseif window_cnt == 0 then
                        local msg = 'Can not attach %s to this window.\z
                            \n\nCould not find window by title.\n\nTITLE: %s'
                        reaper.MB(msg:format(box_name, title), 'Notice', 0)
                        is_reset = true
                    else
                        found_hwnd = reaper.JS_Window_HandleFromAddress(list)
                        if found_hwnd ~= target_hwnd then
                            local msg = 'Can not attach %s to this \z
                                window.\n\nHandle missmatch'
                            reaper.MB(msg:format(box_name), 'Notice', 0)
                            is_reset = true
                        end
                    end
                end

                if not is_reset then
                    is_reset = true
                    -- Save accessible windows by custom ID instead of title
                    if target_hwnd == main_hwnd then
                        title = 'REAPER Main Window'
                    end
                    if target_hwnd == reaper.MIDIEditor_GetActive() then
                        title = 'Active MIDI editor'
                    end

                    -- Prompt user to confirm new attachment
                    local msg = '%s will be attached to this window:\z
                            \n\nTITLE: %s%s\n\nProceed?'
                    local id_text = ''
                    if child_id then id_text = ('\nID: %d'):format(child_id) end
                    msg = msg:format(box_name, title, id_text)

                    local ret = reaper.MB(msg, 'Notice', 4)
                    if ret == 6 then
                        -- Save info on new attachment for next script startup
                        SaveAttachedWindow(title, child_id)
                        is_reset = false
                    end
                end

                if is_reset then
                    -- Move box back to previous window (pre-drag)
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)

                    window_hwnd = prev_attach_hwnd
                    reaper.JS_Window_SetFocus(prev_attach_hwnd)

                    box_w = prev_box_w
                    box_h = prev_box_h
                    box_x = prev_box_x
                    box_y = prev_box_y

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                end
            end
            EnsureBoxVisible()
            UpdateAttachPosition()
            SaveThemeSettings(color_theme)
            drag_x = nil
            drag_y = nil
            is_redraw = true
            prev_attach_hwnd = nil
            prev_box_w = nil
            prev_box_h = nil
            prev_box_x = nil
            prev_box_y = nil
        end
    else
        EndIntercepts()
    end


    -- (the tuner's periodic work runs at the top of Main, so that it still
    -- happens while the transport window is hidden)

    if is_resize then
        -- Prepare LICE bitmap for drawing
        if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
        if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
        if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end

        local bm_w, bm_h = GetBitmapSize()
        bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
        snap_bitmap = nil
        bg_bitmap = nil

        local font_family = user_font_family or 'Arial'
        -- Binary search to find font size that fits target height
        local default_h = Scale(14, draw_scale)
        local target_h = math.max(math.min(default_h, bm_h), bm_h // 2.5)
        if user_font_height then target_h = math.min(user_font_height, bm_h) end

        local lo, hi, mid = 1, target_h * 2, nil
        font_size = lo
        while lo <= hi do
            mid = math.floor((lo + hi) / 2)
            gfx.setfont(1, font_family, mid)
            local curr_h = math.max(1, select(2, gfx.measurechar(70)))
            if curr_h <= target_h then
                font_size = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        if font_size ~= mid then gfx.setfont(1, font_family, font_size) end
        MeasureGlyphs()

        -- Create LICE font
        if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
        lice_font = reaper.JS_LICE_CreateFont()

        local GDI_CreateFont = reaper.JS_GDI_CreateFont
        local font_weight = user_font_weight or 0
        local gdi = GDI_CreateFont(font_size, font_weight, 0, 0, 0, 0,
            font_family)
        reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
        reaper.JS_GDI_DeleteObject(gdi)

        -- Set bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap,
            0, 0, bm_w, bm_h)
        is_resize = false
        is_redraw = true
    end


    if snap_w > 0 and is_snap_hovered ~= prev_is_snap_hovered then
        prev_is_snap_hovered = is_snap_hovered
        is_redraw = true
    end

    if is_redraw then
        DrawBitmap(bitmap, GetBitmapSize())
        InvalidateBoxRect()
        is_redraw = false
    end

    reaper.defer(Main)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)


function Exit()
    -- the companion toggle action checks this to know we are here
    reaper.SetExtState(extname, 'alive', '', false)
    reaper.SetExtState(extname, 'is_live', '0', false)
    reaper.SetExtState(extname, 'request', '', false)
    SetToggleActionState(0)

    SetThemeIntegration(0)
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)

    -- Removal is by tag, so nothing the user made is ever deleted.
    RemoveAllTunerTracks()

    if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
    if snap_bitmap then reaper.JS_LICE_DestroyBitmap(snap_bitmap) end
    if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
    if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
    if reaper.ValidatePtr(window_hwnd, 'HWND*') then
        reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
        InvalidateBoxRect()
        EndIntercepts()
    end
end

if attach_window_title then
    local is_reset = false
    -- Give option to move box back to transport when attached window
    -- is not found upon script startup (or when multiple windows are found)
    local window_cnt = 0
    window_hwnd, window_cnt = FindAttachedWindow()

    if window_cnt > 1 then
        local msg = 'Found %d windows with the same title.\n\n\z
            Move %s back to transport?'
        local ret = reaper.MB(msg:format(window_cnt, box_name), box_name, 4)
        is_reset = ret == 6
        ExtSave('start_cnt', nil)
    end

    if not window_hwnd and not WaitForAttachedWindow() then
        local msg = 'Could not find window.\n\nTITLE: %s\n\nWait for \z
            window to open?'
        local ret = reaper.MB(msg:format(attach_window_title), box_name, 4)
        is_reset = ret ~= 6
        if is_reset then
            msg = 'Moved %s back to transport'
            reaper.MB(msg:format(box_name), box_name, 0)
        end
        ExtSave('start_cnt', nil)
    end

    -- Give option to move box back to transport when user quickly toggles
    -- the script 3 times in a row (in 3 seconds)
    local curr_time = reaper.time_precise()
    local start_cnt = tonumber(ExtLoad('start_cnt', 1)) or 1
    local start_time = tonumber(ExtLoad('start_time', curr_time)) or curr_time

    -- Check if more than 3 seconds have passed
    if math.abs(start_time - curr_time) > 3 then
        start_cnt = 1
        ExtSave('start_cnt', nil)
        ExtSave('start_time', nil)
    else
        start_cnt = start_cnt + 1
        -- Check if script has started 3 times
        if start_cnt > 3 then
            start_cnt = nil
            curr_time = nil
            local msg = 'Move %s back to transport?'
            local ret = reaper.MB(msg:format(box_name), box_name, 4)
            is_reset = ret == 6
        end
        ExtSave('start_cnt', start_cnt)
        ExtSave('start_time', curr_time)
    end

    -- Move box back to transport
    if is_reset then
        SaveAttachedWindow(nil)
        EndIntercepts()
        window_hwnd = nil
        prev_top_window_cnt = nil
    end
end



-- Restore the tuner state from the last session. A fresh install starts
-- OFF on purpose: switching the tuner on inserts a track, which marks the
-- project as modified, and nobody should get a "save changes?" prompt from
-- a script they only just installed and have not used yet.
MigrateAwayFromOwnTrack()
SetTunerEnabled(reaper.GetExtState(extname, 'is_on') == '1')

reaper.atexit(Exit)
reaper.defer(Main)
