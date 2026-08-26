--[[
  @noindex
  Part of Speed Trainer. See Reapertips_Speed Trainer.lua.
]]

-- Speed Trainer companion action: Advance one step.
--
-- Bind this to a key or a MIDI footswitch in REAPER's Action List. It leaves
-- a command for a running Speed Trainer window and returns immediately; it
-- never opens the window by itself.

local EXTNAME = 'RTIPS.SpeedTrainer'
local COMMAND = 'advance'

local heartbeat = reaper.GetExtState(EXTNAME, 'heartbeat')
local stamp = tonumber(heartbeat:match('|([%d%.%-]+)$'))
if not stamp or reaper.time_precise() - stamp >= 3 then
    reaper.MB('Speed Trainer is not running. Open it first, then try again.',
        'Speed Trainer', 0)
    return
end

local serial = tonumber(reaper.GetExtState(EXTNAME, 'cmd_serial')) or 0
serial = serial + 1
reaper.SetExtState(EXTNAME, 'cmd_serial', tostring(serial), false)
reaper.SetExtState(EXTNAME, 'cmd', serial .. '|' .. COMMAND, false)
reaper.defer(function() end)
