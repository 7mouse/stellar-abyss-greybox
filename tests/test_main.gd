extends Node
## 入口：把测试驱动挂到 root 上（不随场景切换被释放），再开始跑。脚本编译失败时直接退出 1。
func _ready() -> void:
	var s: GDScript = load("res://tests/test_runner.gd")
	if s == null or not s.can_instantiate():
		printerr("[FAIL] 测试脚本编译失败")
		get_tree().quit(1)
		return
	var r: Node = s.new()
	r.name = "TestRunner"
	get_tree().root.add_child.call_deferred(r)
