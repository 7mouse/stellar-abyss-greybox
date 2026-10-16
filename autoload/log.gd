extends Node
## 试玩 CSV（user://）：floors.csv / hits.csv（可开关）/ deaths.csv；网页版可下载

const HEADERS := {
	"floors": "time,run_id,gen_no,depth,result,floor_sec,combat_sec,guard_sec,hp_start,hp_end,dmg_taken,kills,boons,level_start,level_end,mats,shards,clue_seen,chunks_visited,encounters,chasers_peak,camps_cleared,nodes_taken,charm_used,charm_floor,charm_interrupted,charm_source,charm_stash_run,unbossed_mat_out,charm_stock",
	"hits": "time,run_id,depth,src,dst,dmg,dodged_by_dash",
	"deaths": "time,gen_no,level,depth,cause,legacy_picked,vault_count,clue_seen",
}
var dir := "user://"
var hits_enabled := true

func path(table: String) -> String:
	return dir.path_join(table + ".csv")

func write(table: String, cols: Array) -> void:
	if table == "hits" and not hits_enabled:
		return
	var p := path(table)
	var exists := FileAccess.file_exists(p)
	if exists: ## 表头变了（加了新列）：旧文件改名为 .old.csv，新文件用新表头
		var rf := FileAccess.open(p, FileAccess.READ)
		var head := rf.get_line() if rf else ""
		rf = null
		if head != HEADERS[table]:
			DirAccess.rename_absolute(p, p.get_basename() + ".old.csv")
			exists = false
	var f := FileAccess.open(p, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	if not exists:
		f.store_line(HEADERS[table])
	f.seek_end()
	var row: Array = [Time.get_datetime_string_from_system()]
	for c in cols:
		var s := str(c)
		if "," in s:
			s = '"' + s.replace('"', "'") + '"'
		row.append(s)
	f.store_line(",".join(row))
	f.close()

## 改最后一行里给出的列。用来在回村存东西之后补上风险监控
func patch_last(table: String, values: Dictionary) -> void:
	var p := path(table)
	if not FileAccess.file_exists(p) or values.is_empty():
		return
	var text := FileAccess.get_file_as_string(p)
	var lines := text.split("\n")
	while lines.size() > 0 and lines[lines.size() - 1] == "":
		lines.remove_at(lines.size() - 1)
	if lines.size() < 2:
		return
	var hdr := _split_csv(lines[0])
	var cols := _split_csv(lines[lines.size() - 1])
	for k in values:
		var i := hdr.find(String(k))
		if i >= 0 and i < cols.size():
			cols[i] = str(values[k])
	lines[lines.size() - 1] = _join_csv(cols)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()

func _split_csv(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var quoted := false
	for i in line.length():
		var ch := line[i]
		if quoted:
			if ch == '"':
				quoted = false
			else:
				cur += ch
		elif ch == '"':
			quoted = true
		elif ch == ",":
			out.append(cur)
			cur = ""
		else:
			cur += ch
	out.append(cur)
	return out

func _join_csv(cols: PackedStringArray) -> String:
	var row: Array = []
	for c in cols:
		var s := str(c)
		if "," in s or '"' in s:
			s = '"' + s.replace('"', "'") + '"'
		row.append(s)
	return ",".join(row)

## 风险监控：用过回村符又存过东西的局占比，以及 unbossed_mat_out 的合计和平均
func risk_summary() -> Dictionary:
	var lines := rows("floors")
	var empty := {"runs": 0, "stash_runs": 0, "share": 0.0, "unbossed_sum": 0, "unbossed_avg": 0.0, "rows": 0}
	if lines.size() < 2:
		return empty
	var hdr := _split_csv(lines[0])
	var si := hdr.find("charm_stash_run")
	var ui := hdr.find("unbossed_mat_out")
	var ri := hdr.find("run_id")
	var runs := {}
	var stash_runs := {}
	var sum := 0
	var nrows := 0
	for i in range(1, lines.size()):
		if lines[i] == "":
			continue
		var cols := _split_csv(lines[i])
		nrows += 1
		var rid := cols[ri] if ri >= 0 and ri < cols.size() else ""
		runs[rid] = true
		if si >= 0 and si < cols.size() and int(cols[si]) != 0:
			stash_runs[rid] = true
		if ui >= 0 and ui < cols.size() and cols[ui].is_valid_int():
			sum += int(cols[ui])
	var rc := runs.size()
	return {"runs": rc, "stash_runs": stash_runs.size(), "share": (float(stash_runs.size()) / float(rc)) if rc else 0.0, "unbossed_sum": sum, "unbossed_avg": (float(sum) / float(nrows)) if nrows else 0.0, "rows": nrows}

func rows(table: String) -> PackedStringArray:
	if not FileAccess.file_exists(path(table)):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path(table)).strip_edges().split("\n")

func clear() -> void:
	for t in HEADERS:
		if FileAccess.file_exists(path(t)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path(t)))

## 网页版：逐个下载三张表
func download_all() -> int:
	var n := 0
	for t in HEADERS:
		if not FileAccess.file_exists(path(t)):
			continue
		n += 1
		if OS.has_feature("web"):
			JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(path(t)), t + ".csv", "text/csv")
	return n
