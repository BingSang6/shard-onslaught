extends Node2D
## BOSS 招式组件（《波次闯关制·BOSS设计任务书》：挂在 BOSS 本体上，monster.gd setup 注入）
## 冷却计时 + 行为函数；招式 id 语义见 GameConfig.BOSSES 注释：
##   fan=扇形晶刺 / pulse=扩散冲击环 / summon=召唤 / dash_charge=冲刺斩(带晶刃轨迹) /
##   split=分裂合并(触发式) / armor=护甲壳(被动，monster.gd 承担) / quake=震地波(环+飞溅) /
##   vortex_drop=敌方引力漩涡(吸玩家) / spiral=旋臂扫射(旋转弹幕) / rain=全屏晶雨
## 晶洞主宰三阶段：BOSS5_PHASE_ACTIONS 按阶段启用招式子集。
## 弹幕挂 enemy_projectile_layer 组节点；召唤/分裂体挂 monster_layer 组节点（main 注入）。

var monster: Monster = null
var player: Node2D = null

var _cds := {}                # 招式索引 -> 剩余冷却
var _spirals := []            # 旋转弹幕发射器状态
var _split_used := false      # 分裂已触发（各 BOSS 限 1 次）
var _split_children: Array = []
var _split_timer := 0.0       # >0 = 分裂进行中（倒计时到合并）
var _dash_time := 0.0
var _dash_trail_cd := 0.0


func setup(m: Monster) -> void:
	monster = m
	player = m.player
	var actions: Array = monster_cfg().get("actions", [])
	for i in actions.size():
		# 出场缓冲：首招延迟 = 冷却本身 + 1.2s（给玩家反应窗口）
		_cds[i] = float(actions[i].get("cooldown", 5.0)) + 1.2


func monster_cfg() -> Dictionary:
	return GameConfig.BOSSES.get(monster.monster_id, {})


func _physics_process(delta: float) -> void:
	if monster == null or not monster.alive or player == null:
		return

	# ---- 阶段切换（晶洞主宰）：HP 比例跨过阈值 → 阶段+1，重置该阶段招式冷却 ----
	var ratios: Array = monster_cfg().get("phase_hp_ratios", [])
	if not ratios.is_empty():
		var ratio := monster.hp / monster.max_hp
		var want_phase := 0
		for i in range(1, ratios.size()):
			if ratio <= float(ratios[i]) + 0.001:
				want_phase = i
		if want_phase > monster.phase_index:
			monster.phase_index = want_phase
			monster._flash = 1.5
			_reset_cooldowns_for_phase()

	# ---- 分裂（猎手/主宰）：HP 比例触发，本体无敌 + 小体，限时合并 ----
	if _split_timer > 0.0:
		_update_split(delta)
	else:
		for act in monster_cfg().get("actions", []):
			if String(act.get("id", "")) == "split" and not _split_used:
				if monster.hp / monster.max_hp <= float(act.get("trigger_hp", 0.5)):
					_start_split(act)

	# ---- 冲刺斩：冲刺中留晶刃轨迹 ----
	if _dash_time > 0.0:
		_dash_time -= delta
		_dash_trail_cd -= delta
		if _dash_trail_cd <= 0.0:
			_dash_trail_cd = 0.06
			_spawn_trail_zone()
		if _dash_time <= 0.0:
			monster.dash_vel = Vector2.ZERO

	# ---- 旋转弹幕发射器 ----
	for s in _spirals:
		s.left -= delta
		s.fire_cd -= delta
		if s.fire_cd <= 0.0 and s.count > 0:
			s.fire_cd = s.interval
			s.count -= 1
			_spawn_projectile(monster.position, Vector2.from_angle(s.angle) * s.speed, s.damage)
			s.angle += s.step

	# ---- 招式冷却与释放 ----
	var actions: Array = monster_cfg().get("actions", [])
	for i in actions.size():
		var act: Dictionary = actions[i]
		var aid := String(act.get("id", ""))
		if aid == "armor" or aid == "split":
			continue                      # 被动/触发式，不走冷却
		if not _action_enabled(aid):
			continue
		_cds[i] = float(_cds.get(i, 0.0)) - delta
		if _cds[i] <= 0.0:
			_cds[i] = float(act.get("cooldown", 5.0))
			_execute(aid, act)


# ---------------- 招式行为 ----------------

func _execute(aid: String, act: Dictionary) -> void:
	match aid:
		"fan":
			_action_fan(act)
		"pulse":
			_action_pulse(act)
		"summon":
			_action_summon(act)
		"dash_charge":
			_action_dash(act)
		"quake":
			_action_quake(act)
		"vortex_drop":
			_action_vortex(act)
		"spiral":
			_action_spiral(act)
		"rain":
			_action_rain(act)


## 扇形晶刺：朝玩家方向 count 枚，总张角 spread_deg
func _action_fan(act: Dictionary) -> void:
	var count := int(act.get("count", 5))
	var spread := deg_to_rad(float(act.get("spread_deg", 50.0)))
	var speed := float(act.get("proj_speed", 320.0))
	var damage := float(act.get("damage", 12.0))
	var base := (player.position - monster.position).normalized().angle()
	for i in count:
		var t := float(i) / float(count - 1) - 0.5 if count > 1 else 0.0
		var dir := base + t * spread
		_spawn_projectile(monster.position, Vector2.from_angle(dir) * speed, damage)


## 扩散冲击环：全向弹幕成环（视觉即"冲击环"），附带扩散圆环特效
func _action_pulse(act: Dictionary) -> void:
	var radius := float(act.get("radius", 300.0))
	var damage := float(act.get("damage", 12.0))
	_show_expanding_ring(monster.position, radius)
	var count := 18
	for i in count:
		var dir := TAU * float(i) / float(count)
		_spawn_projectile(monster.position, Vector2.from_angle(dir) * radius * 0.9, damage)


## 召唤：怪物层生成 count 只小怪（绕本体分布）
func _action_summon(act: Dictionary) -> void:
	var count := int(act.get("count", 3))
	var mid := String(act.get("monster", "small"))
	var layer := get_tree().get_first_node_in_group("monster_layer")
	if layer == null:
		return
	for i in count:
		var ang := TAU * float(i) / float(count) + randf() * 0.8
		var pos: Vector2 = monster.position + Vector2.from_angle(ang) * (monster._radius + 90.0)
		pos = pos.clamp(Vector2(60, 60), GameConfig.ARENA_SIZE - Vector2(60, 60))
		var m := Monster.new()
		layer.add_child(m)
		m.setup(player, mid, pos)


## 冲刺斩：直线高速冲向玩家当前位置，沿途留晶刃轨迹（触碰伤害）
func _action_dash(act: Dictionary) -> void:
	var dash_speed := float(act.get("dash_speed", 350.0))
	var dir := (player.position - monster.position).normalized()
	monster.dash_vel = dir * dash_speed
	_dash_time = 0.55
	_dash_trail_cd = 0.0


## 震地波：环形冲击 + count 枚小晶体飞溅
func _action_quake(act: Dictionary) -> void:
	var count := int(act.get("count", 8))
	var speed := float(act.get("proj_speed", 260.0))
	var damage := float(act.get("damage", 15.0))
	_show_expanding_ring(monster.position, 240.0)
	for i in count:
		var dir := TAU * float(i) / float(count) + randf() * 0.3
		_spawn_projectile(monster.position, Vector2.from_angle(dir) * speed, damage)


## 敌方引力漩涡：玩家附近生成 count 个吸人漩涡（持续 duration 秒）
func _action_vortex(act: Dictionary) -> void:
	var count := int(act.get("count", 2))
	var radius := float(act.get("radius", 120.0))
	var pull := float(act.get("pull", 180.0))
	var duration := float(act.get("duration", 4.0))
	for i in count:
		var center: Vector2 = player.position + Vector2.from_angle(randf() * TAU) * randf_range(120.0, 260.0)
		center = center.clamp(Vector2(80, 80), GameConfig.ARENA_SIZE - Vector2(80, 80))
		var zone := VortexZone.new()
		zone.init(center, radius, pull, duration, player)
		add_child(zone)


## 旋臂扫射：旋转发射 count 枚弹幕（每 interval 一发，角度步进）
func _action_spiral(act: Dictionary) -> void:
	var count := int(act.get("count", 12))
	var speed := float(act.get("proj_speed", 300.0))
	var damage := float(act.get("damage", 15.0))
	_spirals.append({
		"angle": randf() * TAU, "step": 0.55, "speed": speed, "damage": damage,
		"count": count, "interval": 0.15, "fire_cd": 0.0, "left": float(count) * 0.15 + 0.2,
	})
	# 清理到期发射器
	var alive_spirals := []
	for s in _spirals:
		if s.left > 0.0:
			alive_spirals.append(s)
	_spirals = alive_spirals


## 全屏晶雨：waves 轮，每轮 count 枚从屏幕顶部落下
func _action_rain(act: Dictionary) -> void:
	var waves := int(act.get("waves", 2))
	var count := int(act.get("count", 12))
	var speed := float(act.get("proj_speed", 300.0))
	var damage := float(act.get("damage", 20.0))
	var interval := float(act.get("wave_interval", 0.8))
	for w in waves:
		var delay := float(w) * interval
		for i in count:
			var x := GameConfig.ARENA_SIZE.x * (float(i) + 0.5 + randf_range(-0.35, 0.35)) / float(count)
			_spawn_projectile_later(
				Vector2(x, -40.0), Vector2(0, speed), damage, delay + randf_range(0.0, 0.25))


# ---------------- 分裂 / 合并 ----------------

func _start_split(act: Dictionary) -> void:
	_split_used = true
	var layer := get_tree().get_first_node_in_group("monster_layer")
	if layer == null:
		return
	monster.invulnerable = true
	monster.dash_vel = Vector2.ZERO
	_dash_time = 0.0
	var child_ratio := float(act.get("child_ratio", 0.25))
	var count := 2
	for i in count:
		var ang := TAU * float(i) / float(count) + randf() * 0.6
		var pos: Vector2 = monster.position + Vector2.from_angle(ang) * (monster._radius + 110.0)
		pos = pos.clamp(Vector2(60, 60), GameConfig.ARENA_SIZE - Vector2(60, 60))
		var c := Monster.new()
		layer.add_child(c)
		c.setup(player, monster.monster_id, pos)
		c.make_split_child(child_ratio)
		_split_children.append(c)
	_split_timer = float(act.get("merge_time", 8.0))
	_split_children_merge_heal = float(act.get("merge_heal", 0.0))


var _split_children_merge_heal := 0.0


func _update_split(delta: float) -> void:
	_split_timer -= delta
	# 清理已消亡的小体引用
	var living: Array = []
	for c in _split_children:
		if is_instance_valid(c) and c.alive:
			living.append(c)
	_split_children = living

	# 小体全灭 → 提前解除无敌（玩家击杀奖励路径）
	if _split_children.is_empty():
		monster.invulnerable = false
		_split_timer = 0.0
		return

	# 合并时限到：小体回归本体（静默移除，不发击杀事件），按 merge_heal 恢复
	if _split_timer <= 0.0:
		for c in _split_children:
			if is_instance_valid(c):
				c.alive = false
				c.queue_free()
		_split_children = []
		if _split_children_merge_heal > 0.0:
			monster.hp = maxf(monster.hp, monster.max_hp * _split_children_merge_heal)
		monster.invulnerable = false


# ---------------- 工具 ----------------

## 招式是否在当前阶段启用（主宰按 BOSS5_PHASE_ACTIONS；其余全程启用）
func _action_enabled(aid: String) -> bool:
	if monster_cfg().get("phase_hp_ratios", []).is_empty():
		return true
	if monster.monster_id != "boss5":
		return true
	var table: Array = GameConfig.BOSS5_PHASE_ACTIONS
	if monster.phase_index >= table.size():
		return true
	return table[monster.phase_index].has(aid)


func _reset_cooldowns_for_phase() -> void:
	var actions: Array = monster_cfg().get("actions", [])
	for i in actions.size():
		_cds[i] = float(actions[i].get("cooldown", 5.0)) * 0.5   # 新阶段半冷却快速施压


func _spawn_projectile(pos: Vector2, vel: Vector2, damage: float) -> void:
	var layer := get_tree().get_first_node_in_group("enemy_projectile_layer")
	if layer == null:
		return
	var p := EnemyProjectile.new()
	layer.add_child(p)
	p.setup(pos, vel, damage)


func _spawn_projectile_later(pos: Vector2, vel: Vector2, damage: float, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): 
		if monster != null and is_instance_valid(monster) and monster.alive:
			_spawn_projectile(pos, vel, damage))


func _spawn_trail_zone() -> void:
	var act := _find_action("dash_charge")
	var trail_damage := float(act.get("trail_damage", 5.0)) if act != null else 5.0
	var zone := TrailZone.new()
	zone.init(monster.position, trail_damage)
	add_child(zone)


func _find_action(aid: String) -> Dictionary:
	for act in monster_cfg().get("actions", []):
		if String(act.get("id", "")) == aid:
			return act
	return {}


## 冲击环视觉（扩散圆环，无判定；伤害由全向弹幕承担）
func _show_expanding_ring(center: Vector2, radius: float) -> void:
	var ring := Line2D.new()
	ring.points = GameConfig.regular_polygon_points(28, radius * 0.25)
	ring.width = 7.0
	ring.default_color = Color(0.85, 0.55, 1.0, 0.85)
	ring.position = center
	var layer := get_tree().get_first_node_in_group("enemy_projectile_layer")
	(layer if layer != null else get_tree().current_scene).add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE * (radius / (radius * 0.25)), 0.45)
	tw.tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


# ================= 子节点：引力漩涡（吸玩家）=================

class VortexZone extends Node2D:
	## 敌方引力漩涡：范围内持续把玩家拉向中心（反向走位可挣脱）
	var radius := 120.0
	var pull := 180.0
	var life := 4.0
	var _player: Node2D = null
	var _poly: Polygon2D
	var _t := 0.0

	func init(center: Vector2, p_radius: float, p_pull: float, p_life: float, p_player: Node2D) -> void:
		position = center
		radius = p_radius
		pull = p_pull
		life = p_life
		_player = p_player

	func _ready() -> void:
		_poly = Polygon2D.new()
		_poly.polygon = GameConfig.regular_polygon_points(6, radius * 0.55)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/crystal_glow.gdshader")
		mat.set_shader_parameter("base_color", Color(0.72, 0.4, 1.0, 0.8))
		mat.set_shader_parameter("glow_strength", 1.6)
		mat.set_shader_parameter("rim_strength", 1.0)
		mat.set_shader_parameter("extent", radius * 0.6)
		_poly.material = mat
		add_child(_poly)

	func _physics_process(delta: float) -> void:
		life -= delta
		_t += delta
		_poly.rotation += delta * 3.5
		if life <= 0.0:
			queue_free()
			return
		if _player == null:
			return
		var to_center: Vector2 = position - _player.position
		if to_center.length() <= radius:
			_player.position += to_center.normalized() * pull * delta


# ================= 子节点：冲刺晶刃轨迹 =================

class TrailZone extends Area2D:
	## 冲刺斩留下的晶刃轨迹：触碰玩家造成一次伤害后消失
	var damage := 5.0
	var life := 0.9
	var _hit := false
	var _poly: Polygon2D

	func init(center: Vector2, p_damage: float) -> void:
		position = center
		damage = p_damage

	func _ready() -> void:
		collision_layer = 16
		collision_mask = 1
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 26.0
		shape.shape = circle
		add_child(shape)
		_poly = Polygon2D.new()
		_poly.polygon = GameConfig.regular_polygon_points(4, 20.0)
		_poly.rotation = randf() * TAU
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/crystal_glow.gdshader")
		mat.set_shader_parameter("base_color", Color(0.4, 0.98, 1.0, 0.9))
		mat.set_shader_parameter("glow_strength", 2.0)
		mat.set_shader_parameter("rim_strength", 0.9)
		mat.set_shader_parameter("extent", 22.0)
		_poly.material = mat
		add_child(_poly)
		area_entered.connect(_on_area_entered)

	func _physics_process(delta: float) -> void:
		life -= delta
		_poly.rotation += delta * 5.0
		if life <= 0.4:
			_poly.modulate.a = life / 0.4
		if life <= 0.0:
			queue_free()

	func _on_area_entered(area: Area2D) -> void:
		if _hit:
			return
		if area.is_in_group("player"):
			_hit = true
			area.take_damage(damage)
			queue_free()
