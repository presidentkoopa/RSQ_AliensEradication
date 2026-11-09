# The Power Loader: a code review and a wish list (2026-11-08)

Read in full: `zscript/ae/loader.zs` (1,644 lines), `actors/weapons/mechloader.txt`, `modeldef.loader.txt`,
`hands.zs:486-695`, `CVARINFO.ae:148-209`, `docs/DESIGN_2026-10-23_power_loader.md`, `HANDOFF_2026-10-24.md`;
and from `presidentkoopa/RSQ_QuestEngineSurvey`: `03_MECHS.md`, `06_GRAB_INTERACTION.md`, `99_OVERLOOKED.md`,
`11_HUD_MODELS.md` headings. Nothing here is built. Every item is a proposal with a cost (S/M/L) and the
owner's yes is needed before any of it is touched (CLAUDE.md). Nothing was run.

## 1. What is right, and should not be touched

- Every decision that needs hand poses is local, sent as a **world point** (eighths, hand in the low bit, z shifted),
  and every machine runs the same search. No actor ids cross the wire, no RNG on any path. This is the correct
  netplay shape and the arc chain is the cleanest example (nearest-first, reach from the last link).
- **Carry is a velocity spring**, so pinning is free and nothing teleports through walls.
- **Reachability from the claw** on swing, ram, arc and crush. Paid for twice elsewhere; here from the start.
- Swing gates lifted from the BD22 axe lessons: speed AND travel AND not-rising AND empty claw AND rate limit.
- Token given/taken by the handler, not by Select/Deselect, so nothing is stranded by a death or a map change.
- `GetSpeedFactor()` on the token: the only slowdown that works on this engine, and `ae_loader_speed` is a
  **server** cvar for the right reason.
- Beacon `oldx` carried by hand; sounds `Say()`-ed at the claw, not the chest; `+CLIENTSIDEONLY` sparks.

## 2. Tighten (bugs and drift, in order of consequence)

### 2.1 The DECORATE still fights (S, but a decision)
`mechloader.txt` Fire still runs `A_CustomPunch(500, 0, …)` twice per cycle and AltHold runs three
`A_Explode(20, 256)` plus a DummyProjectile2, from the view line. `loader.zs` never suppresses them. On a VR
player a trigger press is therefore the TC's 500 face-punch AND the claw closing; alt fire is a 20-damage radius
blast AND a ram. The 10-24 rig table reports only the handler's numbers, so the harness did not go through the
weapon's states.
Options: (a) blank Fire/AltFire/AltHold in the DECORATE (`SAWG A 1; Goto Ready`) and accept that a non-VR player
has no attack in this VR pack; (b) keep them as the desktop fallback and have the handler strip `BT_ATTACK |
BT_ALTATTACK` from `cmd.buttons` for a VR player before the weapon's state runs (needs one check of WorldTick vs
PlayerThink order on 9afc750917). Either way **confirm first on the rig**: one press at a barrel, read the damage.

### 2.2 `+THRUACTORS` on the held thing kills the human shield and the battering ram (S)
`Take()` sets `bTHRUACTORS`. Hitscan's actor filter skips THRUACTORS (`p_map.cpp:4673-4700`, survey 06 line 66
and 308) and `PIT_CheckThing` lets movers through it, so a held monster stops no bullets, no projectiles, and
cannot be swung or rammed into another body. The survey's recipe keeps the held actor solid and uses `freezetics`
per tic. Dropping THRUACTORS costs one thing: a solid held body can block the player's own movement when it is
pulled into you. Suggest: keep it solid, and clamp the carry target to be at least `t.radius + mo.radius + 4`
from the pawn (cheap, in `Carry()`).

### 2.3 The claw point is not where the claw is drawn (M)
`ClawPoint()` = hand + 72 map units along the hand direction. The drawn `loader_arm_r.md3` claw, through the
same MODELDEF chain, sits about F 150-163 cm, L -80 cm, U -40..+20 cm from the controller (measured this
session with the kit). 72 map units at 34/m is 2.1 m straight ahead; the jaws you see are 1.6 m ahead and
0.8 m to the side. The hit point and the jaws disagree by nearly a metre. Fix: build the claw point from the
hand's full frame (forward from `AttackDir`, right from yaw, up from pitch) with the mesh's measured offset in
map units (F 158 cm -> 53.7, L 80 cm -> 27.2, U ~ -10 cm -> -2.8 after pixelstretch), mirrored for the off
hand. Then grab radius, swing radius and sparks all land on the mesh. Needs one headset look to confirm the
booms draw where the kit says.

### 2.4 Where the booms draw (needs eyes, then maybe M)
The arm meshes keep the operator-origin coordinates and are drawn with no hook, so each boom is 0.5-1.1 m
outboard of its controller. If your hands rest at your hips that is roughly where a P-5000's booms are, and it
may read right; if you hold the controllers in front of your chest the booms float a metre out either side.
The old single model had both arms around ONE hand, so nobody has seen this. If it is wrong the fix is a
hook on the two arm layers (`RSQ_Place.Layer` dispatch, the design's §3.3) pulling each boom's shoulder to a
point near the body; `ae_loader_arms 0` already falls back to the old single model.

### 2.5 Small things
- `F()` and `F2()` are the same function. ~40 `CVar.FindCVar` lookups per player per tic (each `F()` call is a
  hash lookup); cache the loader cvars once per tic into a struct. Matters on a Quest with 4 players.
- Dead fields: `handPrev[]` is written and never read (the pose history replaced it); `bodyStep` and
  `yawDelta` are computed and unused; `heldGrav` is fine. Comment drift at `work[]` (line 245: two comments
  on one line) and `flungWas` (line 264: "diagnostic: footsteps actually fired" belongs to `quakes[]`).
- `Arm()` sets `bAddBob = true` on the boom layers, `Cage()` sets it false: the booms bob with your walk
  while the cage does not. Probably wanted (arms are on your hands) but say so in the comment.
- `Select` runs `A_SetGravity(3)` on the player and `Deselect` restores 1. Triple gravity is the one
  DECORATE line that DOES take effect: shorter jumps, hard falls. Intended? It never appears in the cvars.
- `Stun()` holds `tics` but also `SetState(Pain)` on something already in Pain; harmless.
- `Rumble()` fires one `A_QuakeEx` per arc link in one tic; they stack into one 10 ms pulse. Fine, but the
  survey (99 §1a) notes `QuakePower` is noise in [-I, +I]; for a shaped envelope re-fire per tic.
- The flamer `FTFire` is spawned at the claw point with `vel = away * Speed`; if the TC's FTFire has a
  `Spawn` state with `A_Explode`-style self-timers it is fine, but its `target` is set after `Spawn` ran one
  tic? No: `Spawn()` then `f.target = mo` in the same tic before its first Tick. OK.

## 3. Expansion ideas (the Aliens power loader), costed

### Feel and presentation
1. **Hum and servo loop (S, needs one sound asset).** `ae_loader_hum` is 0 because the pack has no loop. One
   hydraulic idle plus a servo whine, pitched per arm by its measured speed, from TWO carried emitters (one
   per claw) instead of the single power-pack emitter. Everything else is already written.
2. **Getting in as a moment (S).** The design's step 9b, still open: ramp the ACS `LOADUP` view rise (41->61)
   over ~25 tics, play the arms from stowed (claw frames 20->15) over the same window, hum from zero, beacon
   from rest, one buzz on both hands at the latch. No new asset.
3. **Wrist gauge (S-M, survey 11 recipe).** A persistent layer above `PSP_TARGETCENTER` with an explicit
   caller rides the off hand through weapon switches: hydraulic pressure (ram/crush cooldown), cage integrity,
   a red lamp while something is held. The survey's working recipe is `11_HUD_MODELS.md` §4.1.
4. **Stomp damage (S).** Footsteps already fire per stride and alternate controllers; add a 24-unit crush
   under the pawn on each step for things under knee height (facehuggers, chestbursters, corpses). Playsim
   from `mo.vel`, no event needed.

### Mechanics
5. **Two-claw lift (M).** Both claws on one thing: raise the `Grabbable` mass cap to ~1400 when both hands
   send `ae_grab` at the same body within a window; carry target = midpoint of the two claw points; drop when
   either opens. Lets the loader lift a Praetorian or a heavy crate, and makes the second claw matter.
6. **Pin bonus (S).** The spring already pins. Detect "held body is being refused by geometry" (its pos stays
   >N units from the claw target for K tics while held) and double the crush bite: a monster crushed against
   a wall dies faster than one crushed in the air. The airlock scene.
7. **Held barrel as a weapon (S).** Swing is refused while holding (correct for a live body). Allow the RAM
   while holding an `ExplosiveBarrel`: the barrel is shoved out along the arm at ram speed, so you throw a
   lit barrel through a doorway with the alt fire rather than dropping it.
8. **Grab items (S).** `Grabbable()` excludes `MF_SPECIAL` things. Pulling an ammo crate to your chest and
   calling `Inventory.Touch(player)` when it arrives (survey 06 §4.1) lets you scavenge without taking the
   loader off.
9. **Boss clinch (L).** Boss grabs are excluded (mass > 700, +BOSS). A clinch mode for the Queen: the claw
   latches, both are locked, the squeeze becomes a rhythm (alternate triggers) against her struggle; break on
   failure, big damage and a knockback on success. Only worth it with a Queen to fight.
10. **Cage as a thing that wears (M).** Directional absorption (front and top 35%, rear 10%, below 0: it is a
    roll cage), a cage HP pool that drops per absorbed hit, sparks more as it goes, absorb falls to zero when
    spent, repaired by a medikit-like "hydraulics" pickup or by time. `A_ChangeModel` to a dented cage mesh
    is unverified from an EventHandler (design §7.12): one compile check first.
11. **Arc vs synthetics (S).** `Electric` damage is already its own type; give Synth/Working-Joe classes a
    `DamageFactor Electric 3.0` in the pack's DamageFactor table and the welding arc becomes the anti-android
    tool it should be. Data, no code.
12. **Torch sets things alight (S).** The torch already spawns the TC's `FTFire`. Add `Fire` damage factor on
    `ExplosiveBarrel` so a torched barrel cooks off, and a burning corpse ignites eggs. Data again.

### Netplay and the other player
13. **A co-op partner's loader has no arms (L, engine-bound).** Psprite layers are drawn only for the local
    player; another player wearing a loader is an invisible operator with a floating pickup model. The only
    stock-engine route is world actors re-posed at 35 Hz from that player's AttackPos/OffhandPos, which exist
    only on his machine, so it needs the hand poses on the wire (the `RSVR_HandNet` the design named and cut).
    Record it; do it on UZDXREMA where `FollowHandPlayer` is one engine change.

### The two the owner cut, recorded so nobody re-derives them
14. **Legs** (design §2.6): world actor under the waist, cadence from `mo.vel`, head offset unavailable so it
    sits at the pawn. **Body frame** (§3.7). Both still BUILDABLE, both still cut.

## 4. Order I would suggest, if asked
2.1 (rig, one press) -> 2.2 (one flag) -> 2.3 (claw point from the mesh) -> headset look at 2.4 -> then 1, 2, 4
for feel, then 5/6/7 for play. Everything below that is a conversation.
