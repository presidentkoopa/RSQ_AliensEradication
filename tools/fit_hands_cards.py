#!/usr/bin/env python3
"""fit_hands_cards.py -- the hand table from the CARDS, by the one method, into every place this pack reads it.

    RSQ_TOOLS=<RS_ModelSwapper>/tools RSQ_ERMAC=<RSQ_RustedLegacy>/src/models \\
        python3 -B tools/fit_hands_cards.py [PulseRifle_3D ...] [--write]

Why: zscript/rsq/handtable.zs was a solver's guess patched by hand four times over (its own header says so), with
the hooks copied into MODELDEF.aemain / MODELDEF.aedual by hand for the dual-wield path. The hands sat a hand's
width behind the grips and 8-10 cm under the forends (measured 2026-11-08 against the cards). This replaces all of
that with ONE source: for each gun, RS_ModelSwapper's card of the same mesh (cards/aliens/<gun>: measured grip line,
measured pump / support bar), the pack's own gun block (modeldef.<gun>.txt: the TC's Scale / Offset / ZOffset),
and the kit's ICP (tools/kit/handfit_cards.py in RS_ModelSwapper: Ermac's posed hand, its measured gripping face
put onto the gun in a tight window round the card's point). Then:
  * zscript/rsq/handtable.zs: GunHook / SupportHook of the fitted guns and their variants (same mesh, same row);
    GunRot / SupportRot 0; the pose letters, Trigger letters and the knife / satchel / smartgun rows untouched;
  * MODELDEF.aemain and MODELDEF.aedual: the hand blocks' Offset re-baked from the table (gen_aedual_modeldef.py's
    settled convention: Offset = (0 + hook.x, -24 + hook.z, -10 + hook.y)), so both draw paths agree by construction.
Sheets: docs/renders/fit/<class>.cards.png (gun + both hands, side and bottom). LOOK before --write.
Owner, 2026-11-08: the smartgun stays as it is (done last, by hand); the knife and satchel stay.
"""
import os, sys, re, json
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.environ.get('RSQ_TOOLS') or os.path.join(ROOT, '..', 'rs_modelswapper', 'tools')
if not os.path.isdir(TOOLS): sys.exit('RS_ModelSwapper not found: set RSQ_TOOLS to its tools/ folder')
MS = os.path.dirname(os.path.abspath(TOOLS))
for p in ('kit', 'handfit/core/hands_tool', 'handfit/blender'): sys.path.insert(0, os.path.join(TOOLS, p))
import gunview, hudrender, gunplace  # noqa: E402
import handfit_cards as HC  # noqa: E402
from handfit_addon import parse_card  # noqa: E402

# base class -> (card folder in RS_ModelSwapper, pose type, variants that wear the same mesh)
GUNS = {
    'M4A3Pistol_3D':        ('m4a3',  'pistol',       ['MercPistol_3D', 'SynthPistol_3D', 'YutaniPistol_3D']),
    'NewShotgun_3D':        ('m37a2', 'shotgun',      ['YutaniShotgun_3D']),
    'PulseRifle_3D':        ('m41a',  'rifle',        ['YutaniRifle_3D']),
    'M240Flamethrower_3D':  ('m260b', 'flamethrower', ['YutaniFlamer_3D']),
}
# the card's grip line is a centroid guess on the flamer (it lands mid-tank, 30 cm from the trigger lever); the gun's
# own trigger is its 'lever' part. The grip is built from the lever the way the pulse rifle's measured grip sits
# relative to ITS trigger (same mod, same author): top = trigger + (-6.6, 0, +0.9), bottom = trigger + (-7.5, 0, -10.0).
GRIP_FROM_TRIGGER = {'M240Flamethrower_3D': ((-6.6, 0.0, 0.9), (-7.5, 0.0, -10.0))}
# the support hand's point when the card has only the one-handed placeholder: the flamer's forward handle is the
# shipped (owner-approved, hook 0) support position, kept and re-seated onto the surface by the ICP.
SUPPORT_KEEP_SHIPPED = {'M240Flamethrower_3D'}
# owner's eye on the sheets (2026-11-08), applied after the ICP and recorded here, never typed into the table:
#   TRIGGER_FINGER: after the grip fit, the hand is moved so the pose's index pad (landmarks_ermac_frames.json) sits ON
#   the card's trigger point ("hand needs adjusted so finger is on trigger"; made the rule for every gun 21:20);
#   SUPPORT_NUDGE: cm (F, L, U).
TRIGGER_FINGER = set(GUNS)   # owner 21:20 "yes!": the default for every gun hand
SUPPORT_NUDGE = {'NewShotgun_3D': (3.0, 0.0, 0.0),          # "nudge offhand forward some"
                 'M240Flamethrower_3D': (0.0, 0.0, -4.0),   # "offhand needs moved down a little" (21:51), "down a little more" (21:52)
                 'PulseRifle_3D': (0.0, 0.0, -1.5)}         # "lower support hand just a tad" (22:16)
GUN_NUDGE = {'M240Flamethrower_3D': (0.0, 0.0, 1.5)}        # "mainhand needs moved up a little, super close"
# the owner approved this gun hand on its sheet (21:41, "pr and shotgun good") BEFORE the trigger-frame rule moved it
# 5 cm back (21:55: "shotgun grip hand is bad, it was good before"): pinned where he approved it, kit translation (F, L, U).
GUN_PIN = {'NewShotgun_3D': (-3.1, 2.0, -6.1)}
LANDMARKS = json.load(open(os.path.join(TOOLS, 'handfit', 'core', 'landmarks_ermac_frames.json')))
HAND_PL = dict(scale=[-1.0, 1.0, 1.0], off=[0.0, -24.0, -10.0])
SEP = chr(92)


def gun_block(cls):
    for name in sorted(os.listdir(ROOT)):
        if not name.lower().startswith('modeldef.') or not name.lower().endswith('.txt'): continue
        t = open(os.path.join(ROOT, name), encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'^Model\s+%s\s*\n\{(.*?)\n\}' % re.escape(cls), t, re.S | re.M):
            b = m.group(1)
            if 'hand.md3' in b: continue
            g = lambda pat, d=None: (re.search(pat, b, re.I).group(1) if re.search(pat, b, re.I) else d)
            path = g(r'Path\s+"?([^"\n]+?)"?\s*$')
            if path is None: path = g(r'Path\s+"([^"]+)"')
            scale = [float(x) for x in g(r'Scale\s+([-\d. ]+)', '1 1 1').split()]
            off = [float(x) for x in g(r'\n\s*Offset\s+([-\d. ]+)', '0 0 0').split()]
            zoff = g(r'ZOffset\s+([-\d.]+)')
            fr = int(g(r'FrameIndex\s+\w+\s+A\s+0\s+(\d+)', '0'))
            return dict(path=path.replace(SEP, '/').strip(), model=g(r'Model\s+0\s+"([^"]+)"'), scale=scale,
                        off=[off[0], off[1], float(zoff) if zoff is not None else (off[2] if len(off) > 2 else 0.0)], frame=fr, file=name)
    raise SystemExit('%s: no gun block in modeldef.*.txt' % cls)


def real_path(rel):
    """case-insensitive path under ROOT (the TC writes Models\\Weapons\\rifle, the repo has models/weapons/rifle)"""
    cur = ROOT
    for part in rel.split('/'):
        names = os.listdir(cur); hit = next((n for n in names if n.lower() == part.lower()), part); cur = os.path.join(cur, hit)
    return cur


def table():
    s = open(os.path.join(ROOT, 'zscript', 'rsq', 'handtable.zs'), encoding='utf-8').read()
    idx = {k: int(v) for k, v in re.findall(r"if \(w is '(\w+)'\)\s*return (\d+);", s)}
    def strs(fn):
        body = re.search(r'static String %s\(int i\)\s*\{(.*?)\n\t\}' % fn, s, re.S).group(1)
        return [x.strip().strip('"') for x in re.search(r'static const String v\[\] = \{([^}]*)\}', body, re.S).group(1).split(',')]
    def vecs(fn):
        body = re.search(r'static Vector3 %s\(int i\)\s*\{(.*?)\n\t\}' % fn, s, re.S).group(1)
        return list(zip(*[[float(v) for v in re.search(r'static const double %s\[\] = \{([^}]*)\}' % ax, body).group(1).replace('\n', ' ').split(',') if v.strip()] for ax in 'xyz']))
    return s, idx, dict(gp=strs('GunPose'), sp=strs('SupportPose'), gh=vecs('GunHook'), gr=vecs('GunRot'), sh=vecs('SupportHook'), sr=vecs('SupportRot'), tr=strs('Trigger'))


def to_flu(V, it):
    return gunview.to_fl(gunplace.to_local_ao(np.asarray(V, float).reshape(-1, 3), it))


def to_flu_hand(draw, t):
    """a hand md3 (path, frame), hooked by the kit translation t, in the controller frame (cm): vertex order = the file's"""
    it = dict(path=draw[0], frame=draw[1], hook=list(hook(t)), rot=[0, 0, 0], **HAND_PL)
    return np.vstack([gunview.to_fl(hudrender.to_local(raw_v, it)) for tris, raw_v in gunview.item_mesh(it)])


def hook(t):   # kit translation (F, L, U) -> hook (x left, y up, z back)
    return (round(float(t[1]), 3), round(float(t[2]), 3), round(float(-t[0]), 3))


def unhook(h):
    return np.array([-h[2], h[0], h[1]])


def fit(cls, T, idx, ermac):
    card_dir, typ, _ = GUNS[cls]; b = gun_block(cls)
    it = dict(path=real_path(os.path.join(b['path'], b['model'])), frame=b['frame'], scale=b['scale'], off=b['off'], ao=(0, 0, 0), color=[150, 155, 170])
    folder = os.path.join(MS, 'cards', 'aliens', card_dir)
    cf = [f for f in os.listdir(folder) if f.endswith('.card') and not f.endswith('.blend.card')][0]
    raw = open(os.path.join(folder, cf), encoding='utf-8', errors='replace').read(); card = parse_card(os.path.join(folder, cf)); pts = card['points']
    if cls in GRIP_FROM_TRIGGER:
        m = re.search(r'^\s+lever\s+surf \d+\s+rest \[([^\]]*)\]', raw, re.M); trig = np.array([float(v) for v in m.group(1).split(',')])
        a, c = GRIP_FROM_TRIGGER[cls]; pts['grip_top'] = list(trig + a); pts['grip_bottom'] = list(trig + c); pts['trigger'] = list(trig)
    sup_line = next((l for l in raw.splitlines() if l.strip().startswith('support ')), '')
    if 'placeholder' in sup_line: pts.pop('support', None)
    palm = to_flu([(np.array(pts['grip_top']) + np.array(pts['grip_bottom'])) / 2], it)[0]
    i = idx[cls]; two, one, sup, kind, trig_letter = HC.POSE[typ]
    gp = np.vstack([np.vstack([to_flu(raw_v, it), to_flu(raw_v, it)[tris].mean(1)]) for tris, raw_v in gunview.item_mesh(it)])
    t, err, why = HC.fit_gun(gp, palm, 'hand:%d' % two)
    if t is None: return None, '%s: gun hand: %s' % (cls, why)
    note = ''
    # what the game draws for this gun: its RQGT trigger frame when the table gives it a Trigger letter (hands.zs draws
    # "Trg"+letter at rest and "Sqz"+letter while firing), else the pose frame. The pack's own hand.md3 holds them:
    # RQGT A..E = frames 6, 8, 10, 12, 14 (MODELDEF.ae). The pad lands on the trigger with THAT finger.
    tl = T['tr'][i] if i < len(T['tr']) else ''
    draw = (os.path.join(ROOT, 'models', 'rsq', 'hand.md3'), 6 + 2 * 'ABCDE'.index(tl)) if tl in 'ABCDE' and tl else (os.path.join(ermac, 'hand', 'hand.md3'), two)
    if cls in TRIGGER_FINGER and 'trigger' in pts:
        trig = to_flu([pts['trigger']], it)[0]
        hv = to_flu_hand(draw, t)
        # the index finger = the vertices the pack's trigger frame moves against the pose frame (add_hand_frame.py bends
        # exactly that finger: 75 verts, measured 2026-11-08; landmarks_ermac_frames' 778/791/792 do NOT move, so they are
        # another finger). The pad = the ten of them that move most (the tip). Falls back to the whole finger's mean.
        base = to_flu_hand((os.path.join(ermac, 'hand', 'hand.md3'), two), t)
        dv = np.linalg.norm(hv - base, axis=1); fing = np.argsort(-dv)[:10] if (dv > 0.5).sum() >= 10 else np.argsort(-dv)[:3]
        pad = hv[fing].mean(0)
        t = t + (trig - pad); note = '; index pad put on the trigger (moved %s cm)' % np.round(trig - pad, 1).tolist()
    if cls in GUN_NUDGE: t = t + np.array(GUN_NUDGE[cls]); note += '; gun hand nudged %s (owner)' % (GUN_NUDGE[cls],)
    if cls in GUN_PIN: t = np.array(GUN_PIN[cls], float); note = '; gun hand PINNED where the owner approved it %s' % (GUN_PIN[cls],)
    row = dict(cls=cls, i=i, gh=hook(t), sh=(0.0, 0.0, 0.0), info='%-20s %-12s gun hand:%d F%+.1f L%+.1f U%+.1f (face %.2f cm from the gun)%s' % (cls, typ, two, t[0], t[1], t[2], err, note))
    sup_at = None
    if kind == 'same':
        t2 = t.copy(); row['info'] += '; support cups the gun hand'
    else:
        if 'support' in pts: sup_at = to_flu([pts['support']], it)[0]
        elif cls in SUPPORT_KEEP_SHIPPED:
            sup_at = HC.stored_patch('hand2:%d' % sup).mean(0) + unhook(T['sh'][i]); row['info'] += '; support point = the shipped (approved) hand, re-seated'
        if sup_at is None:
            row['info'] += '; no support point: support unchanged'; t2 = unhook(T['sh'][i])
        else:
            t2, err2, fp, why2 = HC.fit_support(gp, None, sup_at, 'hand2:%d' % sup)
            if t2 is None: row['info'] += '; support: ' + why2; t2 = unhook(T['sh'][i])
            else: row['info'] += '; support hand2:%d F%+.1f L%+.1f U%+.1f (%.2f cm)' % (sup, t2[0], t2[1], t2[2], err2)
        if cls in SUPPORT_NUDGE: t2 = np.asarray(t2, float) + np.array(SUPPORT_NUDGE[cls]); row['info'] += '; support nudged %s (owner)' % (SUPPORT_NUDGE[cls],)
    row['sh'] = hook(t2)
    # the sheet
    from PIL import Image
    out = os.path.join(ROOT, 'docs', 'renders', 'fit'); os.makedirs(out, exist_ok=True)
    gi = dict(it); gi.pop('ao')
    hands = [dict(path=draw[0], frame=draw[1], hook=list(row['gh']), rot=[0, 0, 0], color=[225, 170, 135], **HAND_PL)]
    if T['sp'][i]: hands.append(dict(path=os.path.join(ermac, 'hand', 'hand2.md3'), frame=sup, hook=list(row['sh']), rot=[0, 0, 0], color=[120, 200, 140], **HAND_PL))
    marks = [(*palm, 'grip', (255, 200, 60))] + ([(*sup_at, 'support', (120, 230, 140))] if sup_at is not None else [])
    a = os.path.join(out, cls + '.s.png'); bb = os.path.join(out, cls + '.b.png')
    gunview.view([gi] + hands, a, 'side', px=5, marks=marks, title='%s (cards fit)' % cls); gunview.view([gi] + hands, bb, 'bottom', px=5, marks=marks, title='%s (cards fit)' % cls)
    A, B = Image.open(a), Image.open(bb); O = Image.new('RGB', (max(A.width, B.width), A.height + B.height), (40, 44, 60)); O.paste(A, (0, 0)); O.paste(B, (0, A.height))
    O.save(os.path.join(out, cls + '.cards.png')); os.remove(a); os.remove(bb); row['sheet'] = os.path.join(out, cls + '.cards.png')
    return row, row['info']


def write_table(rows, s, idx):
    def set_vec(fn, i, v):
        nonlocal s
        m = re.search(r'(static Vector3 %s\(int i\)\s*\{)(.*?)(\n\t\})' % fn, s, re.S); body = m.group(2)
        for ax, val in zip('xyz', v):
            am = re.search(r'(static const double %s\[\] = \{)([^}]*)(\})' % ax, body); vals = [x.strip() for x in am.group(2).replace('\n', ' ').split(',')]
            vals[i] = '%.3f' % val; body = body[:am.start(2)] + ' ' + ', '.join(vals) + ' ' + body[am.end(2):]
        s = s[:m.start(2)] + body + s[m.end(2):]
    for r in rows:
        for c in [r['cls']] + GUNS[r['cls']][2]:
            i = idx[c]
            set_vec('GunHook', i, r['gh']); set_vec('GunRot', i, (0, 0, 0)); set_vec('SupportHook', i, r['sh']); set_vec('SupportRot', i, (0, 0, 0))
    stamp = '// 2026-11-08 FITTED FROM THE CARDS by tools/fit_hands_cards.py (RS_ModelSwapper cards/aliens + the kit\'s ICP): pistols,\n// shotguns, pulse rifles, flamers. GunRot / SupportRot 0. Knife, satchel, smartgun rows as before. Re-run the script,\n// never hand-edit; then tools/gen_aedual_modeldef.py --write and the aemain bake (this script does both with --write).\n'
    if 'FITTED FROM THE CARDS' not in s: s = stamp + s
    open(os.path.join(ROOT, 'zscript', 'rsq', 'handtable.zs'), 'w', encoding='utf-8').write(s)


def bake_aemain(rows, idx):
    """MODELDEF.aemain: the fitted classes' hand blocks take Offset = (0 + x, -24 + z, -10 + y) (gen_aedual's settled convention)"""
    p = os.path.join(ROOT, 'MODELDEF.aemain'); lines = open(p, encoding='utf-8', errors='replace').read().split('\n')
    want = {}
    for r in rows:
        for c in [r['cls']] + GUNS[r['cls']][2]: want[c] = r['gh']
    cur = None; n = 0
    for k, line in enumerate(lines):
        m = re.match(r'^Model\s+(\w+)', line)
        if m: cur = m.group(1); continue
        if line.startswith('}'): cur = None; continue
        if cur in want and re.match(r'^\s*Offset\s', line):
            x, y, z = want[cur]
            lines[k] = '\tOffset %.3f %.3f %.3f\t// GunHook (%.3f %.3f %.3f) baked (y/z swapped) by tools/fit_hands_cards.py 2026-11-08' % (0 + x, -24 + z, -10 + y, x, y, z); n += 1
    open(p, 'w', encoding='utf-8').write('\n'.join(lines)); return n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]; write = '--write' in sys.argv
    ermac = os.environ.get('RSQ_ERMAC') or sys.exit('set RSQ_ERMAC (hand/hand.md3 + hand2.md3: Ermac\'s full hands)')
    HC.REGIONS = json.load(open(os.path.join(TOOLS, 'kit', 'gripregions.json')))['poses']; HC.ERMAC = os.path.join(ermac, 'hand')
    s, idx, T = table()
    rows = []
    for cls in (args or list(GUNS)):
        row, info = fit(cls, T, idx, ermac); print(info)
        if row: rows.append(row)
    if write and rows:
        write_table(rows, s, idx); n = bake_aemain(rows, idx)
        import subprocess
        r = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'gen_aedual_modeldef.py'), '--write'], capture_output=True, text=True)
        print('-> handtable.zs: %d gun(s) + variants; MODELDEF.aemain: %d block(s) re-baked; gen_aedual_modeldef --write: %s' % (len(rows), n, (r.stdout.strip().splitlines() or ['?'])[-1]))
    for r in rows: print('   sheet', os.path.relpath(r['sheet'], ROOT))


if __name__ == '__main__':
    main()
