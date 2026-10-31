# Aliens VR Weapons (Quest)

VR weapons for **Aliens: Eradication** on stock **QuestZDoom 17.3**: your hands on every gun, reloads done by hand, dual
wield, body holsters, a gimballed M56 Smartgun, and a P-5000 Power Loader you wear and fight with. No engine changes:
everything is ZScript, DECORATE, MODELDEF and data.

## Install

Load, in this order:

1. `_A01_ALIENS_ERADICATION_TC_2_0.pk3`
2. `_A02_ERADICATION_MAPSET_2_0.wad`
3. **`pk3/AliensVR_Weapons.pk3`** (this pack)

This pack **replaces** `_A03_AliensEradication_VR_addon_v1.0.pk3`: it is that addon with the VR work merged in. Do not
load `_A03` as well. Options are under **Options → Aliens VR Weapons**; the dual-wield key is under
**Customize Controls → Aliens VR Weapons**.

## Guns

- **Hands on every weapon.** VR hands on all 16 weapon classes, trigger finger on the 12 guns, left-handed supported.
- **Reload by hand.** Pull the empty magazine, take a fresh one, seat it along the magazine well, and rack the slide
  or handle when the gun was shot dry. Works on the M4A3, Merc, Synth and Yutani pistols, the M41A pulse rifle and the
  Yutani rifle.
- **Pump shotgun.** The M37A2 takes its shells one at a time, pushed into the port by hand. Slug alt fire.
- **Flick down to reload** as a shortcut.
- **Dual wield** pistols, shotgun, pulse rifle and flamer: each hand keeps its own magazine, both draw from one
  reserve.
- **Body holsters**: seven weapon slots, seven places on your body to reach for.
- **M56 Smartgun**: its lock-on restored (A03 had it bypassed), a harness gimbal that swings the gun onto a target
  while your hands stay put, and a fire selector on the receiver.
- **Knife and fist.**
  - The knife cuts with a thrust or a slash. Its damage is 1.3× the fist's.
  - The free off hand punches only on a real punch: fast, mostly forward of your body, a real jab distance, and
    ending in front of you.

## The P-5000 Power Loader

Wear it and your arms are its arms. It is heavy: you walk at 0.35 speed, and every footstep rumbles the controllers in
turn, left and right.

| Arm | Input | What it does |
|---|---|---|
| Either | swing it into something | **100 damage**, knocks it aside and stuns it |
| Main | trigger | close the claw: grab a monster or object and carry it |
| Main | trigger, held | **crush**: kills anything up to an imp in one squeeze; bigger things take a longer hold, one imp's worth of damage per squeeze |
| Main | alt fire, holding something | **throw** it; it hurts whatever it hits, harder the faster it flew |
| Main | alt fire, empty claw | **ram**: 60 damage and a hard shove |
| Off | trigger | **electric arc** that chains between targets |
| Off | alt fire | **welding torch** (the TC's own fire) |

- **Grabbing.** A held monster freezes in its pain frame. A wall stops what you carry instead of letting it pass
  through. Nothing hits through walls: the swing, the ram, the arc and the crush all check line of sight.
- **The cage.** Its frame takes part of every hit: 30 damage dealt, 20 taken.
- **Hit feel.**
  - Struck enemies freeze for a few tics: about 3 for light hits, 6 for heavy.
  - The controller of the arm that hit rumbles.
  - Arm sounds come from the claw, and the hum (off by default) from the machine, not from inside your chest.
- **Motion tracking.** Swings and punches are measured in your body's own frame, so turning or snap-turning never
  counts as a swing. A swing must be fast, travel a real distance, and not be rising.

## Status

Shown on the Linux QuestZDoom 17.3 rig with the repo's behaviour harness (`tools/rtest/`), fake VR hands, on the TC
2.0, 0 script errors or VM aborts:

- all six magazine guns reload 8/8 and refill from the reserve
- the shotgun takes 8 shells one at a time
- the loader:
  - grab, hold and crush an imp
  - crush a revenant in 60-damage squeezes
  - swing into a revenant: 100 damage, knocked 20 units aside, stunned 35 tics
  - throw a barrel: 168 damage on impact
  - ram: 60 damage plus a shove
  - arc: 3 × 26 on an imp
  - cage: 30 dealt, 20 taken

**Rig only, not headset-confirmed.** Not yet exercised on the rig: the new fist punch and the knife damage (no harness
script for them), the per-arm rumble and footsteps (the rig has no controllers to feel), and the hum emitter.

## Tuning

Every number above is a slider or cvar in the options menu. They are not tuned yet, and they will be set from the
source mod's own data.

## For developers

- `tools/rtest/`: the behaviour harness. `suite.py` runs every magazine gun; `run.py` drives one scripted run.
  Loader scripts are in `loader_test.zs` (`aet_loader 1`–`9`).
  - On Linux, set `AET_ENG=/path/to/rig`, `AET_TC=<the TC pk3>` and `AET_IWAD=<doom2.wad>`.
  - `AET_MAPSET` is optional; without it the run uses doom2 MAP01 and steps off its starting ledge.
- `tools/mkpk3.py . pk3/AliensVR_Weapons.pk3` builds the pack.
- Design notes and handoffs are in `docs/`.
