class_name DropManager
extends Node2D
## 掉落管理器（晶粒 + 战术补给两路）：
## 晶粒：怪物死亡掉经验晶粒；超限时最旧的自动飞向玩家回收（防 WebGL 堆积）。
## 补给（《战斗循环增强任务书》§2 + V0.8 空投增强）：计数伪随机触发 + 类型权重 + 残血保护 +
## 上限回收（8）+ 稀有保底（30 击杀）+ BOSS 必掉 + 关间空投 + 关内周期空投（wave_manager 调用）。

const Halo = preload("res://scripts/effects/halo.gd")

var player: Node2D = null

# ---- 补给掉落状态（数值单点在 GameConfig.DROP_TABLE）----
var _kill_counter := 0            # 击杀计数（伪随机触发用）
var _kills_since_rare := 0        # 距上次稀有的击杀数（pity 保底）
var magnet_until := -1.0          # 磁石全屏磁吸截止时刻（<0 = 未生效）


func _ready() -> void:
	GameEvents.monster_killed.connect(_on_monster_killed)


func _process(_delta: float) -> void:
	# 磁石窗口过期自然失效（时间用引擎钟：暂停时也不走 _process，语义正确）
	if magnet_until >= 0.0 and Time.get_ticks_msec() / 1000.0 > magnet_until:
		magnet_until = -1.0


## 磁石是否生效（晶粒/补给吸附查询）
func magnet_active() -> bool:
	return magnet_until >= 0.0 and Time.get_ticks_msec() / 1000.0 <= magnet_until


## 磁石拾取：全屏磁吸 magnet_duration 秒
func trigger_magnet() -> void:
	magnet_until = Time.get_ticks_msec() / 1000.0 + float(GameConfig.DROP_TABLE["magnet_duration"])


func _on_monster_killed(monster: Monster) -> void:
	if player == null:
		return
	# 场上晶粒超限：最旧的直接结算回收（视为自动拾取）
	var drops := get_tree().get_nodes_in_group("drops")
	while drops.size() >= GameConfig.DROP["max_drops"]:
		var oldest = drops.pop_front()
		if is_instance_valid(oldest):
			GameEvents.xp_gained.emit(oldest.xp_value)
			oldest.queue_free()

	var gem := CrystalDrop.new()
	add_child(gem)
	gem.setup(monster.position, monster.xp_value, player)
	# BOSS 掉落大晶粒（视觉放大 1.6 倍）
	if GameConfig.BOSSES.has(monster.monster_id) or monster.monster_id == "boss":
		gem.scale = Vector2(1.6, 1.6)
		# BOSS 必掉：1 血包 + 1 随机稀有（弹种道具）
		_spawn_supply(monster.position + Vector2(-40, 0), "heal")
		_spawn_supply(monster.position + Vector2(40, 0), "weapon")
		return

	# ---- 补给计数伪随机（小怪 5% / 大兽 15%；pity 30 击杀保底稀有）----
	_kill_counter += 1
	_kills_since_rare += 1
	var table: Dictionary = GameConfig.DROP_TABLE
	var chance := float(table["small_chance"]) if monster.monster_id == "small" \
			else float(table["big_chance"])
	if randf() < chance:
		_spawn_supply(monster.position, _roll_kind())


## 类型判定：稀有保底（连续 pity_count 击杀无稀有 → 必掉弹种道具）→ 稀有 20% 单独判定
## → 普通权重（血包60/磁石25/护盾15；残血 HP<30% 血包权重×3）
func _roll_kind() -> String:
	var table: Dictionary = GameConfig.DROP_TABLE
	if _kills_since_rare >= int(table["pity_count"]):
		_kills_since_rare = 0
		return "weapon"
	if randf() < float(table["rare_chance"]):
		_kills_since_rare = 0
		return "weapon"
	var weights: Dictionary = table["weights"]
	var heal_w := float(weights["heal"])
	if player != null and player.hp < player.max_hp * float(table["low_hp_ratio"]):
		heal_w *= float(table["low_hp_heal_mult"])     # 残血保护：血包权重 ×3
	var total := heal_w + float(weights["magnet"]) + float(weights["shield"])
	var roll := randf() * total
	if roll < heal_w:
		return "heal"
	roll -= heal_w
	if roll < float(weights["magnet"]):
		return "magnet"
	return "shield"


## 生成补给（场上上限 max_drops=8，超出回收最旧）
func _spawn_supply(pos: Vector2, kind: String) -> void:
	var supplies := get_tree().get_nodes_in_group("supply_drops")
	while supplies.size() >= int(GameConfig.DROP_TABLE["max_drops"]):
		var oldest = supplies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var s := SupplyDrop.new()
	add_child(s)
	s.setup(pos, kind, player)


## 补给空投（V0.8 任务书模块A）：
## - use_pool=true + near=false：关内周期空投——空投池权重、落点 320~420px、0.8s 落点光圈预警
## - use_pool=true + near=true ：关间过渡空投——过渡权重（heal 为主）、落点 140~280px、2~3 个、无预警
## - use_pool=false：旧关间逻辑保留（1~2 个血包/磁石，兼容旧调用）
func airdrop(use_pool := true, near := false) -> void:
	if player == null:
		return
	if not use_pool:
		var legacy_count := 1 + (randi() % 2)
		for i in legacy_count:
			var c: Vector2 = player.position + Vector2.from_angle(randf() * TAU) * randf_range(140.0, 280.0)
			c = c.clamp(Vector2(60, 60), GameConfig.ARENA_SIZE - Vector2(60, 60))
			_spawn_supply(c, "heal" if randf() < 0.5 else "magnet")
		return

	var t: Dictionary = GameConfig.AIRDROP_TABLE
	var weights: Dictionary = t["transition_weights"] if near else t["weights"]
	var count_pool: Array = t["transition_count"] if near else t["drop_count"]
	var dist_min := float(t["transition_min_dist"] if near else t["min_dist"])
	var dist_max := float(t["transition_max_dist"] if near else t["max_dist"])
	var count: int = count_pool[randi() % count_pool.size()]
	for i in count:
		var center: Vector2 = player.position + Vector2.from_angle(randf() * TAU) * randf_range(dist_min, dist_max)
		# 多个补给沿落点左右散开 ±45px（任务书 A1），保持各自拾取间距
		if i % 2 == 1:
			center += Vector2(45.0, 0.0)
		elif i > 0:
			center += Vector2(-45.0, 0.0)
		center = center.clamp(Vector2(60, 60), GameConfig.ARENA_SIZE - Vector2(60, 60))
		if near:
			_spawn_supply(center, _roll_from_weights(weights))        # 过渡期无怪：直接落地方便拾取
		else:
			_spawn_airdrop_marker(center, _roll_from_weights(weights))  # 关内：先光圈预警 0.8s 再落地
	GameEvents.airdrop_arrived.emit()


## 权重表随机取键（空投池/过渡池共用）
func _roll_from_weights(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return String(weights.keys()[0])


## 落点预警光圈（0.8s 缩放脉动）→ 到点生成补给实体（V0.8 A1："天上要掉东西"的期待感）
func _spawn_airdrop_marker(pos: Vector2, kind: String) -> void:
	var marker := Node2D.new()
	add_child(marker)
	marker.position = pos
	var halo: Node2D = Halo.create(90.0, Color(0.55, 1.0, 0.75), 1.4)
	marker.add_child(halo)
	halo.scale = Vector2(1.3, 1.3)
	var tw := marker.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(halo, "scale", Vector2(0.8, 0.8), 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(halo, "scale", Vector2(1.25, 1.25), 0.4).set_trans(Tween.TRANS_SINE)
	# 预警结束：光圈退场 + 补给实体出现（真实时钟，升级暂停期间照常落地）
	var warn := get_tree().create_timer(float(GameConfig.AIRDROP_TABLE["warn_time"]))
	warn.timeout.connect(func() -> void:
		if is_instance_valid(marker):
			marker.queue_free()
		if player != null:
			_spawn_supply(pos, kind))
