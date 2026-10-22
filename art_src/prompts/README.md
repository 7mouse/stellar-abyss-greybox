# art_src/prompts: generation prompts and parameters

Every image here was made with **GenerateImage** (the Grok Bot image tool). That tool takes only:
- the prompt text,
- `aspect_ratio` (16:9 gives 1280×720, 1:1 gives 1024×1024, 3:4 is listed per entry),
- optional reference images.

It has no seed, steps, sampler or CFG settings, so the same prompt will not give the same image again. Keep the committed source files; they are the only ground truth.

Prompt entries are verbatim. They were recovered on 2026-10-21 from the art agent's own tool-call transcript. Times are UTC+8.

| File | Round | Count | Covers |
|---|---|---|---|
| [2026-10-21c.md](2026-10-21c.md) | 21c, from 15:40 | 1 | King boar part sheet v2 (日式手绘 redraw) |
| [2026-10-21d.md](2026-10-21d.md) | 21d, from 16:09 | 19 | Terrain v2: S01 tiles (moss / autumn / stone / water), S02 edges, S03 trees, S04–S07 props, S09 leaf light. UI v2: frames / panels / buttons / icons g1 |
| [2026-10-21e.md](2026-10-21e.md) | 21e, from 16:30 | 6 | Irregular flagstones a/b/c, U16 icons g2, modular cliffs, forest back/front layers |
| [2026-10-21f.md](2026-10-21f.md) | 21f, from 16:41 | 10 | Hero expressions + C03 portrait, king boar heads + mane, monster extras, FX gen2a/2b, F01 finisher, F08 brush, F14 dust |
| [2026-10-21g.md](2026-10-21g.md) | 21g, from 17:20, **WIP** | 17 | Village V01–V10, landmarks S10–S17/S19, tall cliffs (2 rejected), forest clumps, piglet leaf, empty incubator |

`refs/` holds the reference composites that were passed to GenerateImage and existed only on the work machine. They are tool-made montages of committed rig previews.
Every other reference path in the prompt files is a committed repo file.

Each entry also lists:
- the output file id,
- the repo file it became, matched by checksum. "Not committed" means a draft that was not kept.

## Not recoverable

These were generated before this transcript began: an earlier session, before the 2026-10-21 box rollback. Their exact prompts are **not recoverable**. Only the content descriptions in `art_src/ref/README.md`, `art_src/ref/explore/README.md` and the commit messages remain.

| Files | When | What is known |
|---|---|---|
| `art_src/ref/explore/*.jpg` (37) | 2026-10-15/16 | Style exploration, all superseded by 定稿 v2. The filename is the generation time |
| `art_src/ref/combat_baseline_v2.jpg` (+ crops) | 2026-10-16 | Locked combat baseline 定稿 v2 (producer-approved) |
| `art_src/ref/hud_reference_v1.jpg`, `hero_sheet_v1/v2.jpg`, `mossroot_basic3_v1/v2.jpg`, `slime_depth_progression_v1.jpg`, `hero_s_render_256.png` | 10-16 to 10-18 | Reference / design sheets |
| `art_src/ref/level1_plan_samples/a_village_v1.jpg`, `b_mossroot_combat_v1.jpg`, `c_boss_mosscrown_v1.jpg` | Art plan v1 | Plan samples |
| `art_src/src/hero_fb_partsheet_gen1.jpg`, `hero_s_partsheet_gen1.jpg`, `sprout_boar_fb_partsheet_gen1.jpg`, `sprout_boar_s_partsheet_gen1.jpg` and the hero / sprout_boar parts v2 / v2.1 sources | Before 10-21 | Part sheets (3/4-view chibi, white background, assembled poses on the top row, separated parts below) |
| `art_src/src/slime_deep_moss_partsheet_gen1/gen2.jpg`, `root_spore_mushroom_partsheet_gen1.jpg`, `mosscrown_king_boar_partsheet_gen1.jpg`, `terrain_floor1_set_gen1.jpg`, `hud_set_gen1.jpg`, `fx_set_gen1.jpg` | 10-21, 11:54–11:59 | Batch 1 sheets, described in `art_src/ref/README.md` |

For new sheets in the same style, reuse the 21d–21g prompts as templates. They carry the house style block:
- non-pixel Japanese hand-painted 2D,
- muted low-saturation palette,
- thin soft dark outlines,
- pure white background with isolated parts,
- "not mobile web-game style", no candy colours, no living-artist names.
