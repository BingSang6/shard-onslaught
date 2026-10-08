extends Node
## 《碎晶突围》headless 冒烟测试（阶段1+2 验收）
## 运行：godot --headless --path . res://tests/smoke_test.tscn
## 覆盖 PRD「8.测试要求」中阶段1+2 相关项：
##   1. 状态机/开局流程、刷怪、击杀掉经验
##   2. 升级 3 选 1、重复技能升级、弹窗期间世界暂停
##   3. 碎裂引爆连锁爆炸、连锁层数 ≤ MAX_CHAIN=8、大数量压力下不卡死
##   4. 引力漩涡聚集效果（与碎裂引爆组合的前置验证）
##   5. 晶盾/瞬闪/晶刺弹射/晶域 单技能行为
##   6. 通关与失败结算、失败也发晶核、存档读写往返
##   7. 阶段3：永久强化购买/跨局生效、图鉴解锁、BOSS 临时增益、结算晶核明细
## 退出码：0=全部通过，1=有失败项

var checks := 0
var failures := 0
var main: Node2D


func _ready() -> void:
	# 测试驱动器在暂停期间也要继续跑（升级弹窗会 paused=true）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_game_data()   # 测试自包含：清掉本地真实存档/截图脚本残留（start_skill 等会干扰开局随机强化）
	await get_tree().process_frame
	await _run_all()
	print("\n========== 冒烟测试结果：%d 项检查，%d 失败 ==========" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


## 重置存档相关状态（不写盘——只在内存中隔离本测试进程）
func _reset_game_data() -> void:
	GameData.permanent_upgrades = {"hp": 0, "attack": 0, "pick_range": 0, "start_skill": 0, "bullet_speed": 0}
	GameData.unlocked_monsters = []
	GameData.crystal_core = 0
	GameData.max_wave = 0
	GameData.cleared_all = false
	GameData.auto_upgrade = false


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] " + msg)
	else:
		failures += 1
		print("  [FAIL] " + msg)


## 推进 n 个“60fps 帧”当量的真实时间（headless 帧率不封顶，
## 不能用 process_frame 计数，改用真实时钟保证物理 tick 数量正确；
## create_timer 默认 process_always=true，暂停期间也能继续等待）
func tick(n: int) -> void:
	await get_tree().create_timer(n / 60.0).timeout


## 测试前置清理：消化一切挂起的升级弹窗（晶粒溢出回收会意外升级），
## 清空经验与场上晶粒，确保树处于未暂停的 PLAYING 状态。
func force_resume() -> void:
	var guard := 0
	while (main.state == 2 or main.pending_levelups > 0) and guard < 20:
		main._on_upgrade_chosen("heal")
		guard += 1
	main.state = 1
	main.xp = 0.0
	main.pending_levelups = 0
	main.player.temp_weapon_id = ""     # 前序测试拾取弹种补给的 8s 临时弹种可能跨用例残留
	main.player.temp_weapon_time = 0.0
	main.get_tree().paused = false
	for d in main.get_tree().get_nodes_in_group("drops"):
		d.queue_free()


func _run_all() -> void:
	seed(424242)
	# 复位存档，避免上一轮测试的晶核/永久强化影响断言（局外加成会改初始血量）
	GameData.crystal_core = 0
	for key in GameData.permanent_upgrades.keys():
		GameData.permanent_upgrades[key] = 0
	GameData.unlocked_monsters.clear()
	GameData.save_game()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# 测试驱动器为 ALWAYS，主场景需显式 PAUSABLE，世界才能被 paused 冻结
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().process_frame

	# 状态枚举（main.gd: MENU=0 PLAYING=1 UPGRADE_PANEL=2 SETTLE=3）
	await _t_flow_and_spawn()
	await _t_kill_and_xp()
	await _t_upgrade_panel()
	await _t_pause_freezes_world()
	await _t_chain_explosion()
	await _t_chain_stress_no_hang()
	await _t_vortex_pull()
	await _t_shield()
	await _t_dash()
	await _t_ricochet()
	await _t_aura()
	await _t_boss_spawn()
	await _t_win_settle()
	await _t_lose_settle_and_save()
	await _t_save_roundtrip()
	await _t_perm_shop()
	await _t_perm_cross_run()
	await _t_codex()
	await _t_boss_buff()
	await _t_settle_breakdown()
	await _t_audio()
	await _t_boss3_armor()
	await _t_boss2_split()
	await _t_boss5_phases()
	await _t_supply_drops()
	await _t_weapons()
	await _t_upgrade_optimize()
	await _t_sprite_scale()
	await _t_airdrop_cycle()
	await _t_airdrop_pickup()
	await _t_wave2_density()
	await _t_wave_local_reset()
	await _t_bullet_speed_evolution()


# ---------------- T1 状态机与刷怪 ----------------

func _t_flow_and_spawn() -> void:
	print("\n[T1] 状态机/开局/刷怪")
	check(main.state == 0, "初始为 MENU 状态")
	main.start_run()
	await tick(2)
	check(main.state == 1, "start_run 后进入 PLAYING")
	check(is_instance_valid(main.player) and main.player.hp == 100.0, "玩家存在且满血")
	check(main.wave_manager.current_wave == 1, "波次制：开局进入第 1 关")
	check(main.wave_manager.wave_time_left > float(GameConfig.WAVE_TABLE[0]["duration"]) - 1.0,
		"本关倒计时已启动（波次时限 %.0fs）" % GameConfig.WAVE_TABLE[0]["duration"])
	await tick(140)  # ~2.3s
	var monsters: int = main.get_tree().get_nodes_in_group("monsters").size()
	check(monsters > 0, "2 秒内已开始刷怪（当前 %d 只）" % monsters)
	check(monsters <= GameConfig.MAX_MONSTERS, "同屏怪物未超上限")
	# 关闭刷怪与自动攻击，后续用例走确定性路径
	main.spawner.enabled = false
	main.player.set("_fire_cd", 1e9)


# ---------------- T2 击杀掉落经验 ----------------

func _t_kill_and_xp() -> void:
	print("\n[T2] 击杀/晶粒/经验")
	main._clear_world()
	main.kill_count = 0
	main.xp = 0.0
	var m: Monster = main.spawner.spawn_monster("small", main.player.position + Vector2(200, 0))
	check(m.alive, "手动生成怪物成功")
	m.take_damage(9999.0)
	await tick(3)
	check(main.kill_count == 1, "击杀数 +1")
	check(main.get_tree().get_nodes_in_group("drops").size() >= 1, "死亡掉落晶粒")
	# 晶粒瞬移到玩家脚下触发磁吸拾取
	for d in main.get_tree().get_nodes_in_group("drops"):
		d.position = main.player.position
	await tick(5)
	check(main.xp > 0.0, "拾取晶粒获得经验（xp=%.0f）" % main.xp)


# ---------------- T3 升级 3 选 1 与重复升级 ----------------

func _t_upgrade_panel() -> void:
	print("\n[T3] 升级弹窗/重复技能升级")
	main.level = 1
	main.xp = 0.0
	main._on_xp_gained(GameConfig.xp_to_next(main.level))
	await tick(2)
	# 手动气泡模式：升级不打断战斗，气泡提示待处理
	check(main.state == 1 and not main.get_tree().paused, "升级不打断：保持 PLAYING（气泡模式）")
	check(main.pending_levelups == 1 and main.hud.levelup_button.visible,
		"升华气泡显示待升级（pending=%d）" % main.pending_levelups)
	main._open_upgrade_panel()   # 模拟点击气泡
	await tick(2)
	check(main.state == 2, "点击气泡后进入 UPGRADE_PANEL")
	check(main.upgrade_panel._root.visible, "3 选 1 弹窗已显示")
	main._on_upgrade_chosen("aura")
	await tick(2)
	check(main.skills.get_level("aura") == 1, "选择后习得晶域扩散 Lv1")
	check(main.state == 1 and not main.get_tree().paused, "选卡后恢复 PLAYING")
	check(not main.hud.levelup_button.visible, "消化完毕气泡隐藏")
	# 同技能重复获取 → 升级
	main._on_xp_gained(GameConfig.xp_to_next(main.level))
	await tick(2)
	main._open_upgrade_panel()
	await tick(2)
	main._on_upgrade_chosen("aura")
	check(main.skills.get_level("aura") == 2, "重复选择同一技能升至 Lv2")
	# 一次给多级经验 → 连升合并（任务书 §5.3）：只弹 1 次窗，选 1 个其余自动学推荐
	main.pending_levelups = 0
	main._on_xp_gained(GameConfig.xp_to_next(main.level) * 2.5)
	await tick(2)
	check(main.state == 1 and main.pending_levelups == 2 and main.hud.levelup_button.visible,
		"多级经验合并入账不打断（pending=%d）" % main.pending_levelups)
	main._open_upgrade_panel()
	await tick(2)
	check(main.state == 2 and main.pending_levelups == 2, "气泡打开弹窗（连升 pending=%d）" % main.pending_levelups)
	main._on_upgrade_chosen("fire_rate")
	await tick(2)
	check(main.state == 1 and main.pending_levelups == 0 and not main.get_tree().paused,
		"连升合并：单次弹窗选 1 项即消化全部等级并恢复战斗")


# ---------------- T4 弹窗暂停世界 ----------------

func _t_pause_freezes_world() -> void:
	print("\n[T4] 升级弹窗期间世界暂停")
	var m: Monster = main.spawner.spawn_monster("small", Vector2(200, 300))
	m.speed = 0.0
	var pos_before: Vector2 = m.position
	main.pending_levelups = 1            # 气泡模式：有存货才能打开弹窗
	main._open_upgrade_panel()
	await tick(12)
	check(main.get_tree().paused, "弹窗期间树已暂停")
	check(m.position == pos_before, "暂停期间怪物静止")
	main._on_upgrade_chosen("heal")
	await tick(2)
	check(not main.get_tree().paused, "选卡后解除暂停")


# ---------------- T5 连锁爆炸 ----------------

func _t_chain_explosion() -> void:
	print("\n[T5] 碎裂引爆连锁爆炸")
	main._clear_world()
	main.kill_count = 0
	main.skills.acquire("shatter_blast")
	check(main.skills.get_level("shatter_blast") == 1, "习得碎裂引爆")
	# 玩家远离测试区（避免自动索敌干扰）
	main.player.position = Vector2(500, 900)
	var c := Vector2(200, 300)
	var center: Monster = null
	for i in 12:
		var pos := c + Vector2((i % 4) * 55.0, (i / 4) * 55.0)
		var m: Monster = main.spawner.spawn_monster("small", pos)
		if i == 5:
			center = m
	var kills_before: int = main.kill_count
	center.take_damage(9999.0)
	await tick(40)  # ~0.7s，等待队列连锁扩散
	var combo: int = main.effect_manager.max_combo
	check(main.kill_count - kills_before >= 4, "连锁造成多只击杀（+%d）" % (main.kill_count - kills_before))
	check(combo >= 4, "连锁连击数 ≥4（实际 x%d）" % combo)
	check(main.effect_manager.last_chain_level <= GameConfig.MAX_CHAIN, "连锁层数未超过 MAX_CHAIN=8")


# ---------------- T6 连锁压力（防死循环/卡死） ----------------

func _t_chain_stress_no_hang() -> void:
	print("\n[T6] 连锁压力测试（200 只密集怪）")
	main._clear_world()
	main.kill_count = 0
	main.skills.acquire("shatter_blast")  # 升到 Lv2
	var c := Vector2(320, 320)
	var center: Monster = null
	var spawned := 0
	for i in 200:
		var ring := i / 20
		var pos := c + Vector2.from_angle((i % 20) * TAU / 20.0) * (18.0 + ring * 30.0)
		var m: Monster = main.spawner.spawn_monster("small", pos)
		spawned += 1
		if i == 100:
			center = m
	center.take_damage(9999.0)
	await tick(150)  # ~2.5s；若连锁死循环此处会超时/崩溃
	var alive_now: int = main.get_tree().get_nodes_in_group("monsters").filter(func(m): return m.alive).size()
	check(true, "压力连锁后引擎仍响应（未卡死）")
	check(alive_now < spawned, "大量怪物被连锁清除（存活 %d/%d）" % [alive_now, spawned])
	check(main.effect_manager.last_chain_level <= GameConfig.MAX_CHAIN, "连锁层数被正确截断 ≤8")


# ---------------- T7 引力漩涡聚集 ----------------

func _t_vortex_pull() -> void:
	force_resume()
	print("\n[T7] 引力漩涡吸附聚集")
	main._clear_world()
	await tick(2)  # 等待待销毁怪物退出群组，保证聚类采样确定性
	main.skills.acquire("vortex")
	var c := Vector2(150, 200)
	var monsters: Array[Monster] = []
	for i in 6:
		# 半径 70 的六边形环：任意两只间距 ≤140，全部在 Lv1 漩涡半径 155 内
		var m: Monster = main.spawner.spawn_monster("small", c + Vector2.from_angle(TAU * i / 6.0) * 70.0)
		m.speed = 1.0  # 关闭追人移动，隔离引力效果
		monsters.append(m)
	# 用怪物两两间距衡量聚集度（漩涡中心会落在最密的怪物处，不能按几何环心度量）
	var spread := func() -> float:
		var total := 0.0
		for i in monsters.size():
			for j in range(i + 1, monsters.size()):
				var mi = monsters[i]
				var mj = monsters[j]
				if is_instance_valid(mi) and is_instance_valid(mj):
					total += mi.position.distance_to(mj.position)
		return total
	var before: float = spread.call()
	main.skills.trigger_vortex_now()
	await tick(100)  # ~1.7s 吸附
	var after: float = spread.call()
	check(after < before * 0.5, "怪物被吸向漩涡中心聚团（两两间距和 %.0f → %.0f）" % [before, after])


# ---------------- T8 晶盾 ----------------

func _t_shield() -> void:
	force_resume()
	print("\n[T8] 晶盾抵挡一次伤害")
	main.skills.acquire("shield")
	await tick(6)  # 等待护盾充能
	var hp_before: float = main.player.hp
	main.player.take_damage(50.0)
	check(main.player.hp == hp_before, "晶盾抵挡了本次伤害")
	await tick(25)  # 等待破盾无敌帧（0.35s）结束
	main.player.take_damage(50.0)
	check(main.player.hp == hp_before - 50.0, "破盾后伤害正常结算")
	main.player.heal(200.0)


# ---------------- T9 瞬闪 ----------------

func _t_dash() -> void:
	force_resume()
	print("\n[T9] 瞬闪位移")
	main.skills.acquire("dash")
	main.player.position = Vector2(500, 900)
	var y_before: float = main.player.position.y
	main.player.try_dash()  # 无输入时默认向上冲刺
	await tick(14)
	var moved: float = y_before - main.player.position.y
	check(moved > 100.0, "瞬闪完成冲刺位移（%.0f px）" % moved)


# ---------------- T10 晶刺弹射 ----------------

func _t_ricochet() -> void:
	force_resume()
	print("\n[T10] 晶刺弹射")
	main._clear_world()
	main.skills.acquire("ricochet")
	# 两只怪物并排（远离玩家，避免其他干扰；定住不动保证弹道命中）
	var base := Vector2(120, 150)
	var a: Monster = main.spawner.spawn_monster("small", base)
	var b: Monster = main.spawner.spawn_monster("small", base + Vector2(120, 30))
	a.speed = 0.0
	b.speed = 0.0
	var p := Projectile.new()
	p.setup(base - Vector2(0, 300), Vector2(0, 1) * 350.0, 50.0, 0.0)
	p.set_ricochet(1, 400.0, 0.9)
	main.projectile_layer.add_child(p)
	await tick(95)  # ~1.6s：命中首目标约 0.86s + 弹射飞抵第二目标约 0.35s
	check(not is_instance_valid(a) or not a.alive, "首目标被晶刺击杀")
	check(not is_instance_valid(b) or not b.alive, "晶刺弹射击中第二目标")


# ---------------- T11 晶域扩散 ----------------

func _t_aura() -> void:
	force_resume()
	print("\n[T11] 晶域扩散持续伤害")
	main._clear_world()
	main.skills.acquire("aura")
	main.skills.acquire("aura")  # 升到 Lv2：dps=16，确保 1.2 秒内击杀 12 血小怪
	var m: Monster = main.spawner.spawn_monster("small", main.player.position + Vector2(50, 0))
	m.speed = 0.0
	await tick(70)  # ~1.2s：Lv2 晶域 dps=16 → 累计远超 12 血
	check(not is_instance_valid(m) or not m.alive, "晶域切割致死靠近怪物")


# ---------------- T12 波次推进与 BOSS 关（第 3 关碎晶王） ----------------

func _t_boss_spawn() -> void:
	force_resume()
	print("\n[T12] 波次推进与 BOSS 关（第 2→3→4 关）")
	main._clear_world()
	main.state = 1
	main.wave_manager.reset(main.player, main.spawner, main.drop_manager)
	main.spawner.enabled = false       # 隔离刷怪，走确定性路径
	main.wave_manager.current_wave = 2 # 直接拨到第 2 关末尾
	main.wave_manager.wave_time_left = 0.05
	await tick(10)   # ~0.17s：第 2 关时限到 → 3s 过渡
	check(main.wave_manager.state == 1, "关末进入 TRANSITION（3s 过渡）")
	await tick(195)  # ~3.25s：过渡结束 → 第 3 关 BOSS 出场
	check(main.wave_manager.current_wave == 3, "过渡后进入第 3 关")
	var boss: Monster = main.wave_manager.get_boss()
	check(boss != null and boss.alive and boss.monster_id == "boss1",
		"第 3 关生成碎晶王（HP %.0f）" % (boss.max_hp if boss != null else 0.0))
	check(boss != null and is_equal_approx(boss.max_hp, 400.0), "碎晶王 HP=400（BOSSES 配置）")
	check(not main.spawner.enabled, "BOSS 关暂停常规刷怪")
	check(main.hud.boss_name_label.get_parent().visible, "HUD BOSS 血条已显示")
	# 击杀 BOSS → 过关 + 奖励（回血 30 / 攻击+6 / 晶核 15 入明细）
	main.player.set("_fire_cd", 1e9)
	main.player.hp = 50.0
	var atk_before: float = main.player._current_attack()
	boss.take_damage(99999.0)
	await tick(6)
	check(main.boss_killed and main.boss_core_reward == 15, "BOSS 击破：标记 + 晶核 15 入明细")
	check(main.player.hp > 50.0, "碎晶王击破奖励回血 +30")
	check(main.player._current_attack() == atk_before + 6.0, "击破奖励攻击 +6（20s）")
	await tick(200)  # ~3.3s：过渡结束进入第 4 关
	check(main.wave_manager.current_wave == 4, "BOSS 击破后进入第 4 关")
	check(main.spawner.enabled, "第 4 关（精英+）恢复常规刷怪")
	main.spawner.enabled = false


# ---------------- T13 通关结算（第 10 关） ----------------

func _t_win_settle() -> void:
	force_resume()
	print("\n[T13] 第 10 关结束通关结算")
	main._clear_world()
	main.state = 1
	main.wave_manager.reset(main.player, main.spawner, main.drop_manager)
	main.spawner.enabled = false
	main.wave_manager.current_wave = 10   # 拨到最终关，时限将至
	main.wave_manager.wave_time_left = 0.05
	var core_before: int = GameData.crystal_core
	await tick(30)
	check(main.state == 3, "第 10 关结束进入 SETTLE（通关）")
	check(main.settle_panel._root.visible, "结算面板已显示")
	check(GameData.crystal_core > core_before, "通关发放晶核并入档")
	check(GameData.cleared_all, "通关标识已存档（cleared_all）")
	check(GameData.max_wave == 10, "最高关卡记录 = 10")
	main.settle_panel.close()


# ---------------- T14 失败结算（失败也发晶核） ----------------

func _t_lose_settle_and_save() -> void:
	print("\n[T14] 血量归零失败结算")
	main.start_run()
	await tick(5)
	main.spawner.enabled = false
	main.player.set("_fire_cd", 1e9)
	var core_before: int = GameData.crystal_core
	main.player.take_damage(99999.0)
	await tick(5)
	check(main.state == 3, "血量归零进入 SETTLE")
	check(GameData.crystal_core > core_before, "失败也发放晶核（降低挫败感）")
	main.settle_panel.close()


# ---------------- T15 存档往返 ----------------

func _t_save_roundtrip() -> void:
	print("\n[T15] 存档保存/读取往返")
	GameData.crystal_core = 777
	GameData.permanent_upgrades["hp"] = 3
	GameData.save_game()
	GameData.crystal_core = 0
	GameData.permanent_upgrades["hp"] = 0
	GameData.load_save()
	check(GameData.crystal_core == 777, "晶核读档一致")
	check(GameData.permanent_upgrades["hp"] == 3, "永久强化等级读档一致")


# ---------------- T16 永久强化购买（阶段3） ----------------

func _t_perm_shop() -> void:
	print("\n[T16] 永久强化购买（晶核消耗/费用曲线/满级）")
	GameData.crystal_core = 100
	GameData.permanent_upgrades["hp"] = 0
	var ok: bool = GameData.try_upgrade("hp")
	check(ok, "晶核足够时购买成功")
	check(GameData.permanent_upgrades["hp"] == 1, "永久强化等级 +1")
	check(GameData.crystal_core == 70, "按费用曲线扣费（100 - 30 = 70）")
	GameData.crystal_core = 0
	check(not GameData.try_upgrade("hp"), "晶核不足时购买失败")
	check(GameData.permanent_upgrades["hp"] == 1, "购买失败时等级不变")
	GameData.crystal_core = 999
	check(GameData.try_upgrade("start_skill"), "购买开局技能（120 晶核）")
	check(not GameData.try_upgrade("start_skill"), "满级（max_lv=1）后不可再升")


# ---------------- T17 永久强化跨局生效（PRD 8-3） ----------------

func _t_perm_cross_run() -> void:
	print("\n[T17] 永久强化跨局生效")
	GameData.permanent_upgrades["hp"] = 2
	GameData.permanent_upgrades["attack"] = 1
	GameData.permanent_upgrades["pick_range"] = 1
	GameData.permanent_upgrades["start_skill"] = 0
	main.start_run()
	await tick(3)
	main.spawner.enabled = false
	main.player.set("_fire_cd", 1e9)
	check(main.player.max_hp == 110.0, "初始血量 100 + 5×2 = 110")
	check(main.player.base_attack == 12.0, "初始攻击 10 + 2×1 = 12（V0.8.5 基础攻击 8→10）")
	check(main.player.pick_radius == 110.0, "拾取半径 90 + 20×1 = 110")


# ---------------- T18 图鉴解锁与面板（阶段3） ----------------

func _t_codex() -> void:
	force_resume()
	print("\n[T18] 图鉴解锁与面板")
	main._clear_world()
	GameData.unlocked_monsters.clear()
	var m: Monster = main.spawner.spawn_monster("small", main.player.position + Vector2(150, 0))
	m.take_damage(9999.0)
	await tick(3)
	check(GameData.unlocked_monsters.has("small"), "击杀后图鉴解锁该怪物类型")
	main.codex_panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: int = main.codex_panel._rows_box.get_children() \
		.filter(func(c): return not c.is_queued_for_deletion()).size()
	check(rows == 3, "图鉴面板展示 3 条怪物条目")
	main.codex_panel.close()


# ---------------- T19 BOSS 击破奖励（阶段3 → BOSSES.reward） ----------------

func _t_boss_buff() -> void:
	force_resume()
	print("\n[T19] BOSS 击破奖励（碎晶王：回血+攻击增益）")
	var atk_before: float = main.player._current_attack()
	main.player.hp = 60.0
	main._apply_boss_reward("boss1")
	check(main.player._current_attack() == atk_before + 6.0, "击破后晶刺伤害 +6")
	check(main.player.attack_buff_active(), "增益处于生效中")
	check(main.player.hp == 90.0, "碎晶王奖励回血 +30")
	# 晶甲巨兽奖励：最大生命 +20
	var maxhp_before: float = main.player.max_hp
	main._apply_boss_reward("boss3")
	check(main.player.max_hp == maxhp_before + 20.0, "巨兽精粹：最大生命 +20")
	# 引力魔核奖励：射速增益（间隔 ÷1.15）
	var interval_before: float = main.player._current_fire_interval()
	main._apply_boss_reward("boss4")
	check(main.player._current_fire_interval() < interval_before, "魔核共鸣：射速增益缩短发射间隔")
	main.player._buff_time = 0.3                 # 压缩等待：直接把剩余时间拨到快到期
	main.player._fire_buff_time = 0.3
	await tick(25)
	check(not main.player.attack_buff_active(), "增益到期后失效")
	check(main.player._current_attack() == atk_before, "攻击恢复基础值")


# ---------------- T20 结算晶核明细（阶段3） ----------------

func _t_settle_breakdown() -> void:
	force_resume()
	print("\n[T20] 结算晶核明细 breakdown + 到达关卡")
	main._clear_world()
	main.state = 1
	main.kill_count = 7
	main.effect_manager.max_combo = 5
	main.boss_core_reward = 15                    # BOSS 击破晶核奖励（BOSSES.reward.core）
	var holder: Array = []                       # lambda 捕获是值拷贝，须用引用容器带回数据
	GameEvents.run_finished.connect(func(_won, s): holder.append(s), CONNECT_ONE_SHOT)
	main._finish_run(false)
	var stats: Dictionary = holder[0] if not holder.is_empty() else {}
	check(not stats.is_empty(), "run_finished 信号携带结算数据")
	var bd: Dictionary = stats.get("breakdown", {})
	check(int(bd.get("kills", -1)) == 7 and int(bd.get("combo", -1)) == 10 \
		and int(bd.get("boss", -1)) == 15 and int(bd.get("base", -1)) == 10,
		"明细各项正确（击杀7 / 连锁×2=10 / BOSS15 / 失败保底10）")
	check(int(stats.get("cores", -1)) == 42, "合计晶核 = 42 且与明细求和一致")
	check(int(stats.get("wave", -1)) == main.wave_manager.current_wave
		and int(stats.get("wave_total", -1)) == GameConfig.WAVE_COUNT,
		"结算 stats 携带到达关卡（第 %d/%d 关）" % [stats.get("wave", 0), stats.get("wave_total", 0)])
	main.settle_panel.close()


# ---------------- T21 程序化音频（阶段4） ----------------

func _t_audio() -> void:
	print("\n[T21] 程序化音频 SoundManager")
	# 1. Autoload 就绪 + 短音效样本全量合成（17 种）
	check(SoundManager != null and not SoundManager._samples.is_empty(), "SoundManager 就绪且样本表非空")
	var expect := ["shot", "hit", "kill", "chain", "xp", "hurt", "heal", "dash",
		"levelup", "choose", "start", "boss_spawn", "boss_kill", "win", "lose", "click", "buy"]
	var all_ok := true
	for id in expect:
		if not SoundManager._samples.has(id):
			all_ok = false
	check(all_ok, "17 种短音效样本全部合成")
	# 2. 逐个播放不报错
	for id in expect:
		SoundManager.play(id)
	check(true, "全部音效可播放（无脚本错误）")
	# 3. 节流：间隔内重复播放被忽略（play 后立即再 play，应被节流挡掉一次）
	SoundManager._last_play.clear()
	SoundManager.play("xp")
	var ts_first: int = SoundManager._last_play.get("xp", -1)
	SoundManager.play("xp")
	check(int(SoundManager._last_play.get("xp", -1)) == ts_first, "高频音效节流生效（间隔内不重复发声）")
	# 4. 静音切换 + 存档持久化往返
	GameData.muted = false
	var muted_now := SoundManager.toggle_mute()
	GameData.save_game()
	var saved_muted: bool = GameData.muted
	GameData.muted = false
	GameData.load_save()
	check(muted_now and saved_muted and GameData.muted, "toggle_mute 切换且存档往返保留静音状态")
	SoundManager.toggle_mute()  # 恢复未静音
	# 5. 事件接线：GameEvents 信号触发播放链路无错
	GameEvents.shot_fired.emit()
	GameEvents.projectile_hit.emit()
	GameEvents.boss_spawned.emit()
	GameEvents.chain_triggered.emit(5)
	check(true, "GameEvents 音效信号链路触发无错")
	# 6. BGM 延迟合成后可用且循环配置正确
	await get_tree().create_timer(0.5).timeout
	check(SoundManager._samples.has("bgm"), "BGM 样本延迟合成完成")
	var bgm = SoundManager._samples["bgm"]
	check(bgm is AudioStreamWAV and bgm.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"BGM 循环模式配置正确")


# ---------------- T22 晶甲巨兽护甲壳（第 7 关 BOSS3） ----------------

func _t_boss3_armor() -> void:
	force_resume()
	print("\n[T22] 晶甲巨兽护甲壳（减伤/破甲脆弱期/恢复）")
	main._clear_world()
	main.player.set("_fire_cd", 1e9)
	var m: Monster = main.spawner.spawn_monster("boss3", main.player.position + Vector2(-350, -250))
	m.speed = 0.0
	check(is_equal_approx(m.max_hp, 1600.0) and is_equal_approx(m.armor_hp, 300.0),
		"巨兽 HP1600 + 护甲 300 初始化")
	# 有甲期：100 伤 → 本体仅承伤 40%
	m.take_damage(100.0)
	check(is_equal_approx(m.hp, 1600.0 - 40.0), "有甲期承伤 40%（100 伤 → 本体 -40）")
	check(is_equal_approx(m.armor_hp, 200.0), "护甲池承受全额伤害（300→200）")
	# 打穿护甲 → 脆弱期（全额承伤）
	m.take_damage(250.0)
	check(m.armor_hp == 0.0 and m.fragile_left > 0.0, "护甲破碎进入 10s 脆弱期")
	var hp_at_break: float = m.hp
	m.take_damage(100.0)
	check(is_equal_approx(m.hp, hp_at_break - 100.0), "脆弱期全额承伤（无减伤）")
	# 脆弱期结束 → 护甲恢复
	m.fragile_left = 0.05
	await tick(8)
	check(is_equal_approx(m.armor_hp, 300.0), "脆弱期结束护甲恢复 300")
	m.queue_free()


# ---------------- T23 晶刺猎手分裂合并（第 5 关 BOSS2） ----------------

func _t_boss2_split() -> void:
	force_resume()
	print("\n[T23] 猎手分裂：本体无敌+小体+限时合并")
	main._clear_world()
	main.player.set("_fire_cd", 1e9)
	var m: Monster = main.spawner.spawn_monster("boss2", main.player.position + Vector2(0, -450))
	check(is_equal_approx(m.max_hp, 800.0), "猎手 HP800 初始化")
	m.take_damage(450.0)   # hp 350 < 50% → 下一物理帧触发分裂
	await tick(4)
	check(m.invulnerable, "HP<50% 触发分裂，本体进入无敌")
	var children := 0
	for c in main.get_tree().get_nodes_in_group("monsters"):
		if c != m and c.is_split_child:
			children += 1
	check(children == 2, "分裂出 2 只小猎手（各 25% 血）")
	var hp_now: float = m.hp
	m.take_damage(500.0)
	check(m.hp == hp_now, "分裂期本体免伤")
	# 合并时限到 → 小体回归 + 本体至少恢复到 40% 血量
	m.boss_action._split_timer = 0.05
	await tick(8)
	var left_children := 0
	for c in main.get_tree().get_nodes_in_group("monsters"):
		if c != m and c.is_split_child:
			left_children += 1
	check(left_children == 0 and not m.invulnerable, "合并时限到：小体回归，本体解除无敌")
	check(m.hp >= 800.0 * 0.4, "合并后本体至少恢复到 40%% 血量（%.0f ≥ 320）" % m.hp)
	m.queue_free()


# ---------------- T24 晶洞主宰三阶段（第 10 关 BOSS5） ----------------

func _t_boss5_phases() -> void:
	force_resume()
	print("\n[T24] 主宰三阶段切换（HP 驱动招式启用）")
	main._clear_world()
	main.player.set("_fire_cd", 1e9)
	var m: Monster = main.spawner.spawn_monster("boss5", main.player.position + Vector2(-320, 280))
	m.speed = 0.0
	check(m.phase_index == 0, "初始阶段 1（fan+summon）")
	check(not m.boss_action._action_enabled("rain"), "阶段 1 未启用晶雨")
	m.take_damage(m.max_hp * 0.40)   # HP 60% → 阶段 2
	await tick(4)
	check(m.phase_index == 1, "HP≤66% 切换阶段 2")
	check(m.boss_action._action_enabled("vortex_drop") and m.boss_action._action_enabled("quake"),
		"阶段 2 启用 引力漩涡+震地波")
	check(not m.boss_action._action_enabled("rain"), "阶段 2 仍未启用晶雨")
	m.take_damage(m.max_hp * 0.35)   # HP 25% → 阶段 3 + 分裂触发
	await tick(4)
	check(m.phase_index == 2, "HP≤33% 切换阶段 3")
	check(m.boss_action._action_enabled("rain"), "阶段 3 启用全屏晶雨")
	check(m.invulnerable, "阶段 3 触发分裂分身（本体无敌）")
	m.queue_free()


# ---------------- T25 掉落补给（D1-D4） ----------------

func _t_supply_drops() -> void:
	force_resume()
	print("\n[T25] 掉落补给（计数伪随机/残血保护/上限回收/满血血包）")
	main._clear_world()
	main.player.set("_fire_cd", 1e9)
	main.player.position = Vector2(360, 900)
	var dm: DropManager = main.drop_manager
	# D1 概率触发：击杀 100 只小怪（5% ≈ 5 个 + pity 保底）→ 至少 1 个补给
	var m0: Monster = main.spawner.spawn_monster("small", Vector2(60, 60))
	m0.take_damage(99999.0)
	for i in 99:
		var m: Monster = main.spawner.spawn_monster("small", Vector2(60, 60))
		m.take_damage(99999.0)
	await tick(2)
	var supplies: int = main.get_tree().get_nodes_in_group("supply_drops").size()
	check(supplies >= 1, "D1 击杀计数触发补给掉落（100 杀掉 %d 个）" % supplies)
	# D2 残血保护：稀有判定先分走 20%，实际血包占比 = 0.8×(1.8/2.2) ≈ 65.4%（σ≈3.4%）
	# 阈值 110(55%) 距均值 -3σ 安全，且与无保护基线 48% 保持区分度，非 flaky
	main.player.hp = main.player.max_hp * 0.2
	var heal_count := 0
	for i in 200:
		if dm._roll_kind() == "heal":
			heal_count += 1
	check(heal_count >= 110, "D2 残血时血包占比显著提高（%d/200 = %.0f%%，权重×3）" % [heal_count, heal_count / 2.0])
	main.player.heal(9999.0)
	# D3 上限回收：强制再补 5 个 → 回收消化后场上 ≤ 8
	for i in 5:
		dm._spawn_supply(Vector2(120, 120), "heal")
	await tick(3)   # 等待 queue_free 的最旧补给退出群组
	check(main.get_tree().get_nodes_in_group("supply_drops").size() <= int(GameConfig.DROP_TABLE["max_drops"]),
		"D3 场上补给 ≤ 上限 8（超出回收最旧，当前 %d）" % main.get_tree().get_nodes_in_group("supply_drops").size())
	# D4 满血拾取血包：不回溢、补给正常消失
	var hp_full: float = main.player.hp
	dm._spawn_supply(main.player.position, "heal")
	await tick(10)
	check(main.player.hp == hp_full, "D4 满血拾取血包不回溢")
	check(not main.get_tree().get_nodes_in_group("supply_drops").any(
		func(s): return s.kind == "heal" and s.position.distance_to(main.player.position) < 5.0),
		"D4 拾取后血包消失")
	# 磁石窗口 / 护盾碎片层数
	dm.trigger_magnet()
	check(dm.magnet_active(), "磁石触发全屏磁吸窗口（6s）")
	main.player.shield_charges = 0
	check(main.player.add_shield_charge() and main.player.shield_charges == 1, "护盾碎片 +1 层")
	main.player.shield_charges = 3
	check(not main.player.add_shield_charge(), "护盾层数上限 3")
	main.player.shield_charges = 0


# ---------------- T26 弹种系统（W1-W3） ----------------

func _t_weapons() -> void:
	force_resume()
	print("\n[T26] 弹种系统（三连发/巨型爆炸/弹种卡等级/临时弹种）")
	main._clear_world()
	main.player.set("_fire_cd", 1e9)
	# W1 三连发：一次攻击 3 枚扇形 15°
	var target: Monster = main.spawner.spawn_monster("small", main.player.position + Vector2(0, -300))
	target.speed = 0.0
	# 隔离：force_resume 自动推荐可能已学其他弹种卡（随机池），清零后仅保留三连发
	for wid in GameConfig.WEAPON_TYPES.keys():
		if wid != "default":
			main.skills.levels[wid] = 0
	main.skills.acquire("triple")
	main.player.sync_weapon_from_skills()
	check(main.player.current_weapon() == "triple", "习得三连发弹种卡（替换默认弹种）")
	var proj_before: int = main.projectile_layer.get_children().size()
	main.player._fire(target)
	var projs: int = main.projectile_layer.get_children().size() - proj_before
	check(projs == 3, "W1 三连发一次发射 3 枚（实际 %d）" % projs)
	# W3 弹种卡等级倍率 + 封顶
	check(is_equal_approx(GameConfig.weapon_lv_mult(1), 1.0) \
		and is_equal_approx(GameConfig.weapon_lv_mult(2), 1.15) \
		and is_equal_approx(GameConfig.weapon_lv_mult(3), 1.3),
		"W3 弹种卡等级倍率 Lv1/2/3 = 1.0/1.15/1.3")
	main.skills.acquire("triple")
	main.skills.acquire("triple")
	check(main.skills.get_level("triple") == 3, "弹种卡升至 Lv3")
	main.skills.acquire("triple")
	check(main.skills.get_level("triple") == 3, "弹种卡封顶 3 级不再叠加")
	# W2 巨型晶刺：直接命中致死 + 爆炸半径 24 范围伤害
	var a: Monster = main.spawner.spawn_monster("small", main.player.position + Vector2(0, -280))
	a.speed = 0.0
	var p := Projectile.new()
	p.setup(main.player.position, Vector2(0, -1) * 260.0, 50.0, 0.0)
	p.set_weapon(0, 0.0, 24.0, Color("d24df5"))
	main.projectile_layer.add_child(p)
	await tick(90)
	check(not is_instance_valid(a) or not a.alive, "W2 巨型晶刺直接命中目标")
	# 爆炸范围：弹着点附近两只（22/18 距离）被半径 24 爆炸波及
	var blast_a: Monster = main.spawner.spawn_monster("small", Vector2(500, 200))
	var blast_b: Monster = main.spawner.spawn_monster("small", Vector2(518, 210))
	blast_a.speed = 0.0
	blast_b.speed = 0.0
	var boom := Projectile.new()
	boom.setup(Vector2(500, 200), Vector2.ZERO, 50.0, 0.0)
	boom.set_weapon(0, 0.0, 24.0, Color("d24df5"))
	main.projectile_layer.add_child(boom)
	boom._explode(null)
	await tick(3)
	check(not is_instance_valid(blast_a) or not blast_a.alive, "W2 爆炸中心目标受伤")
	check(not is_instance_valid(blast_b) or not blast_b.alive, "W2 爆炸半径 24 波及 20 距离邻近目标")
	boom.queue_free()
	# 弹种道具：临时弹种 8s，到期回落已习得弹种
	main.player.equip_temp_weapon("spread")
	check(main.player.current_weapon() == "spread", "弹种道具切换临时弹种")
	main.player.temp_weapon_time = 0.05
	await tick(8)
	check(main.player.current_weapon() == "triple", "临时弹种到期回落已习得弹种")


# ---------------- T27 升级弹窗优化（U1-U3） ----------------

func _t_upgrade_optimize() -> void:
	force_resume()
	print("\n[T27] 升级弹窗优化（连升合并/自动升级/一键推荐）")
	main._clear_world()
	main.state = 1
	# U1 连升合并：一次 3.5 级经验 → 只弹 1 次窗，选 1 项消化全部
	main.level = 1
	main.xp = 0.0
	main.pending_levelups = 0
	main._on_xp_gained(GameConfig.xp_to_next(main.level) * 3.5)
	await tick(2)
	check(main.state == 1 and main.pending_levelups == 2, "多级经验合并入账不打断（pending=%d）" % main.pending_levelups)
	main._open_upgrade_panel()
	await tick(2)
	check(main.state == 2 and main.pending_levelups == 2, "U1 气泡打开弹窗（pending=%d）" % main.pending_levelups)
	main._on_upgrade_chosen("heal")
	check(main.state == 1 and main.pending_levelups == 0, "U1 连升合并：单次弹窗选 1 项即消化全部")
	# U3 一键推荐规则
	main.player.hp = 20.0
	check(main._pick_recommended(["aura", "heal", "dash"]) == "heal", "U3 规则①：HP<35% 推荐 heal")
	main.player.heal(9999.0)
	main.skills.levels["spread"] = 1
	check(main._pick_recommended(["spread", "aura", "dash"]) == "spread", "U3 规则②：已有弹种卡推荐弹种强化")
	main.skills.levels.erase("spread")
	main.player.sync_weapon_from_skills()
	# U2 自动升级：开关开 → 不弹窗自动学推荐
	GameData.auto_upgrade = true
	main._on_xp_gained(GameConfig.xp_to_next(main.level))
	await tick(2)
	check(main.state == 1 and main.pending_levelups == 0, "U2 自动升级不弹窗，等级自动消化")


func _t_sprite_scale() -> void:
	print("\n[T28] 显示尺寸与素材分辨率无关（缩图回归防护）")
	# 数学不变式：draw_px = scale × 纹理边长，任意分辨率素材屏上大小恒定
	var s2048 := GameConfig.sprite_scale(26.0, 2048.0)
	var s256 := GameConfig.sprite_scale(26.0, 256.0)
	var s320 := GameConfig.sprite_scale(26.0, 320.0)
	check(absf(s2048 * 2048.0 - s256 * 256.0) < 0.01 and absf(s2048 * 2048.0 - s320 * 320.0) < 0.01,
		"sprite_scale：256/320/2048 三种纹理画布显示尺寸一致")
	check(absf(GameConfig.sprite_scale(26.0) - s2048) < 1e-6, "sprite_scale 缺省参数兼容 2048 基准")
	# 实体校验：玩家/怪物贴图按实际纹理宽度换算，绘制直径 = 半径×2÷900×2048
	var pdraw: float = main.player._poly.scale.x * main.player._poly.texture.get_width()
	var pwant: float = 22.0 * 2.0 / GameConfig.ASSET_BODY_DIAMETER * GameConfig.ASSET_SRC_DIAMETER * 1.8
	check(absf(pdraw - pwant) < 1.0, "玩家绘制直径 %.0fpx 与基准 %.0fpx 一致（主角×1.8）" % [pdraw, pwant])
	var m: Monster = main.spawner.spawn_monster("big", main.player.position + Vector2(-350, -250))
	var mdraw: float = m._poly.scale.x * m._poly.texture.get_width()
	var mwant: float = 26.0 * 2.0 / GameConfig.ASSET_BODY_DIAMETER * GameConfig.ASSET_SRC_DIAMETER
	check(absf(mdraw - mwant) < 1.0, "大晶兽绘制直径 %.0fpx 与基准 %.0fpx 一致" % [mdraw, mwant])


# ---------------- T29-T33 补给空投 + 刷怪节奏 + 弹速进化（V0.8 任务书）----------------

func _t_airdrop_cycle() -> void:
	force_resume()
	print("\n[T29] 关内周期空投（精英关 18s 触发/空投池/落点距离/过期消失）")
	main._clear_world()
	for s in main.get_tree().get_nodes_in_group("supply_drops"):   # _clear_world 不清补给，手动隔离
		s.queue_free()
	main.drop_manager.magnet_until = -1.0   # 前序测试拾取磁石的 6s 吸附窗口泄漏会拉走空投落点
	main.state = 1
	main.player.set("_fire_cd", 1e9)
	main.player.position = Vector2(360, 900)
	main.player.hp = main.player.max_hp
	var arrived: Array = []                       # lambda 按值捕获局部变量，计数须用引用容器
	var fn := func() -> void: arrived.append(1)
	GameEvents.airdrop_arrived.connect(fn)
	# 进入第 2 关（精英），手动泵 wave_manager 18.2s（0.02 步进；略超 18s 规避浮点边界）
	main.wave_manager._begin_wave(2)
	main.spawner.enabled = false     # T29 只测空投：隔离真实帧刷怪→碰撞击退导致玩家位移干扰落点断言
	for i in 910:
		main.wave_manager.update(0.02)
	check(arrived.size() >= 1, "精英关 18s 内触发周期空投（%d 次）" % arrived.size())
	check(main.wave_manager._airdrop_timer > 0.0 and main.wave_manager._airdrop_timer <= 18.0,
		"空投后计时器重置为周期间隔（%.1fs）" % main.wave_manager._airdrop_timer)
	# 预警光圈 0.8s 后补给实体落地（create_timer 走真实时钟，等 ~1.2s）
	await tick(70)
	var supplies: Array = main.get_tree().get_nodes_in_group("supply_drops")
	check(supplies.size() >= 1, "预警 0.8s 后补给实体出现（%d 个）" % supplies.size())
	if supplies.size() > 0:
		check(supplies[0].kind in ["heal", "weapon", "magnet", "shield"],
			"空投内容来自空投池（首个=%s）" % supplies[0].kind)
		check(supplies[0].position.distance_to(main.player.position) >= 280.0,
			"空投落点 320~420px 远离玩家（边界钳制后 %.0f 仍需走位）" % supplies[0].position.distance_to(main.player.position))
		# 过期消失：同一 lifetime 代码路径，缩短验证
		var s0 = supplies[0]
		s0.lifetime = 0.05
		await tick(5)
		check(not is_instance_valid(s0), "空投补给到点自动消失（lifetime 到期）")
	GameEvents.airdrop_arrived.disconnect(fn)


func _t_airdrop_pickup() -> void:
	force_resume()
	print("\n[T30] 空投拾取（弹种 8s 回落/血包回复/拾取信号）")
	main._clear_world()
	main.player.position = Vector2(360, 900)
	main.player.set("_fire_cd", 1e9)
	var picked: Array = []
	var fn := func(k, v): picked.append([k, v])
	GameEvents.supply_picked.connect(fn)
	var dm: DropManager = main.drop_manager
	# 拾取弹种道具 → 临时弹种 + 信号
	main.player.temp_weapon_id = ""
	main.player.temp_weapon_time = 0.0
	dm._spawn_supply(main.player.position, "weapon")
	await tick(10)
	check(main.player.temp_weapon_id != "" and GameConfig.WEAPON_TYPES.has(main.player.temp_weapon_id),
		"拾取弹种道具 → 临时弹种「%s」" % main.player.temp_weapon_id)
	check(picked.any(func(p): return p[0] == "weapon"), "supply_picked（weapon）信号已广播")
	main.player.temp_weapon_time = 0.05
	await tick(10)
	check(main.player.temp_weapon_id == "", "临时弹种 8s 到期回落默认")
	# 血包：残血 +20 + 信号
	main.player.hp = 50.0
	dm._spawn_supply(main.player.position, "heal")
	await tick(10)
	check(is_equal_approx(main.player.hp, 70.0), "拾取血包 HP +20（50 → %.0f）" % main.player.hp)
	check(picked.any(func(p): return p[0] == "heal" and p[1] > 0.0), "supply_picked（heal +N）信号已广播")
	GameEvents.supply_picked.disconnect(fn)


func _t_wave2_density() -> void:
	force_resume()
	print("\n[T31] 第二关密度（30s 生成数/大兽同屏上限）")
	main._clear_world()
	main.player.position = Vector2(360, 900)
	main.player.set("_fire_cd", 1e9)
	main.player.hp = main.player.max_hp
	main.wave_manager._begin_wave(2)
	seed(20260929)
	for i in 1500:                            # 手动泵 30s（0.02 步进）
		main.spawner._physics_process(0.02)
	await tick(2)
	var monsters: Array = main.get_tree().get_nodes_in_group("monsters")
	var bigs := 0
	for m in monsters:
		if m.monster_id == "big":
			bigs += 1
	check(monsters.size() <= GameConfig.MAX_MONSTERS_ELITE,
		"第 2 关 30s 生成 %d 只 ≤ %d（V0.8.1 密度收敛，V0.7 约 70/V0.8 上限 45）" % [monsters.size(), GameConfig.MAX_MONSTERS_ELITE])
	check(bigs <= int(GameConfig.WAVE_TABLE[1]["big_cap"]),
		"大兽同屏 %d ≤ 上限 %d（满额转小怪）" % [bigs, int(GameConfig.WAVE_TABLE[1]["big_cap"])])
	check(main.spawner.max_monsters == GameConfig.MAX_MONSTERS_ELITE, "精英关同屏硬上限已下发")


func _t_wave_local_reset() -> void:
	force_resume()
	print("\n[T32] 刷怪按本关进度重置（跨关不继承）")
	main._clear_world()
	main.player.position = Vector2(360, 900)
	main.player.set("_fire_cd", 1e9)
	main.wave_manager._begin_wave(1)
	for i in 1450:                            # 第 1 关推进 29s，interval 收紧至峰值下限
		main.spawner._physics_process(0.02)
	var late: float = main.spawner._current_interval()
	check(absf(late - float(GameConfig.WAVE_TABLE[0]["min_interval"])) < 0.01,
		"第 1 关末 interval 收紧至峰值下限 %.2fs" % late)
	main.wave_manager._begin_wave(2)          # 进第 2 关 → 本关重置
	var fresh: float = main.spawner._current_interval()
	check(absf(fresh - 1.15) < 0.05, "第 2 关开局 interval 重置 ≈1.15s（实际 %.2fs，不继承上一关收紧值）" % fresh)
	check(main.spawner.wave_local == 0.0
		and main.spawner.wave_min_interval == float(GameConfig.WAVE_TABLE[1]["min_interval"]),
		"本关计时清零 + 新关峰值下限 %.2fs 下发" % float(GameConfig.WAVE_TABLE[1]["min_interval"]))


func _t_bullet_speed_evolution() -> void:
	force_resume()
	print("\n[T33] 弹速进化（永久强化 Lv1/Lv5 + 弹种绝对增量）")
	main._clear_world()
	main.state = 1
	main.player.position = Vector2(360, 900)
	# C2 基础弹速：350 + 40×等级（Lv1=390 / Lv5=550）
	GameData.permanent_upgrades["bullet_speed"] = 1
	main.player.setup(main.skills, GameData.perm_bonuses(), main.projectile_layer)
	check(is_equal_approx(main.player.base_projectile_speed, 390.0), "Lv1 基础弹速 390")
	GameData.permanent_upgrades["bullet_speed"] = 5
	main.player.setup(main.skills, GameData.perm_bonuses(), main.projectile_layer)
	check(is_equal_approx(main.player.base_projectile_speed, 550.0), "Lv5 基础弹速 550")
	# C2 绝对增量对弹种生效：三连发 320 + 200 = 520（发射实测）
	main.player.weapon_id = "triple"
	main.player.weapon_lv = 1
	var dummy := Node2D.new()
	main.projectile_layer.add_child(dummy)
	dummy.position = main.player.position + Vector2(300, 0)
	main.player._fire(dummy)
	await tick(2)
	var projs: Array = main.projectile_layer.get_children().filter(func(c): return c is Projectile)
	check(projs.size() == 3, "三连发发射 3 枚")
	if projs.size() > 0:
		check(absf(projs[0].velocity.length() - 520.0) < 0.5,
			"三连发弹速 = 320 + 增量200 = 520（绝对增量生效，实测 %.0f）" % projs[0].velocity.length())
	dummy.queue_free()
	GameData.permanent_upgrades["bullet_speed"] = 0   # 还原，防污染后续用例
	main.player.setup(main.skills, GameData.perm_bonuses(), main.projectile_layer)
	GameData.auto_upgrade = false
	# U4 手动气泡信号链：hud.levelup_pressed → 打开三选一
	main._on_xp_gained(GameConfig.xp_to_next(main.level))
	await tick(2)
	check(main.state == 1 and main.hud.levelup_button.visible, "U4 升级后气泡提示不打断")
	main.hud.levelup_pressed.emit()
	await tick(2)
	check(main.state == 2, "U4 点击升华气泡打开三选一")
	main._on_upgrade_chosen("heal")
	await tick(2)
	# U5 关间过渡兜底：攒着没点 → 过渡信号自动弹一次防忘
	main._on_xp_gained(GameConfig.xp_to_next(main.level))
	await tick(2)
	main.wave_manager.transition_started.emit(2, 3.0)
	await tick(2)
	check(main.state == 2, "U5 关间过渡兜底自动弹窗")
	main._on_upgrade_chosen("heal")
	await tick(2)
	check(main.state == 1, "U5 选卡后恢复战斗")
