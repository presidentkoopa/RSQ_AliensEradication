"""Smartgun hands, placed BY HAND from the owner's two holds (2026-11-08, headset recordings, see
RS_ModelSwapper cards/aliens/m56/ae_m56.card OWNER note and the 22:30 screenshot):

  main hand  = the VERTICAL BAR on the RIGHT side of the receiver, just behind the drum, halfway up
               (model x -2..2, y -9.7..-6, z -11..+3; the round knob on top is what the owner boxed).
               Ermac pose F (hand.md3 106, the plasma-rifle fist), no rotation.
  support    = the HORIZONTAL HANDLEBAR sticking out LEFT, forward of the drum (model x 29..34,
               y 12..20, z 8..12). Ermac pose C (hand2.md3 91, fist on a vertical grip) ROLLED 90 deg
               so the bar runs through the fist laterally: knuckles up, thumb inboard, forearm from
               the left-rear. Roll -90 put the fist under the bar palm-up (rejected, looked at).
  The rear pistol grip with the trigger surface is UNUSED (owner).

The hooks are solved so each pose's grip point (tools/kit/gripregions.json 'point') lands on the
target after the rotation (RenderHUDModel rotates about the controller origin AFTER adding the hook,
hudrender.to_local). Rows 8 (Smartgun_3D) and 16 (YutaniSmartgun_3D, same mesh). The dual-wield bake
(MODELDEF.aemain/.aedual) is untouched: the smartgun has no dual blocks.

    RSQ_TOOLS=../rs_modelswapper/tools RSQ_ERMAC=../rsq_rustedlegacy/src/models python3 tools/fit_smartgun.py [--write]
"""
import os, sys, re, json
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_hands_cards as F  # noqa: E402  (kit on sys.path, table(), HAND_PL, hook())
import gunview, hudrender  # noqa: E402
from PIL import Image  # noqa: E402

ROWS = (8, 16)
GUN_AT, GUN_ROT, GUN_FRAME = (0.0, -7.3, -4.5), (0, 0, 0), 106        # F L U cm; (yaw, pitch, roll) deg
SUP_AT, SUP_ROT, SUP_FRAME = (28.5, 13.0, 5.2), (0, 0, 90), 91
REGIONS = json.load(open(os.path.join(F.TOOLS, 'kit', 'gripregions.json')))['poses']


def hand_flu(path, fr, hook, rot):
    it = dict(path=path, frame=fr, hook=list(hook), rot=list(rot), **F.HAND_PL)
    return np.vstack([gunview.to_fl(hudrender.to_local(raw, it)) for tris, raw in gunview.item_mesh(it)])


def solve_hook(path, fr, key, target, rot):
    """the hook that lands the pose's grip point on target (FLU) under this rotation"""
    V0 = hand_flu(path, fr, (0, 0, 0), (0, 0, 0)); g = np.array(REGIONS[key]['point'])
    near = np.argsort(np.linalg.norm(V0 - g, axis=1))[:30]
    c = hand_flu(path, fr, (0, 0, 0), rot)[near].mean(0)
    J = np.stack([hand_flu(path, fr, e, rot)[near].mean(0) - c for e in np.eye(3)], 1)
    return tuple(float(v) for v in np.round(np.linalg.solve(J, np.asarray(target) - c), 3))


def set_vec(s, fn, i, v):
    m = re.search(r'(static Vector3 %s\(int i\)\s*\{)(.*?)(\n\t\})' % fn, s, re.S); body = m.group(2)
    for ax, val in zip('xyz', v):
        am = re.search(r'(static const double %s\[\] = \{)([^}]*)(\})' % ax, body); vals = [x.strip() for x in am.group(2).replace('\n', ' ').split(',')]
        vals[i] = '%.3f' % val; body = body[:am.start(2)] + ' ' + ', '.join(vals) + ' ' + body[am.end(2):]
    return s[:m.start(2)] + body + s[m.end(2):]


def main():
    ermac = os.environ.get('RSQ_ERMAC') or sys.exit('set RSQ_ERMAC (hand/hand.md3 + hand2.md3: Ermac\'s full hands)')
    hp, sp = os.path.join(ermac, 'hand', 'hand.md3'), os.path.join(ermac, 'hand', 'hand2.md3')
    gh = solve_hook(hp, GUN_FRAME, 'hand:%d' % GUN_FRAME, GUN_AT, GUN_ROT)
    sh = solve_hook(sp, SUP_FRAME, 'hand2:%d' % SUP_FRAME, SUP_AT, SUP_ROT)
    print('GunHook %s GunRot %s  SupportHook %s SupportRot %s' % (gh, GUN_ROT, sh, SUP_ROT))
    # sheet
    b = F.gun_block('Smartgun_3D')
    gi = dict(path=F.real_path(os.path.join(b['path'], b['model'])), frame=0, scale=b['scale'], off=b['off'], color=[150, 155, 170])
    hands = [dict(path=hp, frame=GUN_FRAME, hook=list(gh), rot=list(GUN_ROT), color=[225, 170, 135], **F.HAND_PL),
             dict(path=sp, frame=SUP_FRAME, hook=list(sh), rot=list(SUP_ROT), color=[120, 200, 140], **F.HAND_PL)]
    marks = [(*GUN_AT, 'main', (255, 200, 60)), (*SUP_AT, 'support', (120, 230, 140))]
    out = os.path.join(F.ROOT, 'docs', 'renders', 'fit'); os.makedirs(out, exist_ok=True); row = []
    for k, r in (('side', (-30, 50, -30, 20)), ('top', (-30, 50, -30, 30)), ('front', (-30, 20, -30, 20))):
        o = os.path.join(out, '_sg_%s.png' % k); gunview.view([gi] + hands, o, k, rng=r, px=9, marks=marks, title='Smartgun_3D (by hand, fit_smartgun.py)'); row.append(Image.open(o)); os.remove(o)
    R = Image.new('RGB', (row[0].width + row[2].width, row[0].height + row[1].height), (40, 44, 60))
    R.paste(row[0], (0, 0)); R.paste(row[1], (0, row[0].height)); R.paste(row[2], (row[0].width, 0))
    sheet = os.path.join(out, 'Smartgun_3D.cards.png'); R.save(sheet); print('sheet', os.path.relpath(sheet, F.ROOT))
    if '--write' in sys.argv:
        s, idx, T = F.table()
        for i in ROWS:
            s = set_vec(s, 'GunHook', i, gh); s = set_vec(s, 'GunRot', i, GUN_ROT); s = set_vec(s, 'SupportHook', i, sh); s = set_vec(s, 'SupportRot', i, SUP_ROT)
        open(os.path.join(F.ROOT, 'zscript', 'rsq', 'handtable.zs'), 'w', encoding='utf-8').write(s)
        print('-> handtable.zs rows %s written' % (ROWS,))


if __name__ == '__main__':
    main()
