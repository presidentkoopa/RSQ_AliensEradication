// TEST ONLY (2026-11-08): the power loader's batch check on the ModelSwapper rig -- the real
// QuestZDoom 17.3 Linux build on the OpenXR path, controllers posed from cvars. This handler is
// loaded as an overlay pk3 AFTER the pack (tools/rig/aerig_run.py builds it). It does three things:
//   1. drives the controllers through the rig's qzt_* hook (a pack-defined cvar replaces the
//      rig's qz_* one when set: qzt_rhand "x y z pitch yaw roll" in stage metres, qzt_rtrigger
//      0..1, qzt_rgrip, qzt_ltrigger). With vr_secondary_button_mappings (the ini default) the
//      right grip is a SHIFT: trigger alone = +attack (claw), grip+trigger = +altattack (fling /
//      ram), left trigger alone = +oh_attack (arc), grip + left trigger = +oh_altatk (torch).
//      (VrInputDefault.cpp 338-381, 413-454 at the rig's questzdoom revision.)
//   2. spawns stock Doom subjects where the loader's OWN ClawPoint() says the jaws are and
//      presses the buttons, phase by phase, on maptime.
//   3. logs AERIG lines: layers, cab actor vs pawn, claw points, gravity, speed factor, every
//      ae_* net event, each subject's health per tic while a phase runs.
// Nothing here is the pack. Phases (maptime):
//   100  give + select Loader_3D, god (console), ae_loader_debug 1
//   200  SWING: an Imp at the main claw point, a 6-tic lateral sweep of the right hand (15 cm/tic)
//   330  NO DECORATE PUNCH: an Imp dead ahead on the view line at 64 units, trigger pressed 10 tics
//        with nothing at the claw: its health must not move (the old A_CustomPunch(500) would kill it)
//   460  GRAB + CRUSH: a Demon at the claw, trigger held 60 tics: grab at ~7, bites every 12
//   620  GRAB + FLING: a barrel at the claw, trigger, then grip after the grab: it must fly
//   760  RAM: an Imp at the claw, grip + trigger press with an empty claw
//   880  ARC: a Demon at the OFF claw point, left trigger held 30 tics
//  1000  TORCH: grip + left trigger held 30 tics, FTFire count
//  1120  CAGE: god off, 30 damage, god on: health must drop by 20 (int(30 * 0.35) absorbed)
//  1200  (console) a snap turn: qz_rstick "1 0" for 3 tics -- the cab must turn by the snap
//  1300  look up at the cab (console qz_hmd pitch) for the frame dump, then quit
class AET_Rig : EventHandler
{
	Actor subject;
	int phase;
	int tPhase;
	int grabbedAt;
	int events;
	String last;

	static void Cv(Name n, double v)
	{
		let c = CVar.FindCVar(n);
		if (c) c.SetFloat(v);
	}
	static void Cs(Name n, String s)
	{
		let c = CVar.FindCVar(n);
		if (c) c.SetString(s);
	}
	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}
	static int Cnt(Class<Actor> c)
	{
		int n = 0;
		if (!c) return -1;
		ThinkerIterator it = ThinkerIterator.Create(c);
		Actor a;
		while (a = Actor(it.Next()))
			n++;
		return n;
	}
	static Class<Actor> FT() { Class<Actor> c = 'FTFire'; return c; }
	static String Cls(Object o) { return o ? String.Format("%s", o.GetClassName()) : "none"; }
	static String V(Vector3 v) { return String.Format("(%.1f %.1f %.1f)", v.x, v.y, v.z); }

	// the right hand at rest: the rig's default pose, as a string the glue parses
	static String RHand(double x, double y, double z) { return String.Format("%.3f %.3f %.3f 30 0 0", x, y, z); }

	void Say(String s)
	{
		Console.Printf("AERIG t%d %s", level.maptime, s);
	}

	Actor Put(Class<Actor> cls, Vector3 at, String why)
	{
		let a = Actor.Spawn(cls, at, ALLOW_REPLACE);
		if (a)
		{
			a.angle = players[0].mo.angle + 180;	// facing us
			Say(String.Format("SPAWN %s at %s for %s (health %d, mass %d)", a.GetClassName(), V(at), why, a.health, a.Mass));
		}
		else
			Say("SPAWN FAILED " .. cls.GetClassName());
		return a;
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		String en = e.Name;
		if (en.Left(3) == "ae_")
		{
			events++;
			Say(String.Format("EVENT %s args %d %d %d (hand %d)", e.Name, e.Args[0], e.Args[1], e.Args[2],
			    e.Name == "ae_crush" ? e.Args[0] : (e.Args[2] & 1)));
		}
	}

	override void WorldTick()
	{
		if (!playeringame[0] || !players[0].mo) return;
		let mo = PlayerPawn(players[0].mo);
		let p = mo.player;
		int t = level.maptime;
		let H = AE_LoaderHandler(EventHandler.Find('AE_LoaderHandler'));
		bool worn = AE_LoaderHandler.Worn(mo);
		let tok = mo.FindInventory('AE_LoaderWorn');

		// ---- the standing report, once a second ----
		if (t % 35 == 0)
		{
			let arm = p.FindPSprite(AE_LoaderLayers.ARM_MAIN);
			let fh = p.FindPSprite(RSQ_Layers.FREEHAND);
			String cab = "none", lamp = "none";
			if (H && H.cab[0])
			{
				Vector3 d = H.cab[0].pos - mo.pos;
				cab = String.Format("d=%s yaw %.0f (pawn angle %.0f, off %.0f) floorz+%.1f", V(d), H.cab[0].angle, mo.angle,
				      Actor.deltaangle(H.cab[0].angle, mo.angle), H.cab[0].pos.z - mo.floorz);
			}
			if (H && H.lamp[0])
				lamp = String.Format("d=%s angle %.0f", V(H.lamp[0].pos - mo.pos), H.lamp[0].angle);
			Say(String.Format("STATE ready=%s worn=%d invr=%d token=%d speedfactor=%.2f gravity=%.2f viewheight=%.1f health=%d",
				Cls(p.ReadyWeapon), worn, RSVR_VRHand.InVR(mo), tok ? 1 : 0,
				tok ? tok.GetSpeedFactor() : -1.0, mo.Gravity, p.viewheight, mo.health));
			Say(String.Format("LAYERS armMain=%s caller=%s frame=%d bob=%d | freehand=%s armL=%d frame=%d bob=%d | oldgun alpha=%.2f",
				arm ? "yes" : "NO", Cls(arm ? arm.Caller : null), arm ? arm.Frame : -1, arm ? arm.bAddBob : -1,
				fh ? "yes" : "NO", fh ? (fh.Sprite == Actor.GetSpriteIndex('AEAL')) : 0, fh ? fh.Frame : -1, fh ? fh.bAddBob : -1,
				p.FindPSprite(PSP_WEAPON) ? p.FindPSprite(PSP_WEAPON).alpha : -1.0));
			Say("CAB " .. cab .. " | LAMP " .. lamp);
			if (worn && RSVR_VRHand.InVR(mo))
			{
				Vector3 cm = AE_LoaderHandler.ClawPoint(mo, false), co = AE_LoaderHandler.ClawPoint(mo, true);
				Say(String.Format("CLAW main=%s (from hand %s, %.1f units) off=%s (from offhand %s, %.1f units) hands apart %.1f",
					V(cm), V(cm - mo.AttackPos), (cm - mo.AttackPos).Length(), V(co), V(co - mo.OffhandPos), (co - mo.OffhandPos).Length(),
					(mo.AttackPos - mo.OffhandPos).Length()));
			}
		}

		// ---- phase 0: wear it ----
		if (t == 100)
		{
			Class<Inventory> lc = 'Loader_3D';		// the TC's DECORATE class: a runtime lookup, unknown at compile time
			if (lc) mo.GiveInventory(lc, 1);
			let w = lc ? Weapon(mo.FindInventory(lc)) : null;
			if (w) p.PendingWeapon = w;
			Say(w ? "GIVE Loader_3D, selecting" : "GIVE Loader_3D FAILED");
			Cv('ae_loader_debug', 1);
			Cs('qzt_rhand', RHand(0.25, 1.3, -0.3));
			Cs('qzt_lhand', "-0.25 1.3 -0.3 30 0 0");
		}
		if (!worn || !H) return;

		// the TC replaces the stock roster with spawners (EnemySpawner4 -> an alien, Itemspawner16 ->
		// FuelBarrel), so the thing the claw takes is not the thing we spawned: follow what is HELD
		if (H.held[0] && subject != H.held[0] && (phase == 3 || phase == 4)) { subject = H.held[0]; Say("SUBJECT is now the held " .. Cls(subject)); }
		// subject health, every tic while a phase runs
		if (subject && t - tPhase < 160)
		{
			String hn = Cls(H.held[0]);
			String s = String.Format("SUBJ %s health=%d pos=%s vel=%.1f pain=%d solid=%d thru=%d held=%s",
				subject.GetClassName(), subject.health, V(subject.pos), subject.vel.Length(),
				subject.InStateSequence(subject.CurState, subject.FindState('Pain')), subject.bSOLID, subject.bTHRUACTORS, hn);
			if (s != last) { Say(s); last = s; }
		}

		// ---- 200 SWING ----
		if (t == 200)
		{
			phase = 1; tPhase = t;
			subject = Put('DoomImp', AE_LoaderHandler.ClawPoint(mo, false), "SWING");
			Say(String.Format("SWING cvars swing=%.0f len=%.0f gap=%.0f down=%.2f", F('ae_loader_swing', -1), F('ae_loader_swing_len', -1), F('ae_loader_swing_gap', -1), F('ae_loader_swing_down', -1)));
		}
		if (t >= 215 && t <= 221)
		{
			// right hand sweeps left across the body, 15 cm a tic, level, 6 tics: 90 cm
			double x = 0.25 - 0.15 * (t - 215);
			Cs('qzt_rhand', RHand(x, 1.3, -0.3));
			let pose = RSVR_Pose.Get();
			double sp = (pose && pose.Delta(mo, 0, 1)) ? pose.dStep.Length() / (pose.dSecs * 35.0) : -1;
			Say(String.Format("SWEEP hand x=%.2f AttackPos=%s speed=%.1f cm/tic travel3=%.1f", x, V(mo.AttackPos), sp, pose ? pose.Travel(mo, 0, 3) : -1));
		}
		if (t == 240) { Cs('qzt_rhand', RHand(0.25, 1.3, -0.3)); Say("SWEEP back to rest"); }

		// ---- 330 NO DECORATE PUNCH ----
		if (t == 330)
		{
			phase = 2; tPhase = t;
			Vector3 ahead = mo.Vec3Angle(64, mo.angle, 0);
			ahead.z = mo.floorz;
			subject = Put('DoomImp', ahead, "NO-PUNCH (dead ahead on the view line; the old DECORATE A_CustomPunch(500) would kill it)");
			Cv('qzt_rtrigger', 1);
			Say("TRIGGER down (claw, nothing at the claw point)");
		}
		if (t == 340) { Cv('qzt_rtrigger', 0); Say("TRIGGER up"); }
		if (t == 350 && subject) Say(String.Format("NO-PUNCH RESULT imp health=%d (60 = untouched, PASS)", subject.health));

		// ---- 460 GRAB + CRUSH ----
		if (t == 460)
		{
			phase = 3; tPhase = t;
			subject = Put('Demon', AE_LoaderHandler.ClawPoint(mo, false), "GRAB+CRUSH");
			Say(String.Format("CRUSH cvars claw_tics=%.0f crush_tics=%.0f damage=%.0f grab_radius=%.0f", F('ae_loader_claw_tics', -1), F('ae_loader_crush_tics', -1), F('ae_loader_crush_damage', -1), F('ae_loader_grab_radius', -1)));
			Cv('qzt_rtrigger', 1); Say("TRIGGER down (hold 70)");
		}
		if (phase == 3 && t > 460 && t <= 540 && H.held[0] && grabbedAt == 0) { grabbedAt = t; Say(String.Format("HELD %s after %d tics", H.held[0].GetClassName(), t - 460)); }
		if (t == 540) { Cv('qzt_rtrigger', 0); Say(String.Format("TRIGGER up; held=%s subject alive=%d", H.held[0] ? "yes" : "no", subject && subject.health > 0)); grabbedAt = 0; }

		// ---- 620 GRAB + FLING ----
		if (t == 620)
		{
			phase = 4; tPhase = t;
			subject = Put('ExplosiveBarrel', AE_LoaderHandler.ClawPoint(mo, false), "GRAB+FLING");
			Cv('qzt_rtrigger', 1); Say("TRIGGER down");
		}
		if (phase == 4 && t > 620 && t < 660 && H.held[0] && grabbedAt == 0) { grabbedAt = t; Say(String.Format("HELD %s after %d tics; GRIP down now (grip + trigger = alt fire = fling)", H.held[0].GetClassName(), t - 620)); Cv('qzt_rgrip', 1); }
		if (phase == 4 && grabbedAt > 0 && t == grabbedAt + 6) { Cv('qzt_rgrip', 0); Cv('qzt_rtrigger', 0); Say(String.Format("GRIP+TRIGGER up; held=%s barrel vel=%.1f pos=%s", H.held[0] ? "yes" : "no", subject ? subject.vel.Length() : -1, subject ? V(subject.pos) : "-")); grabbedAt = 0; }

		if (phase == 4 && (t == 645 || t == 660 || t == 700) && subject)
			Say(String.Format("FLUNG %s health=%d pos=%s vel=%.1f (from claw %s)", Cls(subject), subject.health, V(subject.pos), subject.vel.Length(), V(AE_LoaderHandler.ClawPoint(mo, false))));

		// ---- 760 RAM ----
		if (t == 760)
		{
			phase = 5; tPhase = t;
			subject = Put('DoomImp', AE_LoaderHandler.ClawPoint(mo, false), "RAM (empty claw, grip + trigger)");
			Cv('qzt_rgrip', 1);
		}
		if (t == 762) { Cv('qzt_rtrigger', 1); Say("GRIP held, TRIGGER down (alt fire)"); }
		if (t == 768 || t == 790)
		{
			if (t == 768) { Cv('qzt_rtrigger', 0); Cv('qzt_rgrip', 0); }
			Vector3 cp = AE_LoaderHandler.ClawPoint(mo, false);
			let it = BlockThingsIterator.CreateFromPos(cp.x, cp.y, cp.z, 0, 160, false);
			while (it.Next())
			{
				let a = it.thing;
				if (a && a != mo && a.bSHOOTABLE && !a.bNOTARGET)
					Say(String.Format("RAM t%d near claw: %s health=%d/%d vel=%.1f dist=%.0f", t, Cls(a), a.health, a.SpawnHealth(), a.vel.Length(), (a.pos - cp).Length()));
			}
		}

		// ---- 880 ARC ----
		if (t == 880)
		{
			phase = 6; tPhase = t;
			subject = Put('Demon', AE_LoaderHandler.ClawPoint(mo, true), "ARC (off claw)");
			Cv('qzt_ltrigger', 1); Say(String.Format("LEFT TRIGGER down 30 tics; sparks now %d", Cnt('AE_LoaderCageSpark')));
		}
		if (t == 910)
		{
			Cv('qzt_ltrigger', 0);
			Vector3 cp = AE_LoaderHandler.ClawPoint(mo, true);
			let it = BlockThingsIterator.CreateFromPos(cp.x, cp.y, cp.z, 0, 160, false);
			while (it.Next())
			{
				let a = it.thing;
				if (a && a != mo && a.bSHOOTABLE && !a.bNOTARGET)
					Say(String.Format("ARC near off claw: %s health=%d/%d (26 Electric per strike, 5 strikes) dist=%.0f", Cls(a), a.health, a.SpawnHealth(), (a.pos - cp).Length()));
			}
			Say(String.Format("LEFT TRIGGER up; sparks alive=%d", Cnt('AE_LoaderCageSpark')));
		}

		// ---- 1000 TORCH ----
		if (t == 1000)
		{
			phase = 7; tPhase = t;
			Cv('qzt_rgrip', 1);
		}
		if (t == 1002) { Cv('qzt_ltrigger', 1); Say(String.Format("GRIP + LEFT TRIGGER down 30 tics; FTFire now %d", Cnt(FT()))); }
		if (t == 1032) { Cv('qzt_ltrigger', 0); Cv('qzt_rgrip', 0); Say(String.Format("TORCH released; FTFire=%d (3-tic rate: ~10 expected)", Cnt(FT()))); }

		// ---- 1120 CAGE ----
		if (t == 1120)
		{
			phase = 8; tPhase = t;
			int before = mo.health;
			p.cheats &= ~CF_GODMODE;
			mo.DamageMobj(null, null, 30, 'Normal');
			p.cheats |= CF_GODMODE;
			let arm = mo.FindInventory('BasicArmor');
			Say(String.Format("CAGE 30 damage: health %d -> %d (cage takes int(30 * %.2f) = %d; pawn DamageFactor=%.2f armor=%d/%s: the TC's LOADUP may already reduce damage) sparks=%d",
				before, mo.health, F('ae_loader_cage_absorb', -1), int(30 * F('ae_loader_cage_absorb', 0)), mo.DamageFactor, arm ? arm.Amount : 0, arm ? Cls(arm) : "none", Cnt('AE_LoaderCageSpark')));
		}

		if (t == 1199) Say(String.Format("SNAP before: pawn angle %.1f cab yaw %.1f", mo.angle, H.cab[0] ? H.cab[0].angle : -1));
		if (t == 1215) Say(String.Format("SNAP after: pawn angle %.1f cab yaw %.1f (must have turned together)", mo.angle, H.cab[0] ? H.cab[0].angle : -1));
		if (t == 1400) Say(String.Format("END events=%d", events));
	}
}
