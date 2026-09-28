extends Node
## 技能：引力漩涡（主动·控制，短视频高光核心之一）

const Halo = preload("res://scripts/effects/halo.gd")
## 周期性在怪物密集处生成紫色引力场，将范围内怪物持续吸向中心——
## 与「碎裂引爆」组合可打出全屏多米诺连锁爆炸（PRD 2.2 最强组合）。
## 生成策略：优先落在怪物最密集的位置（用最旧的怪物做候选采样）。

var skills: Node = null                     # SkillManager 引用（由其注入）

var _cd_timer := 1.5                        # 开局短暂延迟后先放一个


func _physics_process(delta: float) -> void:
	if skills == null or skills.player == null:
		return
	var lv: int = skills.get_level("vortex")
	if lv <= 0:
		return
	_cd_timer -= delta
	if _cd_timer <= 0.0:
		var p := GameConfig.skill_params("vortex", lv)
		_cd_timer = float(p["cooldown"])
		trigger()


## 立即生成一个引力漩涡（优先怪物群中心，否则玩家前方）
func trigger() -> void:
	var lv: int = maxi(1, skills.get_level("vortex"))
	var p := GameConfig.skill_params("vortex", lv)
	var center: Variant = _find_cluster_center(float(p["radius"]))
	if center == null:
		center = skills.player.position + Vector2.from_angle(randf() * TAU) * 140.0
	var zone := VortexZone.new()
	zone.setup(center, float(p["radius"]), float(p["pull"]), float(p["duration"]))
	add_child(zone)


## 简易聚类：随机采样存活怪物，取周边邻居最多的一只的位置
func _find_cluster_center(radius: float) -> Variant:
	var alive_list: Array = []
	for m in get_tree().get_nodes_in_group("monsters"):
		# 过滤掉本帧待销毁的怪物（清场/连锁死亡瞬间群组里仍有尸体）
		if m.alive:
			alive_list.append(m)
	if alive_list.is_empty():
		return null
	var best_pos: Variant = null
	var best_score := 0
	for i in 6:
		var m = alive_list[randi() % alive_list.size()]
		var score := 0
		for other in alive_list:
			if m.position.distance_to(other.position) <= radius:
				score += 1
		if score > best_score:
			best_score = score
			best_pos = m.position
	return best_pos


# ---------------- 漩涡场本体 ----------------

class VortexZone extends Node2D:
	var radius := 130.0
	var pull := 180.0
	var duration := 3.0

	var _t := 0.0
	var _poly: Polygon2D

	func _ready() -> void:
		_poly = Polygon2D.new()
		_poly.polygon = GameConfig.circle_points(radius)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/vortex.gdshader")
		mat.set_shader_parameter("vortex_color", Color(0.6, 0.13, 0.87, 1.0))
		mat.set_shader_parameter("extent", radius)
		mat.set_shader_parameter("spin_speed", 5.0)
		_poly.material = mat
		add_child(_poly)

		# 中心紫色光斑（漩涡核心辉光，双层：亮核 + 外圈淡紫大光晕）
		var core := Halo.create(radius * 0.7, Color(0.72, 0.25, 0.95, 1.0), 1.35)
		add_child(core)
		var outer := Halo.create(radius * 1.25, Color(0.6, 0.13, 0.87, 1.0), 0.4)
		add_child(outer)

		# 吸入粒子：紫色碎片被吸向中心（增强"吸附"感知）
		var suck := GPUParticles2D.new()
		suck.amount = 40
		suck.lifetime = 0.9
		suck.local_coords = false
		var smat := ParticleProcessMaterial.new()
		smat.direction = Vector3(0, 1, 0)
		smat.spread = 180.0
		smat.gravity = Vector3.ZERO
		smat.initial_velocity_min = 120.0
		smat.initial_velocity_max = 220.0
		smat.scale_min = 0.5
		smat.scale_max = 1.2
		smat.color = Color(0.8, 0.45, 1.0, 0.9)
		suck.process_material = smat
		suck.texture = GameConfig.diamond_texture(10)
		smat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		smat.emission_sphere_radius = radius * 0.8
		add_child(suck)

		scale = Vector2(0.1, 0.1)

	func setup(pos: Vector2, p_radius: float, p_pull: float, p_duration: float) -> void:
		position = pos
		radius = p_radius
		pull = p_pull
		duration = p_duration

	func _physics_process(delta: float) -> void:
		_t += delta
		# 出现/消失的缩放过渡
		var target := 1.0 if _t > 0.25 else _t / 0.25
		if _t > duration:
			target = maxf(0.0, 1.0 - (_t - duration) / 0.3)
		scale = scale.lerp(Vector2.ONE * target, minf(1.0, delta * 12.0))
		if _t > duration + 0.3:
			queue_free()
			return
		if _t < 0.15 or _t > duration:
			return
		# 引力：范围内怪物向中心聚集（越近吸力越强，模拟向心坠落）
		for m in get_tree().get_nodes_in_group("monsters"):
			if not m.alive:
				continue
			var to_center: Vector2 = position - m.position
			var d := to_center.length()
			if d <= radius and d > 4.0:
				var strength := pull * (1.0 - 0.5 * d / radius)
				m.position += to_center.normalized() * strength * delta
