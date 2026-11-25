-- FCEUX Lua probe: the whip levels and the dagger. In the courtyard, standing
-- still: whip level 1 (chain) at frame 720, level 2 (morning star) at 820,
-- then the dagger ($15B = 8, 10 hearts) thrown with UP + B at 920.
-- Writes PROBE_OUT/ram.bin (2 KB of RAM per frame from FIRST).
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 700, 1100
local ram = io.open(out .. "/ram.bin", "wb")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f == 700 then memory.writebyte(0x70, 1) end
  if f == 800 then memory.writebyte(0x70, 2) end
  if f == 900 then memory.writebyte(0x15B, 8); memory.writebyte(0x71, 0x10) end
  if f >= 720 and f <= 721 then pad.B = true end
  if f >= 820 and f <= 821 then pad.B = true end
  if f >= 920 and f <= 921 then pad.B = true; pad.up = true end
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
