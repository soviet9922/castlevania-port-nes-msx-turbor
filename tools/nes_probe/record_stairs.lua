-- FCEUX Lua probe: enter the hall, walk to the first staircase and climb it.
-- Run it on a copy of the ROM with the hall's enemy groups zeroed (see
-- docs/NES_NOTES.md), otherwise zombies keep knocking Simon back.
-- env PROBE_OUT, UP_AT (Simon world x where UP replaces RIGHT, default 600)
local out = os.getenv("PROBE_OUT") or "."
local up_at = tonumber(os.getenv("UP_AT") or "600")
local FIRST, LAST = 1450, 2400
local ram = io.open(out .. "/ram.bin", "wb")
local phase = "walk"
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 and f < 1500 then pad.right = true end
  if f >= 1500 then
    local wx = memory.readbyte(0x40) + 256 * memory.readbyte(0x41)
    if memory.readbyte(0x28) == 1 and wx >= up_at then phase = "climb" end
    if phase == "walk" then
      pad.right = true
    else
      pad.up = true
    end
  end
  joypad.set(1, pad)
  emu.frameadvance()
  if f >= FIRST then
    local t = {}
    for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
    ram:write(table.concat(t))
  end
  if f % 100 == 0 then gui.savescreenshotas(out .. string.format("/shot_%04d.png", f)) end
end
ram:close()
os.exit(0)
