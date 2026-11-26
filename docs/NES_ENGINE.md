# Castlevania (NES): the object engine, read from the code

Read from the disassembly that `tools/nes_disasm.py` makes from your own ROM
(`make disasm`, into `build/disasm/`, never committed). Names are the ones in
`tools/nes_labels.txt`. Addresses: the fixed bank at `$C000`; `5:8xxx` is bank 5.

## Banks

- Code runs in banks 0 (sound), 5 (object AI), 6 (game logic, spawners, Simon,
  stages) and 7 (fixed). Banks 1-4 hold only data (maps, graphics).
- `switch_bank` (`$C1D6`, Y = bank) maps a bank; `restore_bank` (`$C1D4`) maps
  `$24` again, which is set to 6 once at reset. So fixed-bank code normally runs
  with bank 6 mapped; `objects_update` runs with bank 5.

## The frame

`frame_playing` (`$CED0`): ... `$CF14`: bank 5, `objects_update` (`$E8FC`); bank 6,
`spawners_update` (`$F382`), `6:A4AA`, then the per-stage events (`6:A63A`).

`objects_update` walks slots 22 down to 3 and, for a non-zero `obj_id`, runs the
handler in the word table `$E968` (by object id, `jump_table` at `$CA6D`), then
`obj_cull` (`$E9F2`) and, through it, the collision with Simon and the whip
(`$E4E5`) and `animate` (`$F1E7`).

## Per-object arrays (indexed by slot; slot 0 = Simon)

| Address | Name | Meaning |
|---|---|---|
| `$0300` | `obj_xpage` | bit 0: a screen page beyond the camera |
| `$031C` | `obj_frame` | sprite frame shown |
| `$0338` | `obj_attr` | sprite attribute bits (palette) |
| `$0354` / `$0370` | `obj_y` / `obj_y_frac` | |
| `$038C` / `$03A8` | `obj_x` / `obj_x_frac` | screen x |
| `$03C4` / `$03E0` | `obj_vy` / `obj_vy_frac` | y speed; **+ is up** (`y_minus_vy`) |
| `$03FC` / `$0418` | `obj_vx` / `obj_vx_frac` | x speed, applied along the facing |
| `$0434` | `obj_id` | |
| `$0450` | `obj_facing` | 0 right, 1 left |
| `$046C` | `obj_state` | AI state (most handlers jump on it) |
| `$0488` | `obj_anim_delay` | bit 7: animation stopped |
| `$04A4` | `obj_anim_step` | |
| `$04C0` | `obj_anim` | animation (3-byte entries: count, first frame, delay) |
| `$04DC` | `obj_ydir` | `aim_at`: 1 = moving up; `wave_y`: the centre y |
| `$04F8` | `obj_dir2` | a second direction; `wave_y`'s shift count |
| `$0530` | `obj_spawner` | spawner slot that made it |
| `$054C` | `obj_timer` | |
| `$0568` | `obj_freeze` | frames frozen after a hit (`obj_frozen` skips the AI) |
| `$0584` | `obj_item` | item it drops |

Speeds are 8.8 fixed point (whole px, 1/256 px). The adds don't always clear
the carry first (`x_plus_vx` etc. use the carry left by the caller), so a
1/256 px difference now and then is the NES's own.

## Helpers (fixed bank)

- `move_x` (`$EE54`): x += vx (facing right) or x -= vx (left), plus
  `scroll_frac` (`$7C`). `move_x_page` (`$EE81`) also carries into `obj_xpage`.
  `move_x_dir2` / `move_x_dir2_page` use `obj_dir2` instead of the facing.
- `gravity` (`$EC5C`): vy -= `$20`/256 (1/8 px), then y -= vy: a fall that
  speeds up by 1/8 px a frame. `y_plus_vy` / `y_minus_vy` apply vy only.
- `wave_y` (`$EF1F`): vy -= (y - centre) >> `obj_dir2` (signed), then
  y += vy: a spring around the centre y (the bat, the Medusa head).
- `set_vx` (`$EC7E`, A = px, Y = fraction), `set_vy` (`$ECF6`), `clear_vy`
  (`$F1DE`), `set_state_timer` (`$ED40`, A = timer, Y = state).
- `probe_ahead` (`$EC2D`): is the tile at x ± `probe_dx` (by the facing),
  y = `probe_y` solid? -> `probe_solid` (`$14`). `probe_feet` (`$EFA8`): at
  (x, y+16); `probe_feet8` (`$EFA4`): at (x, y+8).
- `face_simon` (`$EF88`), `dist_x_simon` (`$EF90`: A = |dx|, Y = 1 when
  Simon is to the left), `turn_around` (`$EAB5`), `snap_y8` (`$EFBB`).
- `aim_at` (`$EEC7`, $00 = target y, $01 = target x): faces the target, sets
  `obj_ydir`, and divides the short axis by the long one (`$CA41`) into
  $01.$02; `$09` says which axis is the long one. Callers then give the long
  axis a fixed speed and the short one the ratio (e.g. `ai_ghost`: 3/4 px).
- `spawn_child` (`$ED8E`): a new object (id `$16`, animation A) at the
  object's place, facing its way. `shoot_at_simon` (`$EC94`): object `$20` in
  slot 12 or 13, 1 1/2 px a frame along the long axis, aimed at Simon.
- `obj_cull` (`$E9F2`): an object whose y leaves 8..`$F7`, or whose x leaves
  8..`$F8` (16..`$F0` for objects `$12` and `$1E`), is removed (`obj_to_burst`,
  then the spawner is freed for those that have one). Objects `$08`, `$0A`,
  `$10`, `$13`, `$1E` use `obj_xpage` and survive a page away.
- `hit_and_cull` (`$EEA0`): the collision (`$DD1F`) then the cull.

## Collision with the whip (`$E4E5`)

Box half-sizes by object id: the table at `$E476` (2 bytes: x, y), plus the
whip's ($73, $74) and its centre ($68, $69). The whip's damage is the pair
at `$E5E5 + 2*whip_level`. Then the handler at `$E585` (by object id) does the
hit: most use `$E0A2`.
