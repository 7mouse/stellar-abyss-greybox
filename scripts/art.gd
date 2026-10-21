class_name Art
extends RefCounted
## 占位贴图，每个实体一张。正式图按同一路径覆盖。
## 主角在世界里高 HERO_WORLD_H，镜头把它放到屏幕高度的 1/8。

const HERO_WORLD_H := 96.0
const HERO := "res://assets/actors/hero.png"
const PORTRAIT := "res://assets/hud/portrait.png"
const ENEMY := {
	"mushling": "res://assets/actors/boar.png",
	"rootshot": "res://assets/actors/shroom.png",
	"shellbug": "res://assets/actors/slime.png",
	"piglet": "res://assets/actors/boar.png",
}
## 只影响画出来的高度，不改碰撞和 data.size
const VISUAL_H := {
	"mushling": 78.0,
	"rootshot": 86.0,
	"shellbug": 56.0,
	"piglet": 54.6, ## 发芽野猪 ×0.7
	"guard_1": 320.0, ## 苔冠王野猪画布
}

static func hero() -> Texture2D:
	return load(HERO)

static func portrait() -> Texture2D:
	return load(PORTRAIT)

static func enemy(id: String) -> Texture2D:
	return load(String(ENEMY.get(id, ENEMY["mushling"])))

static func visual_h(id: String) -> float:
	return float(VISUAL_H.get(id, 72.0))

static func icon(name: String) -> Texture2D:
	return load("res://assets/hud/icon_%s.png" % name)
