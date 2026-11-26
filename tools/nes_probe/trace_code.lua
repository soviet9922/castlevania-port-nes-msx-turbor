-- FCEUX Lua probe: code/data coverage for the disassembler (tools/nes_disasm.py).
-- Logs every executed ROM address (with the PRG bank mapped at $8000) while a
-- random "bot" plays: it walks, jumps, climbs,
-- whips and throws sub-weapons. Environment:
--   PROBE_OUT  directory for cov_<RUN>.txt
--   RUN        name of this run
--   SLOT       savestate slot to start from (0 = power-on, start a game)
--   FRAMES     frames to play (default 3000)
--   SEED       random seed
--   INVINCIBLE 1: keep health and time topped up (default 1)
--   SUB        sub-weapon code to give Simon ($15B), with hearts
--   STAGE      (from power-on) start at this stage: $28 written before it loads
--   SEQ        steps "clear:N,stage12:N,...": force the stage clear ($18 = $0C:
--              the next stage, its block's graphics), or restart at a stage
--              (Simon dies with $28 changed), then play N frames; FRAMES is
--              ignored then
-- Output lines: "X bank addr" (executed); bank 7 for $C000-$FFFF; "S frame
-- stage mode" when the stage number changes. Addresses
-- only, no ROM content. (Data reads are not logged: FCEUX reports opcode
-- fetches as reads too, which is far too slow; the disassembler finds data.)
local out = os.getenv("PROBE_OUT") or "."
local run = os.getenv("RUN") or "run"
local slot = tonumber(os.getenv("SLOT") or "0")
local frames = tonumber(os.getenv("FRAMES") or "3000")
local inv = (os.getenv("INVINCIBLE") or "1") == "1"
local sub = tonumber(os.getenv("SUB") or "0")
math.randomseed(tonumber(os.getenv("SEED") or "1"))

local bank = 0
local exec, data = {}, {}
memory.registerwrite(0x8000, 0x8000, function(a) bank = memory.readbyte(a) end)
memory.registerexecute(0x8000, 0x8000, function(a)
  local b = (a >= 0xC000) and 7 or bank
  exec[b * 65536 + a] = true
end)

if slot > 0 then savestate.load(savestate.object(slot)) end
local stage = tonumber(os.getenv("STAGE") or "-1")
local steps = {}
for kind, n in string.gmatch(os.getenv("SEQ") or "", "(%w+):(%d+)") do
  steps[#steps + 1] = {kind, tonumber(n)}
end
local step_at, step_i = {}, 0
if #steps > 0 then
  frames = 0
  for i, st in ipairs(steps) do step_at[frames + 1] = st[1]; frames = frames + st[2] end
end
local hold, dir, lastx, still = 0, "right", -1, 0
local visits, last_stage = {}, -1
for f = 1, frames do
  local pad = {}
  if slot == 0 and ((f >= 100 and f <= 104) or (f >= 300 and f <= 303)) then pad.start = true end
  if slot == 0 and stage >= 0 and f >= 600 and f <= 647 then memory.writebyte(0x28, stage) end
  local act = step_at[f]
  if act == "clear" then memory.writebyte(0x18, 0x0C); memory.writebyte(0x19, 0)
  elseif act and string.sub(act, 1, 5) == "stage" then
    memory.writebyte(0x28, tonumber(string.sub(act, 6))); memory.writebyte(0x45, 0)
  end
  if inv and memory.readbyte(0x18) == 5 and not (act and string.sub(act, 1, 5) == "stage") then
    memory.writebyte(0x45, 64); memory.writebyte(0x43, 3)
  end
  if sub > 0 then memory.writebyte(0x15B, sub); memory.writebyte(0x71, 20) end
  if hold <= 0 then
    local r = math.random(100)
    if r < 45 then dir = "right" elseif r < 75 then dir = "left"
    elseif r < 85 then dir = "up" elseif r < 92 then dir = "down" else dir = "none" end
    hold = math.random(10, 90)
  end
  hold = hold - 1
  if dir ~= "none" then pad[dir] = true end
  local wx = memory.readbyte(0x40) + 256 * memory.readbyte(0x41)
  if wx == lastx then still = still + 1 else still = 0 end
  lastx = wx
  if (still > 8 and f % 30 == 0) or math.random(100) == 1 then pad.A = true end
  if math.random(20) == 1 then pad.B = true end
  if math.random(200) == 1 then pad.up = true; pad.B = true end
  joypad.set(1, pad)
  emu.frameadvance()
  local st = memory.readbyte(0x28)
  if st ~= last_stage then
    visits[#visits + 1] = string.format("S %d %d %02X", f, st, memory.readbyte(0x18))
    last_stage = st
  end
end
local fh = io.open(out .. "/cov_" .. run .. ".txt", "w")
for _, v in ipairs(visits) do fh:write(v .. "\n") end
for k in pairs(exec) do fh:write(string.format("X %d %04X\n", math.floor(k / 65536), k % 65536)) end
for k in pairs(data) do fh:write(string.format("D %d %04X\n", math.floor(k / 65536), k % 65536)) end
fh:close()
os.exit(0)
