extends Node
## 入口：把测试驱动挂到 root 上（不随场景切换被释放），再开始跑。
func _ready() -> void:
	var r: Node = preload("res://tests/test_runner.gd").new()
	r.name = "TestRunner"
	get_tree().root.add_child.call_deferred(r)
