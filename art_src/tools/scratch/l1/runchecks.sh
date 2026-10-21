cd /tmp/sag
for c in art_src/rigs/root_spore_mushroom/root_spore_mushroom_parts_{f,s,b}_v1_fix.json art_src/rigs/sprout_boar/sprout_boar_parts_{f,b}_v1_fix.json art_src/rigs/mosscrown_king_boar/mosscrown_king_boar_parts_{f,s,b}_v2_fix.json; do b=${c%_fix.json}; python3 art_src/tools/rig_check.py $c --seam-band 4 --labels - v1 --sheet ${b}_jointcheck.png --json ${b}_jointcheck.json >/dev/null 2>&1; python3 -c "
import json;d=json.load(open('${b}_jointcheck.json'))['version'];print('${b##*/}', {k:(v['worst'],v['seam_worst']) for k,v in d.items()})"; done
