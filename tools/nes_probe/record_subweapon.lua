-- FCEUX Lua probe: a sub-weapon thrown in the courtyard. Picking an item up
-- copies its candle code into $15B (see NES_NOTES.md); this sets $15B = SUB
-- (environment variable, default 15) and 10 hearts, then UP + B at frame 720.
-- 15: costs 5 hearts, throws nothing (the stopwatch); 13: the axe; 11: holy
-- water. Writes PROBE_OUT/ram.bin (2 KB of RAM per frame from FIRST).
local out = os.getenv("PROBE_OUT") or "."
local SUB = tonumber(os.getenv("SUB") or "15")
local FIRST, LAST = 700, 900
local ram = io.open(out .. "/ram.bin", "wb")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f == 700 then memory.writebyte(0x15B, SUB); memory.writebyte(0x71, 10) end
  if f >= 720 and f <= 721 then pad.B = true; pad.up = true end
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
