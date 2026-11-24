# Roadmap

## Milestone 0: engine skeleton ✅ (this commit)

- [x] Build system: sjasmplus + Python, 128 KB ASCII16 MegaROM
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
- [ ] Real collision data (currently: ground tiles are solid)
- [ ] Entrance hall (decoded, needs its palette, stairs and collision)
- [ ] Palette selection table, remaining sections of bank 4, banks for blocks 2-6
- [ ] Area transitions (load the next area from banks 2-7)

## Milestone 2: Simon (in progress)

- [x] Simon's graphics from the ROM: stand, walk ×2, tucked; both directions, 3 colours, no loss
- [x] Walk speed and animation timing as on the NES
- [x] Jump arc from the ROM's table, matching the NES frame by frame (checked by the test)
- [x] Crouch
- [ ] Knock-back arc, falling speed after the arc
- [ ] Whip (needs extra sprites; poses up to 24 px wide), stairs
- [ ] Sub-weapons
- [ ] Hearts, score, timer, life bar in the HUD

## Milestone 3: objects and enemies

- [ ] Object system modelled on the NES one (slots, spawn by camera position)
- [ ] Candles and item drops
- [ ] Zombie, panther, bat, fishman, …
- [ ] Sprite multiplexing and flicker when more than 8 sprites share a line
- [ ] Vertical transitions between sections (V9958 vertical scroll)

## Milestone 4: sound

- [ ] Music driver: NES pulse/triangle/noise → MSX-MUSIC FM + PSG
- [ ] Convert the song data from the ROM
- [ ] Sound effects on the PSG, samples on the turbo R PCM

## Milestone 5: performance and polish

- [ ] Own the interrupt vector (RAM in page 0), drop the BIOS
- [ ] Copy hot code to RAM for the R800
- [ ] Bosses, all six blocks, ending
- [ ] Test on real hardware
