extends Node
## 临时截图脚本：加载主场景，依次进入各状态并截图保存。
## 运行方式：Godot_v4.7.2-stable_win64_console.exe --path game res://screenshot_boot.tscn
## V0.7 序列覆盖验收点：主菜单最高关卡 / 商店 / 图鉴 / 战斗 /
## 升级弹窗推荐高亮 / 关3碎晶王战 / 关4精英波+四类补给 / 关10主宰阶段2与阶段3 / 结算"到达第N关"

var main: Node
var out_dir := "D:/hsp/work/dev/aicode/game/gcj/_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = preload("res://scripts/core/main.gd").new()
	add_child(main)
	_run_sequence()


func _run_sequence() -> void:
	# 1. 主菜单（预置存档：最高关卡 6 + 晶核，展示"最高关卡"入口）
	GameData.max_wave = 6
	GameData.cleared_all = false
	GameData.crystal_core = 60
	await get_tree().create_timer(1.2, true).timeout
	await _shot("01_menu")

	# 2. 永久强化面板（预置晶核与部分等级，展示付费/满级/不足状态）
	GameData.crystal_core = 260
	GameData.permanent_upgrades["hp"] = 2
	GameData.permanent_upgrades["start_skill"] = 1
	main.upgrade_shop.open()
	await get_tree().create_timer(0.5, true).timeout
	await _shot("02_shop")
	main.upgrade_shop.close()

	# 3. 晶体图鉴（小怪/大兽已解锁 + BOSS 剪影）
	GameData.unlocked_monsters = ["small", "big"]
	main.codex_panel.open()
	await get_tree().create_timer(0.5, true).timeout
	await _shot("03_codex")
	main.codex_panel.close()
	main.start_screen.refresh()

	# 4. 开始游戏：第 1 关普通波战斗中（自动刷怪 + 晶粒）
	main.start_run()
	await get_tree().create_timer(4.0, true).timeout
	await _shot("04_playing")

	# 5. 升级弹窗：连升 2 级合并 + 推荐项紫边高亮（任务书 §5.2）
	main.skills.acquire("shatter_blast")
	main.skills.acquire("triple")          # 已有弹种卡 → 推荐规则②强化弹种
	main.pending_levelups = 2
	main._open_upgrade_panel()
	await get_tree().create_timer(0.6, true).timeout
	await _shot("05_upgrade_recommended")
	var rec: String = main.upgrade_panel._recommended
	main._on_upgrade_chosen(rec if rec != "" else main.skills.get_choices(3)[0])

	# 6. 关 3：碎晶王 BOSS 战（HUD BOSS 血条 + 扇形晶刺弹幕 + 出场贴图）
	main.wave_manager._begin_wave(3)
	await get_tree().create_timer(5.6, true).timeout   # 出场 1.2s + 首轮扇形/冲击环
	await _shot("06_wave3_boss1")

	# 7. 关 4：精英波（大晶兽头顶血条）+ 四类补给空投同屏
	main.wave_manager._begin_wave(4)
	await get_tree().create_timer(2.2, true).timeout   # 等首批精英怪出场
	for kind in ["heal", "magnet", "shield", "weapon"]:
		var ang := TAU * ["heal", "magnet", "shield", "weapon"].find(kind) / 4.0
		var pos: Vector2 = main.player.position + Vector2.from_angle(ang) * 170.0
		main.drop_manager._spawn_supply(pos.clamp(Vector2(50, 50), GameConfig.ARENA_SIZE - Vector2(50, 50)), kind)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		if m.monster_id == "big":
			m.take_damage(30.0)               # 打掉一截血 → 头顶精英血条显现
	await get_tree().create_timer(0.6, true).timeout
	await _shot("07_wave4_elite_supply")

	# 8. 关 10：晶洞主宰阶段 2（≤66% 血：漩涡 + 震地波弹幕）
	main.wave_manager._begin_wave(10)
	await get_tree().create_timer(1.0, true).timeout   # 出场动画
	var boss = main.wave_manager.get_boss()
	boss.take_damage(boss.max_hp * 0.40)               # → 60% 血进入阶段 2
	await get_tree().create_timer(0.3, true).timeout   # 等阶段检测（物理帧）
	_fast_cooldowns(boss)                              # 拨小冷却加速首轮招式
	await get_tree().create_timer(1.6, true).timeout   # 漩涡场 + 震地波展开
	await _shot("08_wave10_boss5_phase2")

	# 9. 关 10：阶段 3（≤33% 血：晶雨 + 分裂，本体半透明无敌 + 两只分裂体）
	boss.take_damage(boss.max_hp * 0.35)               # → 25% 血进入阶段 3
	await get_tree().create_timer(0.3, true).timeout
	_fast_cooldowns(boss)
	await get_tree().create_timer(1.4, true).timeout   # 晶雨落下 + 分裂体在场
	await _shot("09_wave10_boss5_phase3")

	# 10. 结算：失败于第 10 关 → "到达 第 10 / 10 关" + 战斗时长
	main._finish_run(false)
	await get_tree().create_timer(1.0, true).timeout
	await _shot("10_settle_wave")

	get_tree().quit()


## 拨小 BOSS 全部招式冷却（截图加速用，不影响正式逻辑）
func _fast_cooldowns(boss) -> void:
	if boss == null or not is_instance_valid(boss) or boss.boss_action == null:
		return
	for k in boss.boss_action._cds.keys():
		boss.boss_action._cds[k] = 0.25


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + "/" + name + ".png"
	img.save_png(path)
	print("已截图: " + path)
