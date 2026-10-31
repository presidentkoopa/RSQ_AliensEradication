// TEST ONLY: drives the power loader and reports what actually happened.
//
// Nothing in zscript/ae/loader.zs has ever executed a tic -- it compiles and the pack loads,
// and that is all anyone can say about it. This presses its buttons from script and watches
// the consequences, so each claim about it is a line in a log rather than a hope.
//
//   aet_loader  0  off
//               1  BOTH ARMS SWING, no button held. Expects ae_claw from each arm and damage
//                  on whatever is in front. This is the "independent melee" test: the two
//                  arms are driven half a sweep apart, so a tic where only one of them is
//                  moving fast proves the arms are read separately.
//               2  OFF ARM MAIN ATTACK, held: the welding arc. Expects ae_arc, damage of type
//                  Electric, and AE_LoaderCageSpark actors appearing.
//               3  OFF ARM ALT ATTACK, held: the torch. Expects ae_flame and FTFire actors.
//               4  MAIN ARM: spawn a barrel, close the claw on it, then alt fire to throw it
//                  forward. Expects held -> not held and the barrel moving away fast.
//               5  MAIN ARM: spawn a barrel, close the claw, hold it shut and crush it.
//                  Expects ae_crush and the barrel dying.
//               6  MAIN ARM alt fire with an EMPTY claw: the ram. The other half of alt fire,
//                  which script 4 does not reach.
//               7  THE CAGE: damage the player and watch AE_LoaderWorn.ModifyDamage take its
//                  share, plus the speed factor, which is the whole "it is heavy" premise.
//
//               9  THE OWNER'S RUN (2026-10-31): step 80 units off doom2 MAP01's starting ledge,
//                  an imp at the claw (72 out), claw shut on it, held ~2 s (run with
//                  ae_loader_crush_tics 70), crushed; then a second imp and the off arm's attack.
//
// Every script reports the three psprite LAYERS first, because if the arms were never created
// then every action below still "works" and draws nothing -- which is the failure mode that
// would survive all of the above.
class AET_LoaderTest : EventHandler
{
	int started;
	int shots;
	Actor subject;
	bool said;

	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	// ZScript gives no SpriteID -> name, and String.Format("%s", aSpriteID) is a VM ABORT:
	// "string format failed. Expected a string for format %s". It cost a run. All this needs
	// to answer is whether the layer shows the left arm, so compare against that sprite.
	static bool IsArmL(SpriteID s)
	{
		return s == Actor.GetSpriteIndex('AEAL');
	}

	static int Cnt(Class<Actor> c)
	{
		int n = 0;
		ThinkerIterator it = ThinkerIterator.Create(c);
		Actor a;
		while (a = Actor(it.Next()))
			n++;
		return n;
	}

	void Layers(PlayerPawn mo)
	{
		let p = mo.player;
		// THE OFF ARM IS ON 2200, NOT 2211. AE_LoaderLayers.ARM_OFF (2211) is a declared
		// constant that nothing uses: Arms() creates only ARM_MAIN, and hands.zs:694 draws the
		// left arm on RSQ_Hands' own free-hand layer with the AEArmL state. Checking 2211
		// reported "no off arm" on a loader that has one, which is a test bug, not a pack bug.
		// What matters is that 2200 exists AND is showing AEAL rather than a bare hand.
		let off = p.FindPSprite(2200);
		String osp = 'absent';
		if (off)
			osp = IsArmL(off.Sprite) ? "the left ARM (AEAL)" : "present, but NOT the arm";
		Console.Printf("LOADER layers  main(2300) %d  offarm(2200) %s  cage(2305) %d  beacon(2304) %d",
			p.FindPSprite(2300) ? 1 : 0, osp,
			p.FindPSprite(2305) ? 1 : 0, p.FindPSprite(2304) ? 1 : 0);
		let tok = mo.FindInventory('AE_LoaderWorn');
		Console.Printf("LOADER worn %d  speedfactor %.2f  (1.00 = normal walking speed)",
			tok ? 1 : 0, tok ? tok.GetSpeedFactor() : -1.0);
	}

	override void WorldTick()
	{
		int s = int(F('aet_loader', 0));
		if (s <= 0 || !playeringame[0] || !players[0].mo)
			return;
		let mo = PlayerPawn(players[0].mo);
		if (!mo || !mo.player)
			return;
		let p = mo.player;
		int t = Level.maptime;

		if (!said && t > 40)
		{
			said = true;
			Layers(mo);
		}
		if (t < 60)
			return;

		int n = t - 60;		// tics since the test proper began

		// something to hit, 60 units in front, for the melee and arc scripts
		// 1 and 6 (swing, ram), off the ledge: an imp at the claw (72 out) that stays put
		if ((s == 1 || s == 6) && n == 20)
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 72.0;
			subject = Actor.Spawn('DoomImp', at, NO_REPLACE);
			if (subject)
				subject.Speed = 0;
			Console.Printf("LOADER monster %s spawned t%d at 72 units", subject ? subject.GetClassName() : 'NONE', t);
		}
		if ((s == 2 || s == 3) && n == 1)
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 60.0;
			subject = Actor.Spawn('ExplosiveBarrel', at);
			Console.Printf("LOADER target %s at %.0f units", subject ? 'barrel' : 'NONE', 60.0);
		}
		// 8: a MONSTER in reach, to prove it freezes in its pain frame while held. A barrel
		// has no Pain state, so scripts 4 and 5 could never show this.
		if (s == 8 && n == 1)
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 40.0;
			subject = Actor.Spawn('XenomorphAT', at, NO_REPLACE);
			Console.Printf("LOADER monster %s", subject ? subject.GetClassName() : 'NONE');
		}

		// 9 (owner 2026-10-31): an imp in reach, grab it, hold it a while, crush it; then a second
		// imp and the off arm's attack on it. The run sets ae_loader_crush_tics 70 so the hold
		// lasts two seconds before the crush lands.
		// doom2 MAP01 starts the player on a ledge: step ~2 m forward first (owner, 2026-10-31)
		if ((s == 1 || s == 4 || s == 6 || s == 9) && n == 0)
		{
			mo.SetOrigin(mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 80.0, false);
			Console.Printf("LOADER moved 80 units forward (off the ledge)");
		}
		if (s == 9 && (n == 20 || n == 150))
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * (n == 20 ? 72.0 : 90.0);	// the claw sits ae_loader_reach (72) out
			subject = Actor.Spawn('DoomImp', at, NO_REPLACE);
			if (subject)
				subject.Speed = 0;		// it still turns, attacks and feels pain; it just does not wander out of reach
			Console.Printf("LOADER monster %s spawned t%d at %.0f units", subject ? subject.GetClassName() : 'NONE', t, n == 20 ? 72.0 : 90.0);
		}

		// a barrel within the claw's reach for grab / throw / crush
		if ((s == 4 && n == 20 || s == 5 && n == 1))
		{
			Vector3 at = mo.pos + (cos(mo.angle), sin(mo.angle), 0) * 40.0;
			at.z += 20;
			if (s == 4)
				at = AE_LoaderHandler.ClawPoint(mo, false);	// off the ledge: right in the claw
			subject = Actor.Spawn('ExplosiveBarrel', at);
			Console.Printf("LOADER barrel spawned %s", subject ? (s == 4 ? "in the claw" : "40 units ahead") : "NOWHERE");
		}

		// --- the buttons ---------------------------------------------------------------
		// usercmd buttons cannot be written from here, so the fake hands' Buttons() is what
		// carries them; this sets the cvars it reads.
		int want = 0;
		if (s == 2)
			want |= 1;				// off main
		if (s == 3)
			want |= 2;				// off alt
		// THROW: grab with a SHORT squeeze, then let go of the trigger, then alt fire.
		// Holding the trigger shut for ae_loader_crush_tics (12) IS the crush -- the first
		// version held it 90 tics and crushed the barrel before the throw could run, so the
		// test destroyed its own subject and reported the wrong feature.
		// THE THROW'S WINDOW IS NARROW and both earlier attempts missed it in opposite ways.
		// clawShut needs ae_loader_claw_tics (7) to close; ae_grab fires then; crushFor starts
		// counting from that tic and ae_crush lands ae_loader_crush_tics (12) later. And
		// Fling() needs held[i], so the trigger must STAY down. So alt fire has to arrive
		// between about tic 8 and tic 18 with the trigger still held: hold 4 throughout, add
		// 8 at tic 12, and be finished before 19.
		if (s == 4)
			want |= (n >= 25 && n < 44) ? (4 | ((n >= 37 && n < 41) ? 8 : 0)) : 0;	// shifted 25: the barrel appears at n 20, off the ledge
		if (s == 5)
			want |= 4;				// main trigger, held, to crush
		if (s == 8)
			want |= 4;		// held throughout: the run raises ae_loader_crush_tics so the
							// crush cannot fire and end the test early
		if (s == 6)
			want |= (n >= 30 && n < 36) ? 8 : 0;	// main alt with nothing held: the ram (one press, imp at the claw)
		if (s == 9)
			want |= (n >= 25 && n < 130) ? 4 : (n >= 160 && n < 250) ? 1 : 0;	// claw shut, then off arm attack
		let bc = CVar.FindCVar('aet_buttons');
		if (bc && bc.GetInt() != want)
			bc.SetInt(want);

		// THE CAGE: `god` has to be OFF or the player takes nothing and ModifyDamage never
		// runs. The first version set god at t=10 and reported "health 100 -> 100" as if the
		// cage had eaten everything.
		if (s == 7 && n == 10)
			mo.bINVULNERABLE = false;
		if (s == 7 && n == 20 && mo.health > 40)
		{
			Console.Printf("LOADER health before %d", mo.health);
			mo.DamageMobj(null, null, 30, 'Melee');
			Console.Printf("LOADER health after  %d  (30 dealt; the cage should have eaten part)", mo.health);
		}

		// THE PUNCH, frame by frame. The arms were drawn frozen at 0 until 2026-10-24; this
		// prints both layers' frame every tic through a swing so "it animates" is a sequence
		// in a log and not an assertion.
		if ((s == 1 || s == 5) && (n % 2) == 0)
		{
			let a = p.FindPSprite(2300);
			let b = p.FindPSprite(2200);
			Console.Printf("LOADER frame t%d  main %s  left %s  sparks %d", t,
				a ? String.Format("%d", a.Frame) : "-",
				b ? String.Format("%d", b.Frame) : "-", Cnt('AE_LoaderCageSpark'));
		}

		if ((s == 1 || s == 4 || s == 6) && n >= 20 && (n % 3) == 0 && subject && n < 90)
			Console.Printf("LOADER subject t%d %s hp %d vel %.1f dist %.0f", t, subject.GetClassName(), subject.health,
				subject.vel.Length(), subject.Distance3D(mo));
		if (s == 9 && n >= 20 && n < 30 && subject)
			Console.Printf("LOADER early t%d imp pos %.0f %.0f %.0f vel %.1f %.1f %.1f floor %.0f me %.0f %.0f %.0f", t,
				subject.pos.x, subject.pos.y, subject.pos.z, subject.vel.x, subject.vel.y, subject.vel.z, subject.floorz, mo.pos.x, mo.pos.y, mo.pos.z);
		if (s == 9 && (n % 5) == 0 && subject)
		{
			Vector3 cp = AE_LoaderHandler.ClawPoint(mo, false);
			Console.Printf("LOADER monster t%d  %s  hp %d  state tics %d  vel %.1f  dist %.0f  claw-to-it %.0f (grab reach %.0f)", t, subject.GetClassName(),
				subject.health, subject.tics, subject.vel.Length(), subject.Distance3D(mo), (subject.pos - cp).Length(),
				AE_LoaderHandler.F2('ae_loader_grab_radius', 48.0) + subject.radius);
		}
		if (s == 8 && (n % 4) == 0 && subject)
			Console.Printf("LOADER monster t%d  state tics %d  frame %d  vel %.1f  hp %d",
				t, subject.tics, subject.frame, subject.vel.Length(), subject.health);

		if ((n % 35) == 0)
		{
			String sub = 'none';
			if (subject)
				sub = String.Format("%s hp %d vel %.1f", subject.GetClassName(), subject.health,
				                    subject.vel.Length());
			Console.Printf("LOADER t%d s%d  sparks %d  flames %d  mags %d | target %s",
				t, s, Cnt('AE_LoaderCageSpark'), Cnt('FTFire'), Cnt('RSR_DroppedMag'), sub);
		}
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (!e.Thing || !e.Inflictor && !e.DamageSource)
			return;
		if (e.Thing.player)
			return;
		Console.Printf("LOADER HIT %s dmg %d type %s  (hp now %d)",
			e.Thing.GetClassName(), e.Damage, e.DamageType, e.Thing.health);
	}

	override void WorldThingDestroyed(WorldEvent e)
	{
		if (e.Thing && e.Thing is 'ExplosiveBarrel')
			Console.Printf("LOADER the barrel is gone");
	}
}
