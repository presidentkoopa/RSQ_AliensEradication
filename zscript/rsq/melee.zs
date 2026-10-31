// 2026-10-22 VR MELEE BY MOTION (owner: "we can perform the stab motion"). With a knife in the
// main hand, a fast stab with the controller lands the knife's own blow (A_CustomPunch's damage
// and EnhancedKnifePuff, from actors/weapons/knife.txt) where the hand is going; a fast punch
// with the free off hand lands a fist. The weapon's own trigger swing is untouched.
//   ae_stab (OnOff), ae_stab_speed (m/s the hand must move: default 2.0), ae_stab_reach (cm).
//
// 2026-10-23 SWEPT BLADE (parity step 8, from BD22 1.92's zscript/rsvr/melee.zs). This used to
// spawn a short-lived invisible projectile at the hand and let it fly. Two faults came with that:
//
//   * A FAST STAB COULD MISS A BODY ENTIRELY. The hand moves between tics, and the projectile
//     only ever started from where the hand was at the tic boundary, so a thrust quicker than
//     the tic rate stepped straight over a monster. docs/RELOAD_ON_QUEST.md records the same
//     class of bug on the break-open guns: "Faster than ~1.5 m/s and the crossing fell between
//     tics and was never seen."
//   * ONE SWING COULD ONLY EVER HIT ONE THING -- the projectile destroyed itself on contact.
//
// The blade is now SWEPT: the segment from last tic's blade to this tic's is tested against
// everything in the box it passes through, so what the blade crossed is what gets hit. A hit
// list per swing means a single swing can open up two bodies but neither one twice, and the
// hand buzzes when it connects.
//
// The reach is the knife's OWN LENGTH, measured, not a round number: models/weapons/knife/
// knife.md3 is one surface 518 verts, 53.508 md3 units end to end along its principal axis
// (0.3001, 0.0000, 0.9539), x Scale 0.65 x 1.02 = 35.48 cm. It was 70.0 -- twice the knife --
// so the blow landed on things the blade was nowhere near. ae_stab_reach stays as a taste
// slider on top (memory rule: sliders are for taste, never for a value we failed to measure).
class RSQ_Strike : Actor
{
	int dmg;
	Name puff;
	Default
	{
		Projectile;
		Radius 6;
		Height 8;
		Speed 0;
		Damage 0;
		+NOGRAVITY +HITTRACER +BLOODSPLATTER +THRUSPECIES +NOEXTREMEDEATH
		RenderStyle "None";
		DamageType "Melee";
	}
	// the blow lands here, not through the missile's own Damage (0): the victim takes dmg as a
	// melee hit from the player, the knife's puff plays its body hit, and the strike is spent
	override int SpecialMissileHit(Actor victim)
	{
		if (!victim || victim == target)
			return 1;
		if (!victim.bSHOOTABLE)
			return -1;
		victim.DamageMobj(self, target, dmg, 'Melee', DMG_THRUSTLESS);
		class<Actor> pc = puff;
		if (pc)
		{
			let a = Spawn(pc, pos, ALLOW_REPLACE);
			if (a)
			{
				a.target = target;
				a.SetStateLabel("XDeath");
			}
		}
		Destroy();
		return 0;
	}
	States
	{
	Spawn:
		TNT1 A 1;
		TNT1 A 1;
		TNT1 A 1;
		Stop;
	Death:
		TNT1 A 0
		{
			class<Actor> pc = puff;
			if (pc)
			{
				let a = Spawn(pc, pos, ALLOW_REPLACE);
				if (a)
				{
					a.target = target;
					if (tracer && tracer.bSHOOTABLE)
						a.SetStateLabel("XDeath");	// the body hit, as a puff with PUFFONACTORS plays it
				}
			}
		}
		Stop;
	}
}

class RSQ_MeleeHandler : EventHandler
{
	Vector3 handPrev[MAXPLAYERS], offPrev[MAXPLAYERS];
	int handCool[MAXPLAYERS], offCool[MAXPLAYERS];
	// last tic's blade segment per hand, so this tic can sweep from it
	Vector3 tipPrev[MAXPLAYERS][2], rootPrev[MAXPLAYERS][2];
	bool hasPrev[MAXPLAYERS][2];
	Array<Actor> struck;		// the current swing's hit list: one swing never hits a body twice
	double travelled[MAXPLAYERS];	// decaying sum of the hand's travel, cm: the displacement test

	static double F(Name n, double def)
	{
		let c = CVar.FindCVar(n);
		return c ? c.GetFloat() : def;
	}

	static bool KnifeHeld(PlayerInfo p)
	{
		let w = p.ReadyWeapon;
		return w && (w is 'Knife_3D' || w is 'YutaniKnife_3D');
	}

	override void WorldTick()
	{
		let cvOn = CVar.FindCVar('ae_stab');
		if (cvOn && !cvOn.GetBool())
			return;
		let cvSpd = CVar.FindCVar('ae_stab_speed');
		double need = cvSpd ? cvSpd.GetFloat() : 2.0;
		let cvReach = CVar.FindCVar('ae_stab_reach');
		double reach = cvReach ? cvReach.GetFloat() : 70.0;
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (!playeringame[n])
				continue;
			let p = players[n];
			let mo = p.mo;
			if (!mo || p.playerstate != PST_LIVE || !RSVR_VRHand.InVR(mo))
				continue;
			double vu = 34.0;
			let cv = CVar.GetCVar('vr_vunits_per_meter', p);
			if (cv && cv.GetFloat() > 0)
				vu = cv.GetFloat();
			double ps = mo.Level.pixelstretch;
			if (ps <= 0)
				ps = 1.2;
			Vector3 h = RSVR_VRHand.HandPos(mo);
			Vector3 o = RSVR_VRHand.OffPos(mo);
			// hand speed in m/s: map units per tic (the z axis squashed by pixelstretch) * 35 / vu
			Vector3 dh = h - handPrev[n]; dh.z *= ps;
			Vector3 dq = o - offPrev[n]; dq.z *= ps;
			handPrev[n] = h;
			offPrev[n] = o;
			if (handCool[n] > 0) handCool[n]--;
			if (offCool[n] > 0) offCool[n]--;
			if (!KnifeHeld(p))
				continue;
			// THE SPINE, 2026-10-31: speeds and directions from RSVR_Pose (the hand in the pawn's
			// own frame, turns subtracted, teleports refused) instead of raw point differences.
			let pose = RSVR_Pose.Get();
			double sh = 0, so = 0;
			Vector3 mvh = (0, 0, 0), mvo = (0, 0, 0);
			if (pose && pose.Delta(mo, 0, 1))
			{
				sh = pose.dStep.Length() / pose.dSecs / 100.0;		// m/s
				Vector3 w = RSVR_Pose.ToWorld(mo, pose.dStep);
				mvh = w / max(w.Length(), 0.001);
			}
			Vector3 offStepBody = (0, 0, 0);
			if (pose && pose.Delta(mo, 1, 1))
			{
				so = pose.dStep.Length() / pose.dSecs / 100.0;
				offStepBody = pose.dStep;
				Vector3 w = RSVR_Pose.ToWorld(mo, pose.dStep);
				mvo = w / max(w.Length(), 0.001);
			}
			double len = reach * vu / 100.0;		// cm -> map units

			// the knife: a thrust along the blade (the hand moving the way it points). The
			// blade is swept from where it was last tic to where it is now, so what it passed
			// through is what it hits.
			Vector3 kdir = RSVR_VRHand.HandDir(mo, 0, 0, ps);
			Vector3 tip = h + kdir * len;
			bool swinging = sh >= need;
			if (swinging && handCool[n] == 0)
			{
				Vector3 mv = mvh;
				double along = mv dot kdir;			// +1 straight down the blade: a thrust
				// A SLASH IS NOT A THRUST, 2026-10-24 (owner asked for "stab or slash"; this
				// only ever had the stab). The test was `along > 0.3` -- the hand must move
				// ALONG the blade -- so a cut drawn ACROSS the target, which is most of what
				// anyone does with a knife, was rejected outright.
				//
				// VR_MELEE_ON_QUESTZDOOM_2026-10-24.md warns about the same axis from the
				// other side: "a thrust moves the tip along its own axis, the slowest motion
				// it makes; a stab, a draw-cut and a lean all did nothing" (SABER e825d10). So
				// the two motions need two tests, not one:
				//   THRUST  mostly along the blade, and slower is allowed -- a stab is short.
				//   SLASH   mostly ACROSS it, and the blade has to be moving properly.
				// The sweep below is the same for both: what the segment passed through is
				// what it cuts.
				double lat = sqrt(max(0.0, 1.0 - along * along));
				bool thrust = along > F('ae_stab_along', 0.3);
				bool slash = lat > F('ae_stab_across', 0.6)
				             && sh >= need * F('ae_slash_speed_mul', 1.35);
				// DISPLACEMENT ON TOP OF VELOCITY. The document calls this "the strongest
				// single idea in the three mods' swing detectors ... immune to exactly the
				// thing a velocity test cannot see: a twitch, a tracker glitch, or one noisy
				// sample". The hand must have gone somewhere, not merely twitched fast.
				// the path the hand actually walked over the last three tics, from the spine
				travelled[n] = pose ? pose.Travel(mo, 0, 3) : 0.0;
				if ((thrust || slash) && travelled[n] >= F('ae_stab_travel', 9.0))
				{
					if (!hasPrev[n][0])
					{
						rootPrev[n][0] = h;
						tipPrev[n][0] = tip;
					}
					// owner 2026-10-31: the knife hits for 1.3 x the fist's power
					Sweep(mo, rootPrev[n][0], tipPrev[n][0], h, tip,
						int(FistRoll() * F('ae_knife_fist_mul', 1.3) + 0.5), 'EnhancedKnifePuff', "ALIECLW1");
				}
			}
			// the swing is over: let the next one hit these bodies again
			if (!swinging && struck.Size() > 0)
				struck.Clear();
			rootPrev[n][0] = h;
			tipPrev[n][0] = tip;
			hasPrev[n][0] = true;

			// THE FREE FIST, 2026-10-31: a real punch, not "any fast motion". BD22's four
			// conditions (RSQ_QuestEngineSurvey 01_MELEE 4.1), all read from the spine in the
			// pawn's own frame (+x forward):
			//   FAST      off-hand speed over ae_stab_speed
			//   FORWARD   this tic's move mostly forward of the body (ae_punch_forward of it)
			//   A JAB     forward displacement over the last four tics (ae_punch_jab cm)
			//   IN FRONT  the hand ends ahead of the body (ae_punch_front cm)
			// plus the spike filter: a hand sitting on the body centre is the engine's
			// menu/pause reset (hw_vrmodes.cpp:442), never a fist.
			bool punch = false;
			if (so >= need && offCool[n] == 0 && pose && offStepBody.Length() > 0.001)
			{
				double fwd = offStepBody.x / offStepBody.Length();
				double jab = pose.Delta(mo, 1, 4) ? pose.dStep.x : 0.0;
				double front = pose.Sample(mo, 1, 0) ? pose.sPt.x : 0.0;
				bool onBody = pose.Sample(mo, 1, 0) && pose.sPt.Length() < 5.0;
				punch = !onBody && fwd >= F('ae_punch_forward', 0.6) && jab >= F('ae_punch_jab', 12.0)
				        && front >= F('ae_punch_front', 25.0);
			}
			if (punch && p.OffhandWeapon is 'RSQ_Hands' && RSQ_MeleeHandler.OffFree(mo))
			{
				Vector3 mv = mvo;
				Vector3 ofrom = hasPrev[n][1] ? rootPrev[n][1] : o;
				Sweep(mo, ofrom, ofrom + mv * (len * 0.35), o, o + mv * (len * 0.35),
					FistRoll(), 'EnhancedKnifePuff', "ALIECLW1");
				offCool[n] = 12;
			}
			rootPrev[n][1] = o;
			hasPrev[n][1] = true;
		}
	}

	// the fist's power: one roll of the free fist's damage. The knife is ae_knife_fist_mul of it.
	static int FistRoll()
	{
		return random(2, 8);
	}

	static bool OffFree(PlayerPawn mo)
	{
		let rs = RSR_Handler.StateOf(mo);
		return !rs || rs.phase == RSR.IDLE;
	}

	// is q inside t's cylinder, with a little slack?  (1.92 Touches)
	static bool Touches(Actor t, Vector3 q, double pad)
	{
		if (q.z < t.pos.z - pad || q.z > t.pos.z + t.height + pad)
			return false;
		double ddx = q.x - t.pos.x;
		double ddy = q.y - t.pos.y;
		double rr = t.radius + pad;
		return ddx * ddx + ddy * ddy <= rr * rr;
	}

	// nothing solid between the hand and the point the blade reached (1.92 Clear): without this
	// a swing cuts through a wall into whatever is standing on the other side of it
	static bool Clear(Actor mo, Vector3 from, Vector3 to)
	{
		Vector3 d = to - from;
		double len = d.Length();
		if (len <= 0.001)
			return true;
		FLineTraceData t;
		mo.LineTrace(VectorAngle(d.x, d.y), len, -asin(clamp(d.z / len, -1, 1)),
			TRF_ABSPOSITION | TRF_THRUACTORS, from.z, from.x, from.y, t);
		return t.HitType == TRACE_HitNone;
	}

	// SWEEP the quad between last tic's blade (a0..b0) and this tic's (a1..b1), hitting
	// everything the blade actually passed through. Ported from 1.92's Sweep, with its step
	// counts: the blade is walked in <=16 steps of travel and 8 segments along its length,
	// which is what stops a fast thrust from stepping over a body between tics.
	void Sweep(PlayerPawn mo, Vector3 a0, Vector3 b0, Vector3 a1, Vector3 b1, int dmg, Name puff, Sound snd)
	{
		double pad = 5;
		Vector3 c = (a0 + b0 + a1 + b1) / 4;
		double r = max(max((a0 - c).Length(), (b0 - c).Length()),
		               max((a1 - c).Length(), (b1 - c).Length())) + pad;
		double travel = max((b1 - b0).Length(), (a1 - a0).Length());
		int steps = clamp(int(travel / 4) + 1, 1, 16);
		int segs = 8;
		bool any = false;
		let it = BlockThingsIterator.CreateFromPos(c.x, c.y, c.z - r, 2 * r, r, false);
		while (it.Next())
		{
			Actor t = it.thing;
			if (!t || t == mo || t.player || !t.bSHOOTABLE || t.bDORMANT || t.health <= 0)
				continue;
			if (struck.Find(t) != struck.Size())
				continue;
			bool hit = false;
			Vector3 at = (0, 0, 0);
			for (int i = 1; i <= steps && !hit; i++)
			{
				double f = double(i) / steps;
				for (int j = segs; j >= 0 && !hit; j--)
				{
					double sv = double(j) / segs;
					Vector3 p0 = a0 + (b0 - a0) * sv;
					Vector3 p1 = a1 + (b1 - a1) * sv;
					Vector3 q = p0 + (p1 - p0) * f;
					if (Touches(t, q, pad))
					{
						hit = true;
						at = q;
					}
				}
			}
			if (!hit || !Clear(mo, a1, at))
				continue;
			struck.Push(t);
			// NOT DMG_THRUSTLESS ANY MORE, 2026-10-24. The trap table: "DMG_THRUSTLESS on
			// every cut path -- a lit blade swept through four imps left four imps standing
			// exactly where they were" (SABER e825d10). A cut should move what it cuts. The
			// shove is mass-scaled and runs along the way the blade was travelling, with a
			// little lift, because "a shove with no lift: a body slides a few units and walks
			// straight back in" (SABER, SHIELD both).
			t.DamageMobj(mo, mo, dmg, 'Melee');
			AE_LoaderHandler.HitStop(t, 3);		// hitstop, light (2026-10-31)
			Vector3 dir = b1 - b0;
			double dl = dir.Length();
			if (dl > 0.01 && !t.bBOSS)
			{
				double push = F('ae_stab_push', 3.0) * 100.0 / max(t.Mass, 50);
				t.vel += dir / dl * push + (0, 0, push * 0.3);
			}
			class<Actor> pc = puff;
			if (pc)
			{
				let a = Actor.Spawn(pc, at, ALLOW_REPLACE);
				if (a)
				{
					a.target = mo;
					a.SetStateLabel("XDeath");		// the body hit, as the puff plays it
				}
			}
			any = true;
		}
		mo.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP);
		if (any)
			Buzz(mo);		// the hand feels it connect -- handoff QoL item 4
	}

	// a short haptic pulse in the main hand (RSVR_Buzz carries a DamageType so the engine's
	// per-hand haptics fire; see zscript/rsvr/common.zs)
	static void Buzz(PlayerPawn mo)
	{
		mo.SpawnPlayerMissile('RSVR_Buzz', mo.angle, noautoaim: true);
	}

	static void Strike(PlayerPawn mo, Vector3 from, Vector3 dir, double reach, int dmg, Name puff, Sound snd)
	{
		let s = RSQ_Strike(Actor.Spawn('RSQ_Strike', from, ALLOW_REPLACE));
		if (!s)
			return;
		s.target = mo;
		s.dmg = dmg;
		s.puff = puff;
		s.vel = dir * (reach / 3.0);	// three tics of flight = the reach
		s.angle = VectorAngle(dir.x, dir.y);
		s.pitch = -asin(clamp(dir.z, -1, 1));
		mo.A_StartSound(snd, CHAN_AUTO, CHANF_OVERLAP);
		if (RSR.Debug(mo.player))
			Console.Printf("ae melee t%d: strike from (%.0f %.0f %.0f) dir (%.2f %.2f %.2f) reach %.0f dmg %d", mo.Level.maptime, from.x, from.y, from.z, dir.x, dir.y, dir.z, reach, dmg);
	}
}
