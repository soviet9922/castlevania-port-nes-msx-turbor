-- FCEUX Lua probe: the stopwatch. Walks into the hall (as record_hall.lua),
-- waits for zombies, then sets the sub-weapon $15B = 15 with 20 hearts and
-- presses UP + B at frame 1600. Writes PROBE_OUT/ram.bin (2 KB of RAM per
-- frame from FIRST).
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 1500, 2100
local ram = io.open(out .. "/ram.bin", "wb")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 and f < 1500 then pad.right = true end
  if f > 1500 then memory.writebyte(0x45, 64) end
  if f == 1590 then memory.writebyte(0x15B, 15); memory.writebyte(0x71, 20) end
  if f >= 1600 and f <= 1601 then pad.B = true; pad.up = true end
  joypad.set(1, pad)
  emu.frameadvance()
  if f >= FIRST then
    local t = {}
    for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
    ram:write(table.concat(t))
  end
end
ram:close()
os.exit(0)
