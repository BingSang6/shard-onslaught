# 碎晶突围（Crystal Breakout）

抖音/微信 Web 休闲割草小游戏 · Godot 4 + GDScript 最小可玩原型。

**当前进度：阶段1（基础框架）+ 阶段2（连锁爆炸与 8 技能）已完成。**
阶段3（局外养成经济/完整主菜单/图鉴）与阶段4（音频/数值精调）按 PRD 后续迭代。

## 运行

1. 安装 [Godot 4.7+](https://godotengine.org/download)（标准版即可，无需 .NET 版）
2. 用 Godot 打开本目录的 `project.godot`
3. F5 运行

### 操作
- 移动：拖动屏幕（触屏）/ 按住鼠标左键拖动 / WASD·方向键
- 瞬闪：右下角按钮 / 空格（习得技能后可用）
- 攻击：全自动（锁定最近的怪物发射晶刺）

### 一局规则
- 180 秒倒计时，活到最后即通关；血量归零失败
- 击杀掉晶粒 → 拾取涨经验 → 升级 3 选 1 技能（同技能重复获取可升级，上限 Lv5）
- 招牌combo：**引力漩涡** 聚怪 + **碎裂引爆** 连锁爆炸 = 全屏清场
- 无论胜负都结算晶核并写入本地存档（`user://save.json`，Web 端自动映射浏览器存储）

## 工程结构

```
game/
├── project.godot              # 竖屏 720×1280 / gl_compatibility（WebGL）
├── scenes/main.tscn           # 唯一入口场景（其余节点全部代码构建）
├── shaders/                   # 晶体自发光 / 引力漩涡 Shader
├── scripts/
│   ├── core/    main.gd(状态机/编排) game_config.gd(数值) game_data.gd(存档) game_events.gd(事件总线)
│   ├── player/  player.gd
│   ├── combat/  monster.gd monster_spawner.gd projectile.gd
│   ├── drops/   crystal_drop.gd drop_manager.gd
│   ├── effects/ effect_manager.gd（连锁爆炸队列 / 粒子 / 震动 / 连击）
│   ├── skills/  skill_manager.gd + aura/shield/vortex 三个主动技能节点
│   └── ui/      hud / upgrade_panel / start_screen / settle_panel / ui_style
└── tests/smoke_test.gd        # headless 冒烟测试
```

## 自动化验证（headless）

```bash
# 语法/工程加载检查
godot --headless --path . --quit

# 冒烟测试（状态机/刷怪/升级/连锁爆炸/漩涡/盾闪弹域/BOSS/结算/存档）
godot --headless --path . res://tests/smoke_test.tscn
# 退出码 0 = 全部通过
```

## 关键设计约束（来自 PRD/SDS）

- 原型阶段**零外部图片**：全部 Polygon2D + Shader + GPUParticles2D，色值对齐视觉规范
  （主色 `#0ac8dd` 青 / 辅 `#9922dd` 紫 / 背景 `#080818`）
- 连锁爆炸：队列式实现（非递归），`MAX_CHAIN=8` + 每帧爆炸预算 16，双保险防死循环
- 同屏怪物上限 60、晶粒上限 110（超限自动回收最旧）——WebGL 性能保护
- 中文 UI 依赖系统字体回退（Windows/Android/Web 主流设备均可用）

## 后续（阶段3/4，见根目录 readme.md）

- 完整主菜单：永久强化面板（4 项消耗晶核升级）、图鉴
- 结算经济细化、音效/BGM（程序化生成）、数值曲线精调
- WebGL 导出与微信/抖音小游戏适配（需专用导出模板）
- 用 `images/` 参考图批量生成 PNG 精灵替换几何原型
