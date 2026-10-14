class_name EnemyData
extends Resource

enum Pattern { MELEE_COMBO, TRACKER, BALANCED }

@export var display_name: String = ""
@export var max_hp: int = 30
@export var attack: int = 8
@export var speed: int = 8
@export var pattern: Pattern = Pattern.BALANCED
@export var color: Color = Color.RED
