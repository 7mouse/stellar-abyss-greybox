cd /workspace/art_inbox/2026-10-21b
R=art_src/rigs
run(){ # cfg prevbase outbase
python3 art_src/tools/rig_check.py $1 --prev $2_src2x.psd $2_pivots.json --labels v2 v2.1 --sheet $3_jointcheck.png --json $3_jointcheck.json --out-root $PWD; }
run $R/sprout_boar/sprout_boar_s_fix_v2_1.json $R/sprout_boar/sprout_boar_parts_s_v2 $R/sprout_boar/sprout_boar_parts_s_v2_1
for v in f s b; do echo "== hero $v"; run $R/hero/hero_${v}_fix_v2_1.json $R/hero/hero_parts_${v}_v2 $R/hero/hero_parts_${v}_v2_1; done
