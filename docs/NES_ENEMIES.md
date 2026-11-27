# Castlevania (NES): the enemies, read from the code

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

## Block 1

- **Spawners** (`$F382`): every record on the screen (x 8..`$F8`) runs, each
  with its own timer, counted down every other frame while it is on the screen.
- **Zombie** (`$01`, spawner `6:$805D`, AI `5:$8030`): at most 3; a random edge
  (not the one within 64 px of Simon) with floor there; 32 frames to the next,
  288 after every third (a global counter, `$63`, never reset: the first wave
  after power-on has 4). It walks 7/8 px a frame, turns at a wall 16 px ahead,
  falls off ledges. (The hall recordings fit: the next wave comes 288 frames
  after the last one's third zombie, not after it is gone.)
- **Bat** (`$02`, `6:$80E7`): every 384 frames, at most 3, not while Simon is
  on the stairs; at the edge he faces (the other when that one is within 64
  px), at his middle -19, -11, -3 or +1 (by the frame), 1 1/8 px a frame on a
  spring dipping 18 px.
- **Fishman** (`$03`, `6:$8182`, `$F08D`): 168 frames after its record comes on
  the screen, then every 510; at most 2; not within 40 px of Simon. It leaps
  5 1/2 px up, lands on a 16-px row, stands 8 frames, walks 3/4 px a frame for
  79/121/93/144 frames (random), aims 16 frames, shoots (from 8 px above its
  middle, 1 3/4 px a frame), waits 16.
- **Black panther** (`$11`, `5:$8275`): wakes when Simon is within 64 px
  across, runs 2 px a frame, leaps (1 1/2 px up, gravity 1/8) at an edge, runs
  at him again after landing; once awake, gone when it leaves the screen.
- **Giant bat** (`$19`, `5:$80EF`): asleep 120 frames after the screen locks;
  then flies (3/4 px a frame on the long axis) to Simon's middle +72 or -73
  across and 41 px above; hovers 123/32/61/199 frames; every 16 frames of a
  hover, if Simon faces it within 88 px and 20 px of its height, rises 2 1/2 px
  a frame for 7 frames; at the end, Simon's middle above its middle: a
  fireball at him (1 1/2 px a frame), else a swoop aimed 25 px below him (2 px
  across, the downward speed falling 6/256 a frame: a U through and past him)
  until it rises above NES y 112. A hit takes the weapon's full damage and
  stops it 8 frames. The orb shows at the screen's middle (128, 128) 60 frames
  after the burn, flashes 32 frames, then falls.

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

## Block 4 (stages 10-12)

- **Stages:** block 4's tile blocks are at `$975B`, its palette is `$CE61` (the per-block
  table at `$CD15`), its graphics sets are 3 and 6 (`$C8B0`), and its music is
  `$39` for stage 10 and block 2's `$2D` for stages 11 and 12. Each stage
  ends at the NES's exit point (`$FC19`): stage 10's is halfway up its last
  steps, stage 11's is at its right edge. Record type `$04` makes nothing in
  the first quest.
- **Eagle** (`$12`, spawner `$F4DE`, AI `$ECFE`): one every 112 frames while
  its record is on the screen (at most 3). It starts at screen x 18 (flying
  right) or 238 (flying left), at random, at the record's height + 32, 16, 48,
  0 in turn. It flies 1 3/4 px a frame for 47 frames and hovers for 17, at a
  fixed height. It carries a fleaman 16 px below it, which drops when the
  eagle is gone or Simon comes within 64 px across (checked every 8 frames).
- **Bone dragon** (`$14`-`$16`, `6:$8867`, `5:$8AAD`): a root vertebra fixed in
  a right-hand wall, 5 vertebrae and a skull. The neck grows out to 52 px,
  then the head moves up and down 1 3/4 px a frame. It is aimed at Simon's
  height every 32 frames, turns at the end of each leg (52/36/60/28 frames)
  and after each attack, and pushes the vertebrae along as a chain (each
  within 8 px of the next). Every 32 frames, 1 time in 2, it opens its mouth
  for 16 frames, fires at Simon (if he is left of it and near its height),
  then waits 16 more. Only the head can be hurt: damage adds up to 192
  (1000 points).
- **Red skeleton** (`$13`, `5:$91A4`): it gets up from a bone pile, walks in
  48-frame legs at 5/8 px a frame, and turns at walls. A hit collapses it
  (400 points every time); it gets up again and never dies.
- **Frankenstein's monster and Igor** (`$1C`, `$1F`): every other enemy goes
  when they appear. When the camera locks they wait 120 frames, then Frank
  walks at Simon carrying Igor for 60 frames and lets him go. After that Frank
  walks in legs of 60/36/84/24 frames: towards Simon from 80 px away, else
  away. Igor hops 3/5/4/6 px up, 1 1/2 px across, and spits a fireball when
  he is let go and at the top of every hop. A hit on Igor stops him for 84
  frames. Frank takes half the weapon's damage; beaten, he gives 5000 points
  and leaves the orb.

## Blocks 5-7 (stages 13-18)

- **Stages:** see NES_NOTES.md, "Blocks 5-7". The stages reuse the fleaman,
  the skeleton, the red skeleton, the bone pillar, the eagle and the Medusa
  heads (stage 15's generator `6:$8A44` does what block 2's does: one head
  every 64 ticks, at most 3, from the edge Simon faces).
- **Axe knight** (`$0A`, record `$4A` `6:$89F5`, AI `5:$90D2`, hits `$E214`):
  at most two. It always faces Simon and walks in cycles of 9/11/10/12 legs
  (16 frames at 5/8 px, then 4 still): towards Simon when he is 80 px or
  more away, else away; a wall 12 px ahead at its waist or no floor 4 px
  ahead turns it at once. After the last leg it stands 16 frames and throws
  an axe (`$27`, `5:$8DEE`) at its head or knee height (random), 1 1/4 px a
  frame for 87 frames; the axe slows by 1/8 px a frame, turns, and flies back
  until the knight catches it. A page away from the camera the knight stands.
  Its guard: a whip hit face to face, or a sub-weapon from the front, only
  adds to the guard (a clink) until 224; after that hits count, 64 kill it
  (500 points, always a big heart). A hit freezes it 16 frames (a sub-weapon
  8 first).
- **Giant bat** (`$1E`, record `$5E` `6:$8AED`, AI `5:$9386`, hits `$E1AE`):
  at most three, on stage 16's bridge. It waits 60 frames, flies straight at
  a point 48 px right of and 16 px above Simon (screen x wrapping: from the
  right of the screen it goes left) at 3/4 px on the long axis for
  61/37/32/69 frames, hovers 123/32/61/199 frames (jumping 2 1/2 px up for 7
  frames if Simon swings near it), then fires a fireball when Simon is above
  it, far below or 72 px or more across, else swoops at his feet (curving
  back up). Off the screen it flies straight across. 192 damage, 3000 points.
- **Death** (`$18`, record `$58` `6:$8AA9`, AI `5:$8EE0`, hits `$E282`):
  made when the camera comes within 216 px of his room (every other enemy
  goes). 120 frames after the camera locks he appears at the top right and
  floats down (2 1/2 px, slowing 5/256 a frame). At every landing he throws
  3 sickles (`$0B`, `5:$8FF8`) placed from Simon's position (+160/-80,
  +48/+24, +4/-48, wrapping on the screen); they flicker 40 frames, then aim
  at Simon (7/8 px on the long axis), fly 119 frames, stop 32, and aim again.
  He then stands 144/95/185/84 frames: every 32 frames, if Simon is within
  72 px, he leaps at him (1 1/4 px across, 2 px up); else when the time is up
  he hops 1 or 2 px up, 3/4 px across to a random side. In the air gravity is
  6/256 a frame and he bounces off screen x 16 and 240; his feet probe the
  floor every frame, rising too (a low hop lands at once, 8 px higher). Half
  the weapon's damage off the boss bar, 8 frames frozen a hit; 7000 points
  and the orb. The sickles fly on after he is beaten.
- **Dracula** (`$1D`, record `$5D` `6:$8B3B`, AI `5:$950E`, hits `$E327` on
  the body, `$E34B` on an invisible head box `$04`): made like Death. The
  stage music goes on (no boss music). 120 frames after the lock his head
  shows at the floor, rises 1/2 px a frame to y 168 and he flickers in. Then
  a loop: stand 36/16/50/24 frames, open the cape 16, fire 3 fireballs (at
  Simon's middle and 16 px below and above it, 2 px a frame), 32 more,
  vanish (32 + 79 frames away) and reappear by Simon (his screen x + 16, -8,
  +128, +96, +48, -40, +96 or -88, kept within 20..235). Only the head box
  takes damage (half the weapon's), and only while he stands, opens the
  cape or fires; the body clinks. At 0 the head flies off, the body stands
  120 frames, crumbles into 6 pieces, and the monster appears with a full
  bar: it stands 33 frames, waits 85 or 123 (crouching at once if Simon faces
  it swinging), crouches 16, jumps at Simon (6 or 4 1/2 px up, gravity 3/16,
  3/4 px across, turning at screen x 24/232), lands, and when 48 px or more
  away (3 times in 4) opens its mouth and fires 3 from its head. A quarter of
  the weapon's damage on its head box, 8 frames frozen a hit; holy water also
  burns its body slowly. 50000 points and the orb.

## Frames

`tools/nes_frames.py ROM FRAME [FACING]` runs the NES's own sprite builder
(bank 0 `$8052`, frame tables `$8FBE` / `$90BE`) and lists a frame's sprites.
From it: the knight walks on frames `$9A`-`$9D` (legs 84, 88, 8C, 88, the body
1 px lower on the first and third); the skeleton has its own frames `$B1`
(80-86) and `$B2` (88-8E); the mummies walk on `$67`, `$68`, `$69`, `$68`; the
snake's frame `$75` draws F2 before F0; the bone pillar's skulls face Simon
(frame `$9E` mirrored by the facing). An object's `obj_attr` 3 (the pillar's
flash) or `$43` (the mummy winding up) only changes palette 1 to palette 3.
Where an area's sprite patterns run short, the converter folds the frames
added from this table first (tools/convert_objects.py FOLDS).
