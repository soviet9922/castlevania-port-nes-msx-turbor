-- FCEUX Lua probe: the game rules. Walks right through the courtyard and the
-- hall whipping every 20 frames (braziers, candles, zombies), so pickups and
-- kills change the score, hearts, whip level and sub-weapon. Then stops in the
-- hall with the timer set to 2 (frame 2700), so time runs out: the death and
-- the restart. Writes PROBE_OUT/ram.bin (2 KB of RAM per frame) and screenshots.
local out = os.getenv("PROBE_OUT") or "."
local LAST = 4600
local ram = io.open(out .. "/ram.bin", "wb")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 and f < 2600 then
    pad.right = true
    if f % 20 < 2 then pad.B = true end
  end
  if f == 2700 then memory.writebyte(0x43, 0); memory.writebyte(0x42, 2) end
  joypad.set(1, pad)
  emu.frameadvance()
  local t = {}
  for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
  ram:write(table.concat(t))
  if f % 50 == 0 then gui.savescreenshotas(out .. string.format("/shot_%04d.png", f)) end
end
ram:close()
os.exit(0)
