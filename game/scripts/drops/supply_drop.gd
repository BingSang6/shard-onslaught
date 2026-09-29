class_name SupplyDrop
extends Area2D
## 战术补给掉落物（《战斗循环增强任务书》§2）：
## heal=血包(回20) / magnet=磁石(全屏磁吸6s) / weapon=弹种道具(临时弹种8s) / shield=护盾碎片(+1层)
## 拾取同晶粒磁吸（磁石生效时全场吸附）；效果作用于玩家（DropManager 生成时注入）。

const TEXTURES := {
	"heal":   preload("res://assets/drops/drop_heal.png"),
	"magnet": preload("res://assets/drops/drop_magnet.png"),
	"shield": preload("res://assets/drops/drop_shield.png"),
	"weapon": preload("res://assets/drops/drop_weapon.png"),
}

var kind := "heal"                     # heal / magnet / shield / weapon
var lifetime := 20.0                   # 场上存在时间（比晶粒短，鼓励主动拾取）
var _player: Player = null
var _magnet := false
var _magnet_speed := 0.0
var _vel := Vector2.ZERO
var _bob_t := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	collision_layer = 8                    # 与晶粒同层（掉落物）
	collision_mask = 0
	monitoring = false
	add_to_group("supply_drops")

	# 外圈提示光晕（青绿柔光，与晶粒青蓝区分）
	var halo_script := preload("res://scripts/effects/halo.gd")
	var halo: Node2D = halo_script.create(64.0, Color(0.45, 1.0, 0.8), 0.9)
	add_child(halo)

	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURES.get(kind, TEXTURES["heal"])
	# 视觉直径约 46 世界单位（碰撞拾取半径 22）
	_sprite.scale = Vector2.ONE * GameConfig.sprite_scale(23.0, _sprite.texture.get_width())
	add_child(_sprite)


func setup(pos: Vector2, p_kind: String, p_player: Player) -> void:
	position = pos
	kind = p_kind
	_player = p_player
	_vel = Vector2.from_angle(randf() * TAU) * 90.0
	_bob_t = randf() * TAU


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if _player == null:
		return

	# 磁石增强：管理器全屏磁吸窗口内，任意距离开始吸附
	var dm := get_parent()
	if not _magnet and dm != null and dm.has_method("magnet_active") and dm.magnet_active():
		_magnet = true

	var to_player: Vector2 = _player.position - position
	var dist := to_player.length()
	if not _magnet and dist <= _player.pick_radius:
		_magnet = true

	if _magnet:
		_magnet_speed += GameConfig.DROP["magnet_accel"] * delta
		position += to_player.normalized() * _magnet_speed * delta
	else:
		position += _vel * delta
		_vel = _vel.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		_bob_t += delta * 2.6
		_sprite.position.y = sin(_bob_t) * 4.0
		_sprite.rotation += delta * 1.2

	# 拾取判定（同晶粒距离 22）
	if dist <= GameConfig.DROP["pickup_dist"]:
		_apply_effect()
		queue_free()


## 拾取效果（数值单点在 DROP_TABLE）
func _apply_effect() -> void:
	match kind:
		"heal":
			_player.heal(float(GameConfig.DROP_TABLE["heal_amount"]))   # heal() 自带上限截断（满血=无效果）
		"magnet":
			var dm := get_parent()
			if dm != null and dm.has_method("trigger_magnet"):
				dm.trigger_magnet()
		"shield":
			_player.add_shield_charge()          # 满 3 层时无效（正常消失）
		"weapon":
			var pool: Array = GameConfig.WEAPON_TYPES.keys()
			pool.erase("default")
			_player.equip_temp_weapon(pool[randi() % pool.size()])
