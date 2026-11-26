# Roadmap

## Milestone 0: engine skeleton ✅ (this commit)

- [x] Build system: sjasmplus + Python, ASCII16 MegaROM (512 KB with block 2)
- [x] Boot, R800 switch on turbo R, page 2 slot select, mapper banking
- [x] Screen 4 setup, palette, BIOS font, HUD
- [x] V9958 hardware horizontal scroll with fixed HUD (line-interrupt split)
- [x] Column streaming from a metatile map
- [x] 3-colour 16x32 player from 4 OR-ed sprites, 4 animation frames, both directions
- [x] Walking, committed jump, gravity, tile collision, pits
- [x] Automated headless test in openMSX (C-BIOS MSX2+)

## Milestone 1: data pipeline from the user's ROM (in progress)

- [x] ROM check, bank split, tile viewer, 6502 disassembler
- [x] CHR-RAM loader tables decoded; stage graphics rebuilt from ROM, byte-exact
- [x] Stage layout format decoded (6 blocks per column, 17-byte blocks)
- [x] Converter: NES tiles + palettes → Screen 4 tiles (2 colours per row), per-band tile sets
- [x] Stage 1 courtyard + castle gate playable in the MSX build (`make nes`)
- [x] Real collision rule from the ROM (tiles $60-$6B), per 8x8 tile
- [x] Areas in their own ROM banks; the courtyard gate leads into the entrance hall
- [x] Entrance hall: graphics, layout, collision, wall candles
- [x] Stairs from the ROM's stair table: get on/off, climb and descend, whip on stairs
- [x] The exit door at the end of the hall (upper floor) into stage 2's first section
- [x] The doors' sequence (camera scroll, door opens and closes, walk on), the
      castle gate walk-in, the stage number in the HUD
- [x] The opened door's picture (half open, open) and Simon going into the castle gate
- [x] Sections joined by stairs: stage 2's stairs down to the waterway and back up
- [x] Stage 2: the rest of the route and its exit door, into stage 3
- [x] Stage 3's boss: wake, hover, swoop, health in the HUD, burns, orb, stage clear
- [x] Stage clear sequence (timer and hearts to score), per-stage timer after a death
- [x] Block 2's maps (stages 4-6): graphics, collision, stairs, candles, doors at the left, music
- [x] Block 2's enemies: Medusa heads, spear knights, hanging bats
- [x] Stage 6's ceiling crushers
- [x] Medusa (stage 6 boss) and her snakes
- [x] Block 3's maps (stages 7-9): graphics, stairs, candles, doors, music
- [ ] Block 3's enemies and boss; blocks 4-6; the castle map between blocks
- [ ] Palette selection table, stages 2 and up

## Milestone 2: Simon (in progress)

- [x] Simon's graphics from the ROM: stand, walk ×2, tucked; both directions, 3 colours, no loss
- [x] Walk speed and animation timing as on the NES
- [x] Jump arc from the ROM's table, matching the NES frame by frame (checked by the test)
- [x] Crouch
- [ ] Knock-back arc, falling speed after the arc
- [x] Whip: standing, crouching and jumping, NES timing (checked by the test), hit box
- [x] Metasprites with double-buffered sprite pages (VBLANK work stays under 3 ms)
- [x] Stairs (climbing pose recorded from the NES; descending reuses it)
- [x] Whip upgrades (chain, morning star)
- [ ] Whip poses on stairs
- [ ] Sub-weapons
- [x] Hearts, score, timer, lives, life bar and stage number in the HUD
- [x] Death (animation, lives, restart at the section), time out, game over

## Milestone 3: objects and enemies (in progress)

- [x] Object system: 8 slots, sprites after Simon's, colours written per frame
- [x] Braziers from the ROM's placement data; whip destroys them (NES burst timing)
- [x] Item drops: big heart (+5, shown in the HUD), whip upgrade, dagger; fall and pickup
- [x] Use the whip upgrades (chain whip, morning star: graphics and reach) and the dagger (throwing, heart cost)
- [x] Axe and holy water (from the candles that drop them)
- [x] The stopwatch; the sub-weapon icon in the HUD; a heart instead of a
      sub-weapon already held
- [ ] Morning star flashing; the cross; double and triple shots
- [x] Wall candles and small hearts; candles spawn by camera position like the NES
- [ ] The NES item drop rule, money bags, enemy drops
- [x] Zombies from the ROM's enemy groups: spawn at the screen edges, walk across, die to the whip
- [x] Health, getting hit: freeze, knock-back arc from the ROM, crouched landing, blinking invincibility
- [x] Sprite priority rotation (flicker instead of missing sprites past 8 per line)
- [x] Black panthers: wait, run, leap off the platform, run along the floor, never come back
- [x] Zombies in waves of 3, like the NES
- [x] Object sprite patterns per area, checked against the 52 free pattern slots
- [x] Bats (stage 2): appear at the screen edge, fly at Simon in a wave
- [x] Fishmen (stage 2 waterway): jump out of the water, walk, shoot fireballs
- [ ] The splash; enemy type $04 (still unidentified);
      enemy drops; score, lives, timer, death animation
- [ ] Zombie, panther, bat, fishman, …
- [ ] Sprite multiplexing and flicker when more than 8 sprites share a line
- [ ] Vertical transitions between sections (V9958 vertical scroll)

## Milestone 4: sound

- [ ] Music driver: NES pulse/triangle/noise → MSX-MUSIC FM + PSG
- [ ] Convert the song data from the ROM
- [ ] Sound effects on the PSG, samples on the turbo R PCM

## Milestone 5: performance and polish

- [ ] Keep busy scenes within one frame on a 3.58 MHz Z80 too (about 3% of frames in
      the hall go over today; the turbo R's R800 is several times faster)

- [ ] Own the interrupt vector (RAM in page 0), drop the BIOS
- [ ] Copy hot code to RAM for the R800
- [ ] Bosses, all six blocks, ending
- [ ] Test on real hardware
