# The pulse rifle's LED ammo counter is dead: layer 2130 has two owners

Found 2026-11-09, owner's report ("what happened to the animated ammo readout on the
pulserifle"). Not yet fixed. Nothing is missing from the pack -- the readout is being
drawn over.

## What is wrong

Two systems were given the same psprite layer:

| | layer | file |
|---|---|---|
| pulse rifle LED ammo counter | `RSQ_Layers.COUNTER = 2130` | `zscript/rsq/hands.zs:237` |
| M41A underbarrel launcher pump | `RSQ_PumpGL.LAYER = 2130` | `zscript/rsq/pumpgl.zs:27` |

A psprite layer is one slot per player, so the two cannot both hold it. They clash on
exactly the guns the counter is for and on no others: `RSQ_PumpGL.Index()`
(`pumpgl.zs:47-48`) returns non-zero only for `PulseRifle_3D` and `YutaniRifle_3D`, and
those are the two guns `RSQ_Counter.Tick` draws a counter for (`counter.zs:12-14`).

It is not intermittent. `pumpgl.zs:139` is

    RSR.SetPart(p, LAYER, parts, on && gi > 0, SprPart(gi), 0);

and `Show()` is called with `on = true` hardcoded (`pumpgl.zs:126`), so the pump holds
2130 every tic the rifle is in hand, not only during a stroke. The counter is overwritten
continuously. There is also no on/off cvar for the pump -- `CVARINFO.ae:138-145` declares
only `ae_glpump_cost`, `ae_glpump_grab` and `ae_glpump_travel` -- so there is nothing the
owner can switch off to get the readout back.

## When it broke

Both were written 2026-10-22, and the counter worked that day. `pumpgl.zs`'s own header
records what changed the next day:

> 2026-10-23 THE PUMP IS NOW A PART, NOT AN ANIMATION (parity step 4). This used to create
> no psprite layer at all.

While the pump claimed no layer, 2130 was the counter's alone. Turning the pump into a
real part that draws on its own layer took the number the counter already had. The clash
has been there since.

## What is NOT wrong (checked 2026-11-09, so nobody re-checks it)

- `counter.zs` is included -- `ZSCRIPT.ae:9`.
- It is called -- `hands.zs:726`, `RSQ_Counter.Tick(p, mo, dual ? null : side)`.
- `RSQ_GunSide` carries all 100 states `Cnt00`..`Cnt99` (`hands.zs:254-353`).
- `MODELDEF.ae` has all 100 one-block-per-value bindings, keyed `RSC0`..`RSC3`, which do
  not collide with the hand's `RQGS`/`RQSP` keys on the same actor.
- `counter.md3` and all 100 `models/weapons/rifle/counter/cNN.png` are in
  `pk3/AliensVR_Weapons.pk3`.
- The ammo classes are right: `PulseLoaded` / `YPulseLoaded`, magazine capacity 95
  (`actors/weapons/rifle.txt:121,271`), and the counter's clamp to 99 is above that.
- The 2026-11-08 hand re-fit (`32fe9d3`) touched `MODELDEF.aemain` and `MODELDEF.aedual`
  only, not `MODELDEF.ae`, so it did not move the counter quad.
- The `dual ? null : side` guard is correct and is not the cause: the only classes carrying
  `+WEAPON.OFFHANDWEAPON` are `RSQ_Hands` (`hands.zs:446`) and the ten dual copies in
  `DECORATE.aedual`, so `dual` (`hands.zs:603`) is true only with a real second gun.

## The fix, when it is taken

Move `COUNTER` off 2130; the pump's number is referenced in its own file and in the layer
inventory comment, the counter's is not. 2110 is free. The bands in use on the main
controller are 2100/2101 (GunSide hands), 2102-2104 (`vreload` WELLMAG/HANDLE/BOLT),
2120-2123 (`rsr_pump`), 2130 (contested); off-controller is 2200/2201/2202/2203/2210 and
the loader has 2300.

2110 needs no other change: `hands.zs:130` tests against the constant rather than the
literal, and 2110 falls outside both range loops (`vreload` `LAYER_FIRST/LAST` 2102-2104,
`rsr_pump` 2120-2123).

One thing to correct while there: the layer inventory comment at `loader.zs:45` lists 2130
once. It had two owners when that line was written, which is how this survived.

Then prove it on the rig before it goes to a headset -- a layer number is cheap to get
wrong twice. The readout should count down from 95 as the rifle fires and jump back up on
the seat of a reload.
