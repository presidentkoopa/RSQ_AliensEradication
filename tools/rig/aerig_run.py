"""TEST ONLY: the power loader's batch check on the ModelSwapper rig (real QuestZDoom 17.3, OpenXR path).

    python3 -B tools/rig/aerig_run.py [name]

Builds the pack (tools/mkpk3.py) and an overlay pk3 holding aerig.zs + the qzt_* cvars the rig's glue
reads, then runs doom2 -> A01 (the TC) -> pack -> overlay on MAP01 with a console script that gods,
snap-turns at 1200 and looks up at 1300, dumping a frame every 70 tics. Data: /home/claude/rig/packs
(the owner's doom2.wad and TC, never committed). One engine at a time: flock on /home/claude/rig.lock.
Output: tools/rig/runs/<name>.log (the AERIG lines), runs/<name>/f*.ppm frames.
"""
import os, sys, subprocess, zipfile, shutil
H = os.path.dirname(os.path.abspath(__file__)); PACK = os.path.abspath(os.path.join(H, '..', '..'))
RIG = os.environ.get('AE_RIG', '/home/claude/rs_modelswapper/tools/rig/bin')
DATA = os.environ.get('AE_DATA', '/home/claude/rig/packs')
name = sys.argv[1] if len(sys.argv) > 1 else 'loader_batch'
out = os.path.join(H, 'runs'); os.makedirs(os.path.join(out, name), exist_ok=True)
pk3 = os.path.join(out, 'pack.pk3'); ov = os.path.join(out, 'aerig_overlay.pk3'); log = os.path.join(out, name + '.log')
subprocess.check_call([sys.executable, '-B', os.path.join(PACK, 'tools', 'mkpk3.py'), PACK, pk3], stdout=subprocess.DEVNULL)
with zipfile.ZipFile(ov, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('zscript/rig/aerig.zs', open(os.path.join(H, 'aerig.zs')).read())
    z.writestr('ZSCRIPT.aerig', 'version "4.10"\n#include "zscript/rig/aerig.zs"\n')
    z.writestr('MAPINFO.aerig', 'gameinfo { AddEventHandlers = "AET_Rig" }\n')
    # the rig's hook: a pack cvar of these names, when set (non-empty / >= 0), replaces the qz_ one
    z.writestr('CVARINFO.aerig', 'user string qzt_rhand = "";\nuser string qzt_lhand = "";\n'
               'user float qzt_rtrigger = -1;\nuser float qzt_rgrip = -1;\nuser float qzt_ltrigger = -1;\nuser float qzt_lgrip = -1;\n')
# A FRESH INI EACH RUN. The rig engine runs in the Android layout and reads/writes config/qzdoom.ini
# RELATIVE TO ITS CWD, ignoring -config (found 2026-11-08: a cab_height saved by one run came back
# in the next). bin/config/qzdoom.ini is tracked in RS_ModelSwapper, so it is restored from git
# before and after the run (the README's own trap: "git checkout tools/rig/bin/config/qzdoom.ini").
ini_src = os.path.join(RIG, 'config', 'qzdoom.ini'); ini = os.path.join(out, 'scratch.ini')
def reset_ini():
    subprocess.call(['git', '-C', os.path.dirname(RIG), 'checkout', '--', os.path.relpath(ini_src, os.path.dirname(RIG))], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
reset_ini(); shutil.copy(ini_src, ini)
script = ('wait 60; god; wait 1140; qz_rstick "1 0"; wait 3; qz_rstick "0 0"; wait 97; qz_hmd "0 1.6 0 -50 0 0"; '
          'wait 60; qz_hmd "0 1.6 0 0 0 0"; wait 40; quit')
env = dict(os.environ, QZ_RES='480', QZ_DUMP_EVERY='35', QZ_DUMP_DIR=os.path.join(out, name))
argv = ['flock', '-o', '-x', '/home/claude/rig.lock', 'timeout', '900', 'xvfb-run', '-a', os.path.join(RIG, 'qz'),
        '-iwad', os.path.join(DATA, 'doom2.wad'), '-file', os.path.join(DATA, 'A01.pk3'), pk3, ov,
        '-config', ini, '-nosound', '-nomusic', '+logfile', log, '+map', 'MAP01', '+' + script]
r = subprocess.call(argv, cwd=RIG, env=env, stdout=open(os.path.join(out, name + '.out'), 'w'), stderr=subprocess.STDOUT)
reset_ini()
print('exit', r, '->', log)
