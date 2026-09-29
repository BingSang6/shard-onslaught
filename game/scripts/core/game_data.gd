extends Node
## 存档管理（Autoload 单例）
## 使用 user://save.json 持久化，Web 导出后自动映射到浏览器本地存储（LocalStorage/IndexedDB），
## 满足 PRD「存档保存在浏览器本地存储」的非功能需求。
## 存档结构对齐 SDS 3.5：晶核货币 + 4 项永久强化 + 图鉴解锁。

const SAVE_PATH := "user://save.json"

var crystal_core: int = 0                    # 晶核（永久货币）
var permanent_upgrades := {"hp": 0, "attack": 0, "pick_range": 0, "start_skill": 0, "bullet_speed": 0}
var unlocked_monsters: Array = []            # 图鉴：已遭遇的怪物类型 id
var muted := false                           # 静音开关（阶段4：SoundManager 读取）
var max_wave := 0                            # 波次制：历史最高到达关卡（1~10）
var cleared_all := false                     # 通关第 10 关标识
var auto_upgrade := false                    # 自动升级开关（升级不弹窗，自动学推荐）


func _ready() -> void:
	load_save()


## 读取存档（缺省时生成默认存档）
func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save_game()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("存档读取失败：%s" % SAVE_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档解析失败，重置为默认存档")
		return
	crystal_core = int(parsed.get("crystal_core", 0))
	muted = bool(parsed.get("muted", false))
	max_wave = int(parsed.get("max_wave", 0))
	cleared_all = bool(parsed.get("cleared_all", false))
	auto_upgrade = bool(parsed.get("auto_upgrade", false))
	var pu = parsed.get("permanent_upgrades", {})
	for key in permanent_upgrades.keys():
		permanent_upgrades[key] = int(pu.get(key, 0))
	unlocked_monsters = []
	for item in parsed.get("unlock_monster", []):
		unlocked_monsters.append(str(item))


## 保存存档（每局结算时调用）
func save_game() -> void:
	var data := {
		"crystal_core": crystal_core,
		"permanent_upgrades": permanent_upgrades.duplicate(),
		"unlock_monster": unlocked_monsters.duplicate(),
		"muted": muted,
		"max_wave": max_wave,
		"cleared_all": cleared_all,
		"auto_upgrade": auto_upgrade,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：%s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func add_core(amount: int) -> void:
	crystal_core += maxi(0, amount)
	save_game()


## 图鉴解锁（首次击杀某类型怪物时调用）
func unlock_monster(monster_id: String) -> void:
	if not unlocked_monsters.has(monster_id):
		unlocked_monsters.append(monster_id)
		save_game()


## 波次制进度记录：结算时调用（到达关卡取高；通关第 10 关点亮标识）
func record_wave(wave: int, won: bool) -> void:
	if wave > max_wave:
		max_wave = wave
	if won:
		cleared_all = true
	save_game()


## 局外永久强化 → 局内加成（PRD 2.4：血量+5 / 攻击+2 / 拾取范围 / 开局随机技能）
## 数值单一来源在 GameConfig.PERM_UPGRADES（bonus_per_lv），这里只做等级 × 单价的换算
func perm_bonuses() -> Dictionary:
	return {
		"bonus_hp": float(GameConfig.PERM_UPGRADES["hp"]["bonus_per_lv"]) * float(permanent_upgrades["hp"]),
		"bonus_attack": float(GameConfig.PERM_UPGRADES["attack"]["bonus_per_lv"]) * float(permanent_upgrades["attack"]),
		"bonus_pick_radius": float(GameConfig.PERM_UPGRADES["pick_range"]["bonus_per_lv"]) * float(permanent_upgrades["pick_range"]),
		"bonus_bullet_speed": float(GameConfig.PERM_UPGRADES["bullet_speed"]["bonus_per_lv"]) * float(permanent_upgrades["bullet_speed"]),   # V0.8 C：弹速进化总增量
		"start_skill": permanent_upgrades["start_skill"] > 0,
	}


# ---------------- 永久强化购买（阶段3：消耗晶核升级）----------------

## 当前等级（缺省键返回 0）
func get_upgrade_lv(key: String) -> int:
	return int(permanent_upgrades.get(key, 0))


## 是否可升级：未满级 且 晶核足够
func can_upgrade(key: String) -> bool:
	var cfg: Dictionary = GameConfig.PERM_UPGRADES.get(key, {})
	if cfg.is_empty():
		return false
	var lv := get_upgrade_lv(key)
	if lv >= int(cfg["max_lv"]):
		return false
	return crystal_core >= GameConfig.perm_upgrade_cost(key, lv)


## 尝试升级：扣晶核 → 等级 +1 → 立即存档。成功返回 true。
func try_upgrade(key: String) -> bool:
	if not can_upgrade(key):
		return false
	crystal_core -= GameConfig.perm_upgrade_cost(key, get_upgrade_lv(key))
	permanent_upgrades[key] = get_upgrade_lv(key) + 1
	save_game()
	return true
