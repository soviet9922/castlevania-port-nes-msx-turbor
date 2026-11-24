-- FCEUX Lua probe: boot Castlevania, start a game, dump PPU state in Stage 1.
-- Output directory comes from the env var PROBE_OUT.
local out = os.getenv("PROBE_OUT") or "."
local log = io.open(out .. "/probe.log", "w")

memory.registerexecute(0xFD2A, function()
  log:write(string.format("frame %d chrset %d\n", emu.framecount(), memory.getregister("a")))
end)

local function dump_ppu(tag)
  local f = io.open(out .. "/ppu_" .. tag .. ".bin", "wb")
  for a = 0, 0x3FFF do f:write(string.char(ppu.readbyte(a))) end
  f:close()
  f = io.open(out .. "/ram_" .. tag .. ".bin", "wb")
  for a = 0, 0x7FF do f:write(string.char(memory.readbyte(a))) end
  f:close()
  gui.savescreenshotas(out .. "/shot_" .. tag .. ".png")
end

local press = {[100]=true,[101]=true,[102]=true,[103]=true,[104]=true,
               [300]=true,[301]=true,[302]=true,[303]=true}
for f = 1, 1500 do
  if press[f] then joypad.set(1, {start=true}) end
  -- walk right a little once in the stage
  if f > 1100 and f < 1300 then joypad.set(1, {right=true}) end
  emu.frameadvance()
  if f == 1000 then dump_ppu("a") end
  if f == 1400 then dump_ppu("b") end
end
log:close()
os.exit(0)
