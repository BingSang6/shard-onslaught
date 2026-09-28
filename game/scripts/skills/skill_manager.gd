class_name SkillManager
extends Node
## 技能系统（SDS 3.3 组件式架构）：
## - 记录玩家所有已习得技能等级（levels）
## - acquire()：新技能注册 / 重复获取升级（PRD：技能可重复拾取，重复获得升级）
## - get_choices()：升级面板 3 选 1 随机池（排除已满级技能）
## - 主动技能（晶域/晶盾/引力漩涡）在首次习得时实例化为独立逻辑子节点
## - 被动技能（弹射/引爆/瞬闪/高速结晶/晶刺增重）由玩家/投射物/特效查询等级与参数

var player: Node2D = null
var levels := {}                            # skill_id -> 等级


func reset(p_player: Node2D) -> void:
	player = p_player
	levels.clear()
	for child in get_children():
		# 先立即摘除再释放：避免 queue_free 延迟期间 get_node_or_null 命中将死节点
		remove_child(child)
		child.queue_free()


func get_level(skill_id: String) -> int:
	return int(levels.get(skill_id, 0))


## 学习/升级技能，返回新等级（弹种卡封顶 3 级，其余 SKILL_MAX_LV）
func acquire(skill_id: String) -> int:
	var lv := get_level(skill_id) + 1
	levels[skill_id] = mini(lv, skill_max_lv(skill_id))
	# 主动技能首次习得 → 实例化逻辑节点
	if lv == 1 and GameConfig.SKILLS[skill_id]["active"]:
		var node: Node = null
		match skill_id:
			"aura":
				node = preload("res://scripts/skills/aura_skill.gd").new()
			"shield":
				node = preload("res://scripts/skills/shield_skill.gd").new()
			"vortex":
				node = preload("res://scripts/skills/vortex_skill.gd").new()
		if node != null:
			node.name = skill_id
			node.set("skills", self)
			add_child(node)
	return levels[skill_id]


## 技能封顶等级（弹种卡 3 级，其余默认 SKILL_MAX_LV）
func skill_max_lv(skill_id: String) -> int:
	return int(GameConfig.SKILLS[skill_id].get("max_lv", GameConfig.SKILL_MAX_LV))


## 已习得的技能数量（等级总和）
func total_levels() -> int:
	var sum := 0
	for k in levels:
		sum += levels[k]
	return sum


## 升级面板随机池：从未满级技能中不重复抽取 count 个（弹种卡按自身 max_lv 封顶）
func get_choices(count: int = 3) -> Array:
	var pool: Array = []
	for id in GameConfig.SKILLS.keys():
		if get_level(id) < skill_max_lv(id):
			pool.append(id)
	pool.shuffle()
	var result: Array = pool.slice(0, count)
	# 池子不足时用「应急修复」补位（回血，永不溢出）
	while result.size() < count:
		result.append("heal")
	return result


## 晶盾消耗接口（Player.take_damage → 这里委托给晶盾节点）
func consume_shield() -> bool:
	var node := get_node_or_null("shield")
	if node != null:
		return node.consume()
	return false


## 引力漩涡立即触发（测试/调试入口）
func trigger_vortex_now() -> void:
	var node := get_node_or_null("vortex")
	if node != null:
		node.trigger()
