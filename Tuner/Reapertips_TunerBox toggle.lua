--[[
  @noindex
  Part of TunerBox. See Reapertips_TunerBox.lua.
]]

-- ---------------------------------------------------------------------------
-- Toggle the TunerBox tuner on and off.
--
-- Bind this to a key. It does NOT start or stop the TunerBox script itself:
-- the box stays where it is in the transport, this only switches the tuner
-- between listening and standby, which is what you want while a guitar is
-- in your hands.
--
-- It works by leaving a request in an ExtState. TunerBox picks it up on its
-- next pass, within about 30 ms, and acts on it there - which matters,
-- because turning the tuner on has to happen inside the script that owns
-- the track, not in this one shot action.
-- ---------------------------------------------------------------------------

local extname = 'RTIPS.TunerBox'

-- 'toggle' | 'on' | 'off'. Change this in a copy of the file if you want a
-- dedicated "tuner on" or "tuner off" key instead of a single toggle.
local ACTION = 'toggle'

local function IsRunning()
    -- TunerBox stamps the clock on every pass. If the stamp is stale the
    -- script is not running and there is nobody to service the request.
    local beat = tonumber(reaper.GetExtState(extname, 'alive'))
    if not beat then return false end
    return reaper.time_precise() - beat < 2
end

if not IsRunning() then
    local msg = 'TunerBox is not running.\n\nStart it first (Actions list: \z
        "Script: Reapertips_TunerBox.lua"), or turn on "Run script on \z
        startup" in its right click menu.'
    reaper.MB(msg, 'TunerBox', 0)
    return
end

reaper.SetExtState(extname, 'request', ACTION, false)

-- Tell TunerBox where this action lives so it can keep the toolbar button
-- in sync from now on. Without this the button would latch: pressing it
-- lights it, but switching the tuner off any other way (the fork, the menu,
-- quitting the script) would leave it lit forever.
local _, _, sec, cmd = reaper.get_action_context()
if sec and cmd and cmd ~= 0 then
    reaper.SetExtState(extname, 'toggle_action', sec .. ' ' .. cmd, false)
    -- reflect it immediately rather than waiting for the next defer pass
    local is_on = reaper.GetExtState(extname, 'is_live') == '1'
    local will_be = ACTION == 'on' or (ACTION == 'toggle' and not is_on)
    reaper.SetToggleCommandState(sec, cmd, will_be and 1 or 0)
    reaper.RefreshToolbar2(sec, cmd)
end
