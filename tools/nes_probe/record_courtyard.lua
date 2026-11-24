-- FCEUX Lua probe: walk through the Stage 1 courtyard whipping every brazier.
-- Writes PROBE_OUT/ram.bin (2 KB CPU RAM per frame from FIRST) and inputs.txt.
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 640, 2000
local ram = io.open(out .. "/ram.bin", "wb")
local inp = io.open(out .. "/inputs.txt", "w")
for f = 1, LAST do
  local pad = {}
  if (f >= 100 and f <= 104) or (f >= 300 and f <= 303) then pad.start = true end
  if f >= 700 then
    -- cycle of 60 frames: walk 36 frames, whip on frame 40, wait for it to finish
    local c = (f - 700) % 60
    if c < 36 then pad.right = true end
    if c >= 38 and c <= 40 then pad.B = true end
  end
  joypad.set(1, pad)
  emu.frameadvance()
  if f >= FIRST then
    local t = {}
    for a = 0, 0x7FF do t[#t + 1] = string.char(memory.readbyte(a)) end
    ram:write(table.concat(t))
    local keys = {}
    for k, _ in pairs(pad) do keys[#keys + 1] = k end
    table.sort(keys)
    inp:write(f .. " " .. table.concat(keys, ",") .. "\n")
  end
  if f % 100 == 0 then gui.savescreenshotas(out .. string.format("/shot_%04d.png", f)) end
end
ram:close()
inp:close()
os.exit(0)
