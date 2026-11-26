# Castlevania (NES): the enemies of stages 4-9, read from the code

What the port's enemies (src/enemies2.asm) follow. Read from the disassembly
of your own ROM (`make disasm`); the engine's helpers are described in
[NES_ENGINE.md](NES_ENGINE.md). Coordinates: NES x and y are the object's
middle; in the port an object's (x, y) is its box's top left, Simon's middle
is (px+8, py+16), and port y = NES y - 48.

## Shared rules

- **The whip hits on one frame of each swing** (Simon's attack counter `$11`,
  `$E40B`): the port's `WHIP_HIT_T`, the 5th strike frame.
- **Damage to Simon on touch** (`$E74A`): 8 in stages 1-6, 12 in stages 7-11, 16
  from stage 12 (and in the second quest). Not while he blinks after a hit.
- **Touch boxes** (`$E6C6`): |dx| < half width + 4 and |dy| < half height + 12
  (10 when Simon ducks), between the middles; half sizes from `$E476`.
- **Who dies touching Simon**: only the bats (`$02`, `$07`) and the raven (`$0F`),
  as if whipped. Everything else (heads, snakes, bones, fireballs, bandages)
  flies on.
- **Damage that adds up** (whip 6 at level 0, 8 at levels 1-2, x 4: 24 / 32;
  the dagger as level 0, the axe as level 1): knight and ghost die at 64 (3
  leather hits, 2 chain/morning star), the bone pillar at 192 (8 / 6). A hit
  that doesn't kill freezes the knight and the ghost 16 frames (no move, no
  animation). Medusa takes half the damage (3 / 4 a hit, 8-frame freeze), the
  mummies a quarter (1 1/2 / 2 of their 32, 8-frame freeze).
- **Scores** (`$DF35`): Medusa head 300, hanging bat 200, knight 400, snake 100,
  fleaman 500, ghost 300, pillar 400, raven 200, skeleton 300, bone / fireball /
  bandage 100, Medusa and each mummy 3000.
- **Drops** (`$E0A2`): a beaten enemy becomes a flame; 1 time in 16
  (`frame & 15 = 2`) it leaves a sub-weapon from the stage's list (`$E137`; not
  for bones, fireballs, bandages), else 1 time in 8 (`frame & 7 = 0`) a heart
  (big for the knight, fleaman and pillar).
- **Spawners act only on the screen** (screen x 8..`$F8`, `$F3A2`); objects are
  removed when their middle leaves screen x 8..`$F8` (the knight and the
  skeleton survive up to 64 px beyond it).
- **The random byte** `$6F` (`$C030`): `$6F = T[($6F | frame) & 15]`, stepped in
  the idle loop; the port steps it once a frame (`rng_step`).

## Block 2

- **Medusa head** (`$06`, spawner `6:$8435`): the spawner's timer ticks every
  other frame; the first head 18 frames after the spawner comes on screen, then
  one every 128 frames, at most 3, waiting (not restarting) while Simon is on
  the stairs. It starts at the screen edge Simon faces, 33 px above his middle,
  and flies 1 1/4 px a frame on a spring around his middle (`wave_y`, k =
  1/256: 34 px up and down, ~100 frames).
- **Hanging bat** (`$07`, `5:$841B`): wakes when Simon's middle is 1-56 px
  below its middle and -95..+96 px across; then 1 1/2 px a frame across and
  down from 1 1/2 px, slowing 9/256 px a frame (31 px over 42 frames), then
  level.
- **Spear knight** (`$08`, `5:$847E`): 1/2 px a frame, starts facing Simon.
  With Simon level with it (his y - its y in -3..+4) it faces him at once and
  every 192 frames; otherwise it turns round every 192 frames (first after
  256). It turns at a wall 16 px ahead of its middle or a floor end 4 px
  ahead, and falls (gravity 1/8 px) when the floor goes from under it.
- **Medusa** (`$1B`, `5:$82ED`): the camera reaching her room locks it (and
  every other enemy bursts); 180 frames later the statue's 4x4 tiles go and
  she starts. Each flight: a snake drops, she faces Simon, flies 7/8 px a frame
  for 15, 127, 63 or 159 frames (in turn, from a random start) on a spring
  around her y + 4, turning at screen x 16 / 240 and after hurting Simon; then
  she hovers 60 frames still, and rises 1/2 px a frame while below NES y `$A8`.
- **Snake** (`$09`, `5:$83B1`): faces Simon, falls to a floor, slides 1 1/2 px
  a frame 23 frames on and 2 still; off a floor it faces Simon and falls again.

## Block 3

- **Fleaman** (`$0C`, `$EFC4`): once on the screen it sits 60 frames, drops to
  the floor, crouches 8 frames, hops: high (3 1/2 px up, 1 px across) when Simon
  is within 64 px and they face each other, else long and low (1 px up, 2 1/4
  px across); lands on any floor (tested every frame in the air), crouches 8,
  hops again. It turns to Simon before a hop unless he blinks.
- **Ghost** (`$0D`, `$EDC7`): appears when its record is in the screen's left
  strip (`$0D`) or right strip (`$8D`) and Simon's middle is within 48 px of
  its height, at most 2; flies straight at Simon's middle, 3/4 px a frame on
  the long axis, re-aimed every 32 frames.
- **Bone pillar** (`$0E`, `$F178`): once on the screen: 24 frames, 24 more
  flashing, a fireball (2 px a frame from its middle towards Simon), another 40
  frames later, then 240/60/120/180 frames (random) and again. Scrolled off,
  it comes back afresh.
- **Raven** (`$0F`, `5:$87AF`): perches 60 frames once on the screen, then
  swoops up or down towards Simon's height at a random 1 1/4 - 2 1/2 px a frame,
  slowing 9/256 px a frame, 3/4 px across; hovers 24-121 frames; swoops again
  if Simon is 32 px or more above or below, else dashes at him (from 1/4 px,
  +1/32 px a frame, 60 frames); 8 px past him it slows, turns back and speeds
  up (120 frames). Its picture always faces Simon.
- **Skeleton** (`$10`, `5:$8527`): faces Simon; walks 0-3 legs (random) of 15
  frames at 1 1/2 px (towards Simon from 72 px, away when nearer; the other
  way at a wall), 4 frames still between; stands 4, throws a bone, stands 8.
  Off a floor it jumps (1 1/4 px across, 2 1/2 px up). Bones: from its middle,
  3/4 px across, 4 1/2 px up on even frames, 3 1/2 on odd ones, gravity.
- **Mummies** (`$1A`, `5:$866C`): the camera at the tower room locks it; they
  get up for 120 frames (no harm, no hits), then walk 3/4 px a frame for 123,
  65, 180 or 32 frames in turn, facing Simon every 32 frames (and walking away
  if he faces one within 56 px), standing at the screen's edges; then stand 40
  frames, throw a bandage (at the middle y +/- 8, 1 1/2 px a frame on a spring
  ~24 px up and down), stand 8 and walk on. Both burn 60 frames when beaten;
  the last leaves the orb.
