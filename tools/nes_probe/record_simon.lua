-- FCEUX Lua probe: start a game and record Simon doing each basic action.
-- Writes PROBE_OUT/ram.bin (2 KB of CPU RAM per frame, from frame FIRST),
-- PROBE_OUT/inputs.txt (frame and buttons) and PPU snapshots.
local out = os.getenv("PROBE_OUT") or "."
local FIRST, LAST = 640, 1500
local ram = io.open(out .. "/ram.bin", "wb")
local inp = io.open(out .. "/inputs.txt", "w")

-- script: {from, to, buttons}
local script = {
  {100, 104, {start=true}}, {300, 303, {start=true}},
  {760, 880, {right=true}},                 -- walk right
  {900, 902, {A=true}},                     -- jump in place
  {980, 982, {A=true, right=true}},         -- jump forward
  {983, 1040, {right=true}},
  {1060, 1100, {down=true}},                -- crouch
  {1120, 1122, {B=true}},                   -- whip standing
  {1180, 1182, {B=true, down=true}},        -- whip crouching
  {1183, 1220, {down=true}},
  {1240, 1300, {left=true}},                -- walk left
  {1320, 1322, {A=true, left=true}},        -- jump backward
}

local function dump_ppu(tag)
  local f = io.open(out .. "/ppu_" .. tag .. ".bin", "wb")
  for a = 0, 0x3FFF do f:write(string.char(ppu.readbyte(a))) end
  f:close()
end

for f = 1, LAST do
  local pad = {}
  for _, s in ipairs(script) do
    if f >= s[1] and f <= s[2] then
      for k, v in pairs(s[3]) do pad[k] = v end
    end
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
  if f == 750 or f == 1130 then dump_ppu(tostring(f)) end
end
ram:close()
inp:close()
os.exit(0)
