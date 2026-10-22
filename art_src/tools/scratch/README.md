# art_src/tools/scratch: one-off helper scripts (handoff copy, not maintained)

Throwaway helpers I used on the work machine while checking cuts and joints in rounds 21b–21c. They are kept so the next team can see how the numbers in the notes were made.
Hard-coded paths such as `/workspace/art_inbox/2026-10-21b/...` and `/tmp/sag` point at the old work machine. **Change them to the repo root before running.** For everyday work, use the maintained tools in `art_src/tools/`.

| File | What it did |
|---|---|
| l1/comps.py | `comps.py sheet.jpg out.png`: labels the connected components of an AI sheet on white (red box + id, display coordinates at 1024×576). Used to choose `pick` points for cut configs. Output is the `*.comps.png` files in `art_src/wip/debug/l1/` |
| l1/grid.py | `grid.py sheet.jpg out.png x0,y0,x1,y1 [zoom]`: zoomed crop of a sheet with a 10/50 px coordinate grid, for reading pick and rect coordinates |
| l1/headgrid.py | `headgrid.py file.psd name x0,y0,x1,y1 zoom out.png [scale]`: composites a PSD's visible layers and draws a pixel grid on a crop. Used to place blink, eye and pivot coordinates on heads |
| l1/show.py | `show.py out.png a.png b.png ...`: puts images side by side on grey (2× when small) for a quick look |
| l1/runchecks.sh | Batch `rig_check.py --seam-band 4` over the 21c mushroom, sprout boar and king boar v2 fix configs; prints worst / seam per joint |
| l1/checks.txt | Output of runchecks.sh (21c joint numbers before fixes, as quoted in the 21c checklist) |
| l1/attach_list.txt | List of the GenerateImage output files on the work machine at 21c (internal attachment paths; a map from output id to file) |
| rigv2/parts.py | `parts.py file.psd out.png layer ...`: enlarged sheet of selected layers, labelled with their bounding boxes |
| rigv2/view.py | `view.py file.psd out.png [layer ...]`: 2× composite with the named layers highlighted and the others faded |
| rigv2/zoom.py | `zoom.py out.png x0,y0,x1,y1 a_src2x.psd b_src2x.psd ...`: the same crop from several PSD versions side by side (v1 vs v2) |
| rigv2/check*.txt | make_palette and rig_check console logs from the v2 rig round (palette hex lists, joint holes v1 → v2) |
| v21/check.sh | Runs rig_check v2 → v2.1 for the sprout boar s and hero f/s/b (`--labels v2 v2.1`) |
| v21/holes.py | Per-joint hole report at ±30°: count, mean offset and bbox of the hole pixels relative to the pivot (used to decide which way to grow caps) |
| v21/holes2.py | Variant of holes.py with a fixed disc radius |
| v21/holeviz.py | `holeviz.py fix.json base joint angle out.png`: colour map at one angle (blue static, green rotated child, red hole). Outputs are the `hv_*.png` files in `art_src/wip/debug/v21/` |
| v21/detail.py, v21/zoom.py | Zoomed joint detail sheets (full and solo rows) for the v2 vs v2.1 comparison images committed in `art_src/rigs/*/*_v2_vs_v2_1_*.png` |
| v21/metrics.py | The v2 → v2.1 numbers in RIG_V2_NOTES.md: rest-pose luminance change in the cap area, extension minus interior luminance, dark pixels at the old cut line. Needs the "no caps" PSDs that rig_patch writes with caps disabled (not kept) |
| v21/metrics.json, metrics_final.txt, check_final.txt | Outputs of metrics.py and check.sh (the source of the tables in RIG_V2_NOTES.md) |
