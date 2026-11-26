#!/bin/bash
# Coverage runs for tools/nes_disasm.py (make disasm): FCEUX plays your own ROM
# (build/nes/castlevania.nes) with tools/nes_probe/trace_code.lua, 4 at a time;
# each line = the environment of one run. SLOT n = an FCEUX savestate you made
# (1: stage 4, 5: stage 5, 6: stage 6, 7: Medusa, 8-10: stages 7-9, 2: the mummies).
# Output: build/nes/trace/cov_*.txt (addresses only) and runs.log.
cd "$(dirname "$0")/../.." && mkdir -p build/nes/trace && cd build/nes/trace
export PATH=$PATH:/usr/games
runs=(
"RUN=po1 SLOT=0 SEED=1 FRAMES=6000"
"RUN=po2 SLOT=0 SEED=2 FRAMES=6000"
"RUN=po3 SLOT=0 SEED=3 FRAMES=6000 SUB=8"
"RUN=po4 SLOT=0 SEED=4 FRAMES=6000 SUB=11"
"RUN=die1 SLOT=0 SEED=5 FRAMES=9000 INVINCIBLE=0"
"RUN=die2 SLOT=0 SEED=6 FRAMES=9000 INVINCIBLE=0 STAGE=2"
"RUN=st2a SLOT=0 SEED=7 FRAMES=6000 STAGE=2 SUB=13"
"RUN=st3a SLOT=0 SEED=8 FRAMES=6000 STAGE=3 SUB=14"
"RUN=st3b SLOT=0 SEED=9 FRAMES=6000 STAGE=3"
"RUN=st1b SLOT=0 SEED=10 FRAMES=6000 STAGE=1 SUB=15"
"RUN=s4a SLOT=1 SEED=11 FRAMES=5000"
"RUN=s4b SLOT=1 SEED=12 FRAMES=5000 SUB=8 INVINCIBLE=0"
"RUN=s5a SLOT=5 SEED=13 FRAMES=5000 SUB=13"
"RUN=s5b SLOT=5 SEED=14 FRAMES=5000"
"RUN=s6a SLOT=6 SEED=15 FRAMES=5000 SUB=11"
"RUN=s6b SLOT=6 SEED=16 FRAMES=5000 INVINCIBLE=0"
"RUN=med1 SLOT=7 SEED=17 FRAMES=5000"
"RUN=med2 SLOT=7 SEED=18 FRAMES=5000 SUB=11"
"RUN=s7a SLOT=8 SEED=19 FRAMES=5000"
"RUN=s7b SLOT=8 SEED=20 FRAMES=5000 SUB=14"
"RUN=s8a SLOT=9 SEED=21 FRAMES=5000"
"RUN=s8b SLOT=9 SEED=22 FRAMES=5000 SUB=13 INVINCIBLE=0"
"RUN=s9a SLOT=10 SEED=23 FRAMES=5000"
"RUN=mum1 SLOT=2 SEED=24 FRAMES=5000"
"RUN=mum2 SLOT=2 SEED=25 FRAMES=5000 SUB=11"
"RUN=b4 SLOT=10 SEED=26 SEQ=clear:4000,stage11:3000,stage12:4000"
"RUN=b4b SLOT=10 SEED=27 SUB=13 SEQ=clear:2000,stage12:5000,clear:2000"
"RUN=b5 SLOT=10 SEED=28 SEQ=clear:1500,stage12:500,clear:4000,stage14:3000,stage15:4000"
"RUN=b5b SLOT=10 SEED=29 SUB=11 SEQ=clear:1500,stage12:500,clear:1500,stage15:5000,clear:2000"
"RUN=b6 SLOT=10 SEED=30 SEQ=clear:1500,stage12:500,clear:1500,stage15:500,clear:4000,stage17:4000"
"RUN=b6b SLOT=10 SEED=31 SUB=13 SEQ=clear:1500,stage12:500,clear:1500,stage15:500,clear:2000,stage18:8000"
"RUN=end1 SLOT=10 SEED=32 SEQ=clear:1500,stage12:500,clear:1500,stage15:500,clear:2000,stage18:1500,clear:8000"
"RUN=end2 SLOT=10 SEED=33 INVINCIBLE=0 SEQ=clear:1500,stage12:500,clear:1500,stage15:500,clear:2000,stage18:9000"
"RUN=title SLOT=0 SEED=34 FRAMES=4000 STAGE=-1"
)
i=0
for r in "${runs[@]}"; do
  ( env $r PROBE_OUT=$PWD timeout 1800 xvfb-run -a fceux --no-config 1 --sound 0 --loadlua ../../../tools/nes_probe/trace_code.lua ../castlevania.nes >/dev/null 2>&1; echo "done $r" >> runs.log ) &
  i=$((i+1))
  if (( i % 4 == 0 )); then wait; fi
done
wait
echo ALLDONE >> runs.log
