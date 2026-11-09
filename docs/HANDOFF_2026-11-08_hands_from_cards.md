# Hands from the cards -- 2026-11-08

The gun hand and support hand of the pistols (M4A3, Merc, Synth, Yutani), the shotguns (NewShotgun, Yutani), the
pulse rifles (PulseRifle, Yutani) and the flamers (M240, Yutani) are now FITTED FROM THE CARDS by
`tools/fit_hands_cards.py`, and written into the three places the pack reads them from ONE result:
`zscript/rsq/handtable.zs` (GunHook / SupportHook; GunRot / SupportRot 0), `MODELDEF.aemain` (baked Offsets, the
main-gun dual path) and `MODELDEF.aedual` (through the pack's own `tools/gen_aedual_modeldef.py --write`).
Knife, satchel and smartgun rows are untouched (owner: the smartgun is done last, by hand).

How: RS_ModelSwapper beside this repo (`RSQ_TOOLS`), its `cards/aliens/<gun>` (measured grip line, measured pump /
support bar), the pack's own gun blocks (`modeldef.<gun>.txt`, the TC placement), Ermac's full hands
(`RSQ_ERMAC` = the RSQ_RustedLegacy build's `src/models`), the kit's ICP (`tools/kit/handfit_cards.py`), then:
the index finger of the pack's own TRIGGER FRAME (the one `add_hand_frame.py` bends; the game draws it at rest)
put on the card's trigger point; the owner's eye on each sheet recorded in the script (`GUN_NUDGE`, `SUPPORT_NUDGE`,
`GUN_PIN` for the shotgun, which he approved before the finger rule moved it). The flamer's grip is built from
its trigger lever the way the pulse rifle's measured grip sits to its trigger (the card's own grip guess was 30 cm
off); its support point is the shipped, approved one re-seated on the surface and lowered 4 cm.

Owner approved on the sheets (21:09-21:55): pulse rifle, shotgun, pistol, flamer. `docs/renders/fit/<class>.cards.png`
are the fitter's sheets; `tools/hand_survey.py` (the pack's own survey) agrees with them now that it draws the support
hand from hand2.md3 (RQSP letters -> frames 0/1/2) and the gun at its Ready frame -- it had drawn hand.md3's gun pose
for the support hand, so its renders were reporting their own error.

Not done: a rig run and the headset (no engine in this session; `tools/check.sh` needs the TC). The GL-pump
secondary fire (owner: "ideally we can pump the secondary fire"): the support hand is on the launcher's action and the
card has its 14.2 cm stroke; same shape as the shotgun pump reload. The smartgun (owner 21:03: "off hand grip is a
bicycle handlebar halfway up on left side, main hand grip is a vertical cylinder on the right side about half way up").
Re-run: `RSQ_TOOLS=... RSQ_ERMAC=... python3 -B tools/fit_hands_cards.py --write` -- never hand-edit the table again.

## 22:30 Smartgun, by hand (`tools/fit_smartgun.py`)
Rows 8 and 16. The shipped row had the gun hand on the far rear bar (F -55) and the support above-right of the drum.
Owner (22:30 screenshot, boxed the knob): the main hand is the VERTICAL BAR on the right side of the receiver behind the
drum; the support is the handlebar out to the left, forward of the drum. Main = Ermac F (106) at (F 0, L -7.3, U -4.5),
rot 0: GunHook (-4.950, 2.239, -1.328). Support = Ermac C (hand2 91) at (F 28.5, L 13, U 5.2), SupportRot (0,0,90) so the
bar runs through the fist knuckles-up (roll -90 was looked at: fist under the bar, palm up, rejected): SupportHook
(9.561, -14.484, -0.920). `tools/hand_survey.py Smartgun_3D` (live table, independent chain) matches the fitter's
sheet `docs/renders/fit/Smartgun_3D.cards.png`. Written, not rig-verified. Dual blocks untouched (none for smartguns).
