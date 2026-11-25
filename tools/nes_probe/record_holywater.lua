-- FCEUX Lua probe: holy water thrown on the hall's floor with nothing in the
-- way (run on a ROM copy without the hall's zombies). Walks into the hall,
-- sets the sub-weapon $15B = 11 (holy water) and 10 hearts, UP + B at 1560.
-- Writes PROBE_OUT/ram.bin (2 KB of RAM per frame from FIRST).
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 1550, 1760
local ram = io.open(out .. "/ram.bin", "wb")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 and f < 1500 then pad.right = true end
  if f == 1550 then memory.writebyte(0x15B, 11); memory.writebyte(0x71, 10) end
  if f >= 1560 and f <= 1561 then pad.B = true; pad.up = true end
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
