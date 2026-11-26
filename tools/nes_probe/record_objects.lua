-- FCEUX Lua probe: every object's id, world x, y and AI state, every frame,
-- from a savestate, with Simon standing still (or a fixed input). Used to
-- compare an enemy's path with the port's (tools/compare_paths.py).
-- Environment:
--   PROBE_OUT  directory for objects_<RUN>.txt
--   RUN        name of this run;  SLOT savestate slot (1-10)
--   FRAMES     frames to record (default 600)
--   INPUT      held buttons, e.g. "left" or "right,B" (default none)
--   INVINCIBLE 1: keep Simon's health topped up (default 1)
-- Output lines: "frame cam simon_x simon_y | slot:id:x:y:state ..."
-- (world x = screen x + camera). Addresses and positions only.
local out = os.getenv("PROBE_OUT") or "."
local run = os.getenv("RUN") or "run"
local slot = tonumber(os.getenv("SLOT") or "1")
local frames = tonumber(os.getenv("FRAMES") or "600")
local inv = (os.getenv("INVINCIBLE") or "1") == "1"
local held = {}
for b in string.gmatch(os.getenv("INPUT") or "", "[^,]+") do held[b] = true end

local st = savestate.object(slot)
savestate.load(st)
local f = io.open(out .. "/objects_" .. run .. ".txt", "w")
for n = 1, frames do
  joypad.set(1, held)
  emu.frameadvance()
  if inv then memory.writebyte(0x45, 64) end
  local cam = memory.readbyte(0x2E) + 256 * memory.readbyte(0x2F)
  local line = string.format("%d %d %d %d |", n, cam,
    memory.readbyte(0x40) + 256 * memory.readbyte(0x41), memory.readbyte(0x3F))
  for i = 1, 22 do
    local id = memory.readbyte(0x434 + i)
    if id ~= 0 then
      local x = memory.readbyte(0x38C + i) + cam
      if memory.readbyte(0x300 + i) % 2 == 1 then
        x = x + (memory.readbyte(0x38C + i) < 128 and 256 or -256)
      end
      line = line .. string.format(" %d:%02X:%d:%d:%d", i, id, x,
        memory.readbyte(0x354 + i), memory.readbyte(0x46C + i))
    end
  end
  f:write(line .. "\n")
end
f:close()
emu.exit()
