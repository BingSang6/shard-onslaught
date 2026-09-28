extends Node2D
## 技能：晶域扩散（主动·生存/输出）
## 玩家周围持续环形伤害场，持续切割靠近的怪物。
## 视觉：双层反向旋转的青色光环（Node2D._draw），脉动闪烁。

var skills: Node = null                     # SkillManager 引用（由其注入）

var _tick_timer := 0.0
var _t := 0.0


func _physics_process(delta: float) -> void:
	if skills == null or skills.player == null:
		return
	var lv: int = skills.get_level("aura")
	if lv <= 0:
		return
	var p := GameConfig.skill_params("aura", lv)
	var radius: float = p["radius"]
	var dps: float = p["dps"]

	position = skills.player.position
	_t += delta
	queue_redraw()

	# 周期性范围切割伤害
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = p["tick"]
		var tick_damage := dps * float(p["tick"])
		for m in get_tree().get_nodes_in_group("monsters"):
			if not m.alive:
				continue
			if position.distance_to(m.position) <= radius + m._radius:
				m.take_damage(tick_damage, Vector2.ZERO, 0.0, 0)


func _draw() -> void:
	# 三层描边模拟发光：宽淡 → 细亮，透明度随时间脉动
	if skills == null or skills.player == null or skills.get_level("aura") <= 0:
		return
	var lv: int = skills.get_level("aura")
	var radius: float = GameConfig.skill_params("aura", lv)["radius"]
	var pulse := 0.65 + 0.35 * sin(_t * 5.0)
	var cyan := Color(0.13, 0.9, 0.75)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(cyan, 0.12 * pulse), 14.0, true)
	draw_arc(Vector2.ZERO, radius, _t * 0.8, _t * 0.8 + TAU, 56, Color(cyan, 0.45 * pulse), 4.0, true)
	draw_arc(Vector2.ZERO, radius * 0.92, -_t * 1.2, -_t * 1.2 + TAU, 48, Color(cyan, 0.6 * pulse), 2.0, true)
