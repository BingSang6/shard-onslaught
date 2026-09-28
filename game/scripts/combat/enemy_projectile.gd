class_name EnemyProjectile
extends Area2D
## 敌方晶弹（BOSS 招式弹幕：扇形/扩散环/旋臂/晶雨共用）
## 紫红色晶体碎片，命中玩家造成伤害后消失；出场地边界自毁。

var velocity := Vector2.ZERO
var damage := 12.0
var lifetime := 6.0

var _poly: Polygon2D


func _ready() -> void:
	collision_layer = 16                   # 第 5 层：敌方弹幕（玩家投射物=4/掉落物=8）
	collision_mask = 1                     # 检测玩家
	add_to_group("enemy_projectiles")
	# 稍大的碰撞半径（竖屏割草：弹幕判定宽松一点，视觉可辨）
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	add_child(shape)

	_poly = Polygon2D.new()
	_poly.polygon = GameConfig.regular_polygon_points(3, 10.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crystal_glow.gdshader")
	mat.set_shader_parameter("base_color", Color(0.92, 0.4, 0.98, 1.0))
	mat.set_shader_parameter("glow_strength", 2.2)
	mat.set_shader_parameter("rim_strength", 0.8)
	mat.set_shader_parameter("extent", 11.0)
	_poly.material = mat
	add_child(_poly)

	area_entered.connect(_on_area_entered)


func setup(pos: Vector2, p_velocity: Vector2, p_damage: float) -> void:
	position = pos
	velocity = p_velocity
	damage = p_damage
	rotation = velocity.angle()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_poly.rotation += delta * 7.0          # 自转（碎片感）
	lifetime -= delta
	# 超时或飞出场地（含余量）自毁
	if lifetime <= 0.0 or position.x < -80.0 or position.y < -80.0 \
			or position.x > GameConfig.ARENA_SIZE.x + 80.0 \
			or position.y > GameConfig.ARENA_SIZE.y + 80.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player"):
		area.take_damage(damage)
		queue_free()
