# art_src/wip/debug: debug and intermediate images (handoff copy)

Inspection images from the work machine. They keep their original folder structure (`l1/` = round 21c, `rigv2/` = rig v2, `v21/` = rig v2.1).
None of these are game assets. Anything already in the repo with identical content was skipped.

| Files | What |
|---|---|
| l1/*.comps.png | Component maps of the 21c AI sheets (made by `tools/scratch/l1/comps.py`): every connected component boxed and numbered in display coordinates. These are the picks behind the 21c cut configs. `k2.comps.png` = king boar part sheet v2 |
| l1/pose_hero.png, pose_mosscrown_king_boar.png, k_poses.png, m_poses.png, slime_pose.png, dm_pose.png | Early reference-pose renders (21c) of the hero, king boar v2, mushroom, slime and deep moss slime. Current pose sheets come from `ref_poses.py` with `_poses/*_v2.json` |
| l1/k_parts.png, m_parts.png, b_all.png | Cut-part overviews: king boar v2, mushroom, sprout boar f/b |
| l1/jc1.png, jc2.png | 21c joint-check crops (mushroom cap, boar tail) |
| rigv2/jc*.png | Joint-hole sheets at ±30° from the rig v2 round (hero f/s/b, back knee and shoulder) |
| rigv2/cmp_h.png, cmp_b.png | v1 vs v2 comparisons (hero, boar) as reviewed at the time |
| v21/hv_*.png | Hole maps for the joints that needed work in v2.1 (back knee, front hip, side neck). Blue = static, green = rotated child, red = hole |
| v21/boar_far_cmp.png, neck_layers.png | Boar far-leg outline before/after (`erase_outline_over`); hero side neck layer stack |
