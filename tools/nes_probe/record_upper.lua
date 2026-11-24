-- FCEUX Lua probe: hall -> first staircase -> second staircase -> along the
-- upper floor, to record bats and panthers. Run on a ROM copy without the
-- hall's zombie groups (see docs/NES_NOTES.md). Writes PROBE_OUT/ram.bin.
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 1450, 3400
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
    else pad.right = true; if f % 30 < 3 then pad.B = true end end
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
