-- FCEUX Lua probe: walk through the entrance hall to its exit and into the
-- next stage (same route as record_upper.lua, then the last staircase up
-- to the door at the top right). Run on a
-- ROM copy without the hall's enemy groups. Writes PROBE_OUT/ram.bin
-- (2 KB of RAM per frame from FIRST) and a screenshot every 50 frames.
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 2900, 5200
local ram = io.open(out .. "/ram.bin", "wb")
local step = 1
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 and f < 1500 then pad.right = true end
  if f >= 1500 and memory.readbyte(0x28) == 1 then
    local wx = memory.readbyte(0x40) + 256 * memory.readbyte(0x41)
    local y = memory.readbyte(0x3f)
    if step == 1 then pad.right = true; if wx >= 632 then step = 2 end
    elseif step == 2 then pad.up = true; if y == 128 and memory.readbyte(0x3d) == 0 then step = 3 end
    elseif step == 3 then pad.right = true; if wx >= 726 then step = 4 end
    elseif step == 4 then pad.up = true; if y == 96 and memory.readbyte(0x3d) == 0 then step = 5 end
    elseif step == 5 then pad.right = true; if y == 192 and wx >= 1304 then step = 6 end
    elseif step == 6 then pad.up = true; if y == 96 and memory.readbyte(0x3d) == 0 then step = 7 end
    else pad.right = true end
  elseif f >= 1500 then
    pad.right = true
  end
  joypad.set(1, pad)
  emu.frameadvance()
  if f >= FIRST then
    local t = {}
    for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
    ram:write(table.concat(t))
  end
  if f % 50 == 0 and f >= FIRST then gui.savescreenshotas(out .. string.format("/shot_%04d.png", f)) end
end
ram:close()
os.exit(0)
