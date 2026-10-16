extends Node
## 试玩 CSV（user://）：floors.csv / hits.csv（可开关）/ deaths.csv；网页版可下载

const HEADERS := {
	"floors": "time,run_id,gen_no,depth,result,floor_sec,combat_sec,guard_sec,hp_start,hp_end,dmg_taken,kills,boons,level_start,level_end,mats,shards,clue_seen,chunks_visited,encounters,chasers_peak,camps_cleared,nodes_taken,charm_used,charm_floor,charm_interrupted,charm_source",
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
