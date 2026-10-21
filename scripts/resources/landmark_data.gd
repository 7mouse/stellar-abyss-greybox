class_name LandmarkData
extends Resource
## 第 1 层地标（data/landmarks/*.tres）。MapGen 在地形和篝火之后、营地/巡逻之前摆放。

@export var id := ""
@export var display_name := ""
@export var probability := 1.0 ## < 1 时按这个概率放；首局必出的墓碑见 guarantee_first_run
@export var required := true ## 放不下就整图重 roll（最多 5 次）。可跳过的地标为 false
@export var guarantee_first_run := false ## 首局忽略 probability，必出
@export var radius := 0.0 ## 圆形占地
@export var footprint_w := 0.0 ## 矩形占地的长边（倒伏巨树 460）；生成时转到与主路垂直
@export var footprint_h := 0.0 ## 矩形占地的短边（160）
@export var bar_w := 0.0 ## 挡视线碰撞条的长边（420）
@export var bar_h := 0.0 ## 碰撞条的短边（80）
@export var min_start := 0.0
@export var min_campfire := 0.0
@export var min_camp := 0.0
@export var min_guard_wall := 0.0
@export var min_entrance := 0.0
@export var min_patrol := 0.0 ## 之后的巡逻点不得近于这个距离
@export var min_landmark := 0.0
@export var light_radius := 0.0
@export var sight_confirm_cut := 0.0 ## 光里的敌人，视野确认时间减去这么多秒
@export var interact_sec := 0.0
@export var band_min := 0.0 ## 第一战：离起点的下限（px）。墓碑：沿主路的比例下限
@export var band_max := 0.0
@export var offset_min := 0.0 ## 墓碑离路中心的下限（px）
@export var offset_max := 0.0
@export var column_min := 0 ## 1 起算的列号，含端点；0 = 不限
@export var column_max := 0
@export var near_path := 0 ## 离主路最多几个区块；0 = 不限
@export var guard_column := false ## 放在层主区前一列
