class_name CrystalDrop
extends Area2D
## 晶粒掉落物：小型青蓝晶体，拾取增加经验。
## 表现：弹出初速度 + 摩擦停下 + 上下浮动；被玩家磁吸范围吸附后加速飞向玩家。


var xp_value := 1.0
var lifetime := 25.0

var _vel := Vector2.ZERO
var _magnet := false
var _magnet_speed := 0.0
var _bob_t := 0.0
var _player: Node2D = null
var _poly: Polygon2D


func _ready() -> void:
	collision_layer = 8                    # 第 4 层：掉落物
	collision_mask = 0                     # 拾取由 DropManager 主动查询（避免高频信号）
	monitoring = false
	add_to_group("drops")

	_poly = Polygon2D.new()
	_poly.polygon = GameConfig.regular_polygon_points(4, 8.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crystal_glow.gdshader")
	mat.set_shader_parameter("base_color", Color(0.25, 0.9, 1.0, 1.0))
	mat.set_shader_parameter("glow_strength", 1.8)
	mat.set_shader_parameter("rim_strength", 0.9)
	mat.set_shader_parameter("extent", 8.0)
	_poly.material = mat
	add_child(_poly)


func setup(pos: Vector2, p_xp: float, p_player: Node2D) -> void:
	position = pos
	xp_value = p_xp
	_player = p_player
	_vel = Vector2.from_angle(randf() * TAU) * GameConfig.DROP["pop_speed"]
	_bob_t = randf() * TAU


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if _player == null:
		return

	var to_player: Vector2 = _player.position - position
	var dist := to_player.length()

	# 磁石全屏磁吸（DropManager 窗口）：任意距离吸附，加速度 ×3
	var dm := get_parent()
	var global_magnet: bool = dm != null and dm.has_method("magnet_active") and dm.magnet_active()

	# 磁吸：进入玩家拾取半径后加速飞向玩家
	if not _magnet and (dist <= _player.pick_radius or global_magnet):
		_magnet = true
	if _magnet:
		var accel: float = GameConfig.DROP["magnet_accel"] * (3.0 if global_magnet else 1.0)
		_magnet_speed += accel * delta
		position += to_player.normalized() * _magnet_speed * delta
	else:
		# 弹出 → 摩擦停下 → 待机浮动
		position += _vel * delta
		_vel = _vel.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		_bob_t += delta * 3.0
		_poly.position.y = sin(_bob_t) * 3.0
		_poly.rotation += delta * 1.5

	# 拾取判定
	if dist <= GameConfig.DROP["pickup_dist"]:
		GameEvents.xp_gained.emit(xp_value)
		queue_free()
