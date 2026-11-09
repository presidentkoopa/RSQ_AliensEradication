# Power Loader: tightened and run on the rig (2026-11-08, 23:19-00:10)

Owner: "you have autonomy to upgrade and tighten our PowerLoader in accordance with what the engine
teardown allows" / "you are authorized to do an Aliens batch check of things". The list was
`docs/REVIEW_2026-11-08_power_loader.md` (§2 tighten, §5 VR fit). Done, and RUN, on the ModelSwapper rig:
the real QuestZDoom 17.3 Linux build (`RS_ModelSwapper/tools/rig/bin/qz`, PINS 9afc750), OpenXR path,
controllers posed from cvars, `doom2.wad -> _A01 TC -> this pack -> tools/rig/aerig overlay`, MAP01, god.
Four runs (`tools/rig/runs/loader_batch*.log`, gitignored); the fourth is the one below. NOT headset-confirmed.

## What changed (zscript/ae/loader.zs, mechloader.txt, modeldef.loader.txt, CVARINFO.ae, MENUDEF.ae)
1. **The cab is two world actors** (`AE_LoaderCab`, `AE_LoaderLamp`), placed every tic at the pawn by
   `AE_LoaderHandler.PlaceCab`: the TacticalRig helmet/torso pattern. Floor-anchored (`ae_loader_cab_height`
   1.8 m; 1.5 put the roof grate AT the eyes on the rig), `ae_loader_cab_back` 0.25 m behind the pawn
   (the cage mesh's origin is its rear edge: at 0 the rear member went through the head), its own yaw
   (snap turns carry it exactly; walking or a 45-degree look held 1.5 s eases it round at
   `ae_loader_cab_turn` deg/tic; never a glance). Pure playsim: every machine sees every cab. The
   psprite layers 2304/2305 and the AE_LoaderWorn Beacon/Cage states are gone.
2. **Claw point from the mesh**: `ClawPoint()` = hand + (F 152, L -106 | +126, U -5) cm in the hand's
   HandDir/OffDir frame, measured from loader_arm_r/l.md3 through their MODELDEF blocks with the kit.
   `ae_loader_claw_mesh 0` gives the old 72-unit reach back; `ae_loader_claw_scale`; `ae_loader_debug 1`
   sparks both claw points every 7 tics for the headset.
3. **Held things stay solid** (no `bTHRUACTORS`): hitscan skips THRUACTORS, so the human shield and the
   ram-with-a-body are back. `Carry()` keeps the target off the pawn (both radii + 8).
4. **The DECORATE no longer attacks**: Fire/AltFire/AltHold in mechloader.txt are `SAWG A 1; Goto Ready`
   (both loaders). The old A_CustomPunch(500) x2 and A_Explode(20,256) x3 ran on top of the claw and ram.
5. **Gravity is the token's**: `ae_loader_gravity` (server, 1.0) in `AE_LoaderWorn.DoEffect`; Select's
   `A_SetGravity(3)` and the dead `A_SetSpeed` lines removed. Restored in `DetachFromOwner`.
6. Footstep quakes skipped while `r_quakeintensity > 0`; boom layers `bAddBob false` (the left one each
   tic, since hands.zs SetLayer turns it on); `handPrev/bodyPrev/yawPrev/hadPose` and `F2()` gone; two
   comments un-drifted; `cab[]`/`Cab()` clash caught by the rig compile and renamed `PlaceCab`.
7. **Found on the rig and fixed**: both arms "swung" the moment the loader came up (the TC's LOADUP lifts
   viewheight 41 -> 61: a 70 cm jump in the pawn's frame) and on every snap turn (angle and hand poses
   land a tic apart) -- `turnQuiet` 6 tics after a 20+ degree jump or a viewheight jump, `wornFor` < 10
   quiet. A shut empty claw sent `ae_grab` EVERY TIC to every machine -- now every 5 (`grabQuiet`).

## Rig evidence (loader_batch4.log, AERIG lines; the harness is tools/rig/aerig.zs + aerig_run.py)
```
t140 STATE ready=Loader_3D worn=1 invr=1 token=1 speedfactor=0.35 gravity=1.00 viewheight=61.0 health=100
t140 LAYERS armMain=yes caller=AE_LoaderArms frame=0 bob=0 | freehand=yes armL=1 frame=0 bob=0 | oldgun alpha=0.00
t140 CAB d=(0.0 -8.5 51.0) yaw 90 (pawn angle 90, off 0) floorz+51.0 | LAMP d=(0.0 -8.5 51.0) angle -121
t140 CLAW main=(-51.5 845.9 111.4) (from hand (36.0 51.7 -1.4), 63.0 units) off=... (from offhand (42.8 51.7 -1.4), 67.1 units)
      -> 152 cm fwd = 51.7 units, 106 cm right = 36.0, -5 cm = -1.4: the mesh offsets, in map units
t221 EVENT ae_claw (hand 0)          the 15 cm/tic lateral sweep; no swing at select (t127 in runs 1-2) and none on the snap
t471 HELD XenomorphBambiAT after 11 tics   (run 2: XenomorphAT 140 pulled to the claw, vel 11 -> 0, solid=1 thru=0)
t484 EVENT ae_crush  t495 EVENT ae_crush   (run 2: 140 -> 80 -> 20 -> gibbed: 60 a bite, every 12 tics)
t629 HELD FuelBarrel after 9 tics; GRIP down     t634 ae_drop (19.8 27.6 33.9) -> vel 48, wall at t640, health -83 (TickFlung impact)
t768 RAM near claw: XenomorphAT health=80/140 vel=28.5 dist=10   (run 3: 60 damage + the shove)
t910 ARC near off claw: XenomorphAT 140 -> 62, XenomorphBambiAT 80 -> 54   (5 strikes in 30 tics, chain)
t1032 TORCH released; FTFire=7
t1120 CAGE 30 damage: health 100 -> 80 (run 3, armor 0): int(30 * 0.35) = 10 absorbed.  Run 4 had 84 armor: 100 -> 96.
t1199/1215 SNAP: pawn angle 90 -> 45, cab yaw 90 -> 45, together; cab d=(-6,-6) = 0.25 m behind along the new heading
```
No script errors, no VM aborts in any run. Frames (`runs/loader_batch4/f*.ppm`): the cab's struts and roof
grate around the view, steady; after the snap, turned with the player.

## Rig facts worth keeping
- Buttons on the rig (= QuestZDoom with `vr_secondary_button_mappings`, VrInputDefault.cpp 338-454): right
  trigger alone = +attack (claw); right GRIP + trigger = +altattack (fling / ram); left trigger = +oh_attack
  (arc); right grip + LEFT trigger = +oh_altatk (torch); left grip alone = +speed. So the player FLINGS
  and RAMS with grip + trigger, and the torch is grip + left trigger. The off grip within 0.5 m is still
  the engine's two-hand steady; the loader never asks for it.
- The TC replaces the stock roster: `summon DoomImp` is an EnemySpawner that becomes a Xenomorph; a barrel
  is an Itemspawner that becomes a FuelBarrel. The harness follows what the claw HELD, not what it spawned.
- The rig engine reads and writes `bin/config/qzdoom.ini` relative to its cwd and ignores `-config`;
  aerig_run.py restores it from git before and after a run (a saved cab_height came back once).
- A held TC alien did not read as `InStateSequence(Pain)` though it stopped fighting; the TC's Pain
  label may chain. Not chased.
- A green counter box sits in the view through the loader on every frame (the smartgun's counter layer,
  or the TC's HUD?). Not the loader's; not chased.

## For the headset
`ae_loader_debug 1` sparks the two claw points: they must sit in the drawn jaws. The cab: height 1.8 m,
0.25 m back, central front post in the view (the mesh's), roof grate a head above the eyes -- three
sliders in Options > Aliens VR > Power Loader. The left boom's side: if it draws on the RIGHT, the
engine's off-hand mirror flipped it and the fix is `Scale 1 1 1` on the RSQ_Hands loader_arm_l block.
