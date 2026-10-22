# WIP 2026-10-21g: final batch (item 5), stopped unfinished

**Status: WIP. Nothing in this folder is cut, rigged, or game-ready.** The round was stopped on 2026-10-21 at about 17:32 (UTC+8) when the project was handed over to another team.
Only the GenerateImage source sheets exist. No cuts, rigs, manifests or mocks were made for these items.
Prompts for every sheet: `art_src/prompts/2026-10-21g.md`.

| File (src/) | Size | For | State |
|---|---|---|---|
| village_incubator_warehouse_gen1.jpg | 1280×720 | V02 incubator (left, has a green creature inside) + V07 warehouse (right) | Warehouse usable; incubator superseded by gen2 |
| village_incubator_gen2.jpg | 1024² | V02 incubator, empty glass + liquid | To cut. Split base / glass cover by tool; bubbles by shader |
| village_vault_gen1.jpg | 1280×720 | V03 vault closed (left) / open (right) | To cut, same scale, bottom-aligned |
| village_forge_shop_gen1.jpg | 1280×720 | V04 forge (left), V08 supply shop (right) | To cut. Forge fire-glow 2 frames planned as tool-made additive sprites |
| village_well_gate_gen1.jpg | 1280×720 | V05 dive well (left; the start point, since the elevator is cut), V06 return entrance (right) | To cut |
| village_craft_sign_grave_gen1.jpg | 1280×720 | V09 crafting table (left), S15 fallen signpost (middle), S19 tombstone (right) | To cut. "#0000" to be engraved with a font, not AI text |
| village_epitaph_gen1.jpg | 1280×720 | V10 epitaph wall with an empty slot | To cut. The plaque glyphs are fake AI "CJK" and need replacing or blurring |
| village_dirt_road_gen1.jpg | 1024² | V01 dirt road tile | Too bright and saturated. Grade, then make seamless to 512 |
| landmark_campfire_gen1.jpg | 1280×720 | S10 campfire, 4 frames | Logs jitter between frames. Align by the stone ring |
| landmark_chest_shrine_fence_gen1.jpg | 1280×720 | S12 chest closed/open, S13 shrine, S11 energy fence | The fence needs posts / energy split. Loop and rise frames planned as tool animation. The fence art is taller than the 256×128 spec |
| landmark_pit_spring_log_gen1.jpg | 1280×720 | S14 fall pit, S16 glowmoss spring, S17 fallen giant tree | Text labels in the sheet must be excluded (small components). S17 base/crown split by tool |
| cliffs_tall_strip_gen2.jpg | 1280×720 | 21e fix: tall cliff face (~2.5 hero heights) with an irregular moss top | Chosen. To wrap in x and cut into a/b/c segments |
| cliffs_tall_ends_gen1.jpg | 1280×720 | Tall cliff end pieces (left end / right start) | To cut |
| forest_clumps_gen2.jpg | 1280×720 | 21e fix: 3 different forest-back clumps (conifer + snag / broadleaf mound / oak + birch + ferns) | To cut and grade. More realistic and detailed than the 21e clumps; needs sat/val grading |
| piglet_leaf_gen1.jpg | 1280×720 | C05 piglet small leaf, f / s / b | To cut as the swap part for sprout_* |
| rejected/cliffs_tall_gen1_REJECTED.jpg, rejected/cliffs_tall_strip_gen1_REJECTED.jpg | 1280×720 | | Rejected: repetitive basalt columns |

Segmentation was checked (`cut_sprites.segment`): every object is one clean component on white, so `pick` cutting works.
Component bboxes in actual pixels:
- incubator_gen2: x231–796, y48–907
- vault: closed x106–585, open x660–1200
- forge: x81–558. Shop: x662–1228
- well: x122–584. Gate: x686–1202, y138–585
- craft: x64–543. Signpost: x610–886. Tombstone: x969–1203, y245–533
- epitaph: x37–1244, y170–494
- campfire frames: x53–294, 369–612, 680–923, 989–1233
- chest closed: x165–396. Chest open: x461–710. Shrine: x819–1135. Fence: x184–616, y340–677
- pit: x205–584, y15–306. Spring: x728–1060, y44–294. Log: x196–1092, y354–659
- forest clumps: x31–418, 445–828, 856–1255
- leaf: f x183–406, s x550–727, b x876–1094

## Remaining plan (not done)
- **Piglet C05:** scale sprout_boar f v1_1 / s v2_2 / b v1_2 by 0.7 (needs a scale op in rig_extras), lighter palette (grade val up, sat slightly down), swap sprout_* for the leaf, palette strip, rig_check target 0 at ±30°.
- **Buildings:** per item, a manifest with footprint, sort pivot (foot centre) and interaction point (40 px south of the front bottom-edge midpoint).
- **Cliffs v2:** an 8-bit wrap with a/b/c segments of ~420 px. Defringe the white specks on tree crowns, forest and canopies (alpha erode + rim decontaminate, as in style_fix_v3 U16).
- **Mocks:** the 21g combat mock with landmarks, and the village mock per level1-polish-spec §7.2.
