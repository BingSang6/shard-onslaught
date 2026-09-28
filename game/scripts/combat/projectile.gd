class_name Projectile
extends Area2D
## 晶刺投射物：青蓝色细长菱形，命中怪物造成伤害+击退；
## 携带「晶刺弹射」参数：命中后弹向下一只怪物（不重复命中）。

var velocity := Vector2.ZERO
var damage := 8.0
var knockback := 60.0
var lifetime := 1.8                        # 存活时间（约覆盖索敌范围）

# 弹射参数
var bounces := 0
var bounce_range := 0.0
var falloff := 1.0
var _hit_ids := []                         # 已命中过的怪物 id（防弹射回原目标）

# 弹种参数（《战斗循环增强任务书》§3：穿透/追踪/范围爆炸）
var pierce_left := 0                       # 剩余穿透目标数（命中后不减伤继续直飞）
var homing_turn := 0.0                     # 追踪转向速率（rad/s，0=不追踪）
var blast_radius := 0.0                    # 命中爆炸半径（0=单体）
var _poly: Polygon2D


func _ready() -> void:
	collision_layer = 4                    # 第 3 层：投射物
	collision_mask = 2                     # 检测怪物
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	add_child(shape)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(14, 0), Vector2(-8, 5), Vector2(-4, 0), Vector2(-8, -5)])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crystal_glow.gdshader")
	mat.set_shader_parameter("base_color", Color(0.55, 0.95, 1.0, 1.0))
	mat.set_shader_parameter("glow_strength", 2.0)
	mat.set_shader_parameter("rim_strength", 0.6)
	mat.set_shader_parameter("extent", 14.0)
	poly.material = mat
	add_child(poly)
	_poly = poly

	area_entered.connect(_on_area_entered)


func setup(pos: Vector2, p_velocity: Vector2, p_damage: float, p_knockback: float) -> void:
	position = pos
	velocity = p_velocity
	damage = p_damage
	knockback = p_knockback
	rotation = velocity.angle()


## 弹种参数：穿透数/追踪转向率/爆炸半径/弹色（巨型弹视觉放大）
func set_weapon(p_pierce: int, p_homing: float, p_blast: float, color: Color) -> void:
	pierce_left = p_pierce
	homing_turn = p_homing
	blast_radius = p_blast
	if _poly != null:
		var mat: ShaderMaterial = _poly.material
		mat.set_shader_parameter("base_color", Color(color, 1.0))
		if p_blast > 0.0:
			_poly.scale = Vector2(1.8, 1.8)
			mat.set_shader_parameter("extent", 24.0)


func set_ricochet(p_bounces: int, p_range: float, p_falloff: float) -> void:
	bounces = p_bounces
	bounce_range = p_range
	falloff = p_falloff


func _physics_process(delta: float) -> void:
	# 追踪弹种：向最近未命中怪物转向（转向速率 homing_turn rad/s）
	if homing_turn > 0.0:
		var target := _find_next_target(null)
		if target != null:
			var speed := velocity.length()
			var want := (target.position - position).normalized()
			var cur := velocity.normalized()
			var max_a := homing_turn * delta
			var new_dir := cur.slerp(want, clampf(max_a, 0.0, 1.0)).normalized()
			velocity = new_dir * speed
			rotation = velocity.angle()
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		if blast_radius > 0.0:
			_explode()
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	var m = area as Monster
	if m == null or not m.alive:
		return
	if _hit_ids.has(m.get_instance_id()):
		return
	_hit_ids.append(m.get_instance_id())
	GameEvents.projectile_hit.emit()  # 阶段4：命中音效
	m.take_damage(damage, velocity.normalized(), knockback)
	if blast_radius > 0.0:
		_explode(m)
		queue_free()
		return

	if bounces > 0:
		# 弹射：寻找下一只未命中过的怪物
		var next := _find_next_target(m)
		if next != null:
			bounces -= 1
			damage *= falloff
			var dir := (next.position - position).normalized()
			velocity = dir * velocity.length()
			rotation = velocity.angle()
			return
	elif pierce_left > 0:
		# 穿透：沿原弹道继续飞行（可再命中后续目标）
		pierce_left -= 1
		return
	queue_free()


## 巨型晶刺爆炸：半径 blast_radius 范围伤害（直接目标已单独结算）
func _explode(direct_target: Monster = null) -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		var mm = m as Monster
		if mm == null or not mm.alive or mm == direct_target or _hit_ids.has(mm.get_instance_id()):
			continue
		if position.distance_to(mm.position) <= blast_radius:
			_hit_ids.append(mm.get_instance_id())
			mm.take_damage(damage, (mm.position - position).normalized(), knockback)
	# 爆炸闪光（轻量：一次性扩散圆环，0.18s 自灭）
	var ring := Line2D.new()
	ring.points = GameConfig.regular_polygon_points(20, blast_radius)
	ring.width = 5.0
	ring.default_color = Color(0.95, 0.6, 1.0, 0.9)
	ring.position = position
	get_parent().add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.18)
	tw.tween_callback(ring.queue_free)


func _find_next_target(exclude: Monster) -> Node2D:
	var best: Node2D = null
	var best_d := bounce_range
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.alive or m == exclude or _hit_ids.has(m.get_instance_id()):
			continue
		var d: float = position.distance_to(m.position)
		if d < best_d:
			best_d = d
			best = m
	return best
