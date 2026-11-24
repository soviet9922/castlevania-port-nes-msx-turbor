-- FCEUX Lua probe: walk from the courtyard through the gate into the entrance
-- hall and along it. Writes PROBE_OUT/ram.bin (2 KB per frame from FIRST),
-- PROBE_OUT/ppu_<frame>.bin snapshots and screenshots.
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 640, 2600
local ram = io.open(out .. "/ram.bin", "wb")
local function dump_ppu(tag)
  local f = io.open(out .. "/ppu_" .. tag .. ".bin", "wb")
  for a = 0, 0x3FFF do f:write(string.char(ppu.readbyte(a))) end
  f:close()
end
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 then pad.right = true end
  joypad.set(1, pad)
  emu.frameadvance()
  if f >= FIRST then
    local t = {}
    for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
    ram:write(table.concat(t))
  end
  if f % 100 == 0 then
    gui.savescreenshotas(out .. string.format("/shot_%04d.png", f))
    dump_ppu(string.format("%04d", f))
  end
end
ram:close()
os.exit(0)
