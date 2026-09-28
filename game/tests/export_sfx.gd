extends Node
## 音频样本导出工具（开发用）：把程序合成样本落盘为 wav，供离线频谱分析/试听。
## 用法：godot --path game res://tests/export_sfx.tscn → 输出 gcj/_shots/sfx_<id>.wav

func _ready() -> void:
	await get_tree().process_frame  # 等 Autoload SoundManager._ready 完成
	var ids := ["hit", "kill", "shot", "xp"]
	for id in ids:
		var wav: AudioStreamWAV = SoundManager._samples[id]
		var data: PackedByteArray = wav.data
		var path := "D:/hsp/work/dev/aicode/game/gcj/_shots/sfx_%s.wav" % id
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("导出失败: " + path)
			continue
		# WAV 头（PCM16 mono）
		var byte_rate := wav.mix_rate * 2
		f.store_32(0x46464952)          # "RIFF"
		f.store_32(36 + data.size())    # riff size
		f.store_32(0x45564157)          # "WAVE"
		f.store_32(0x20746D66)          # "fmt "
		f.store_32(16)                  # fmt size
		f.store_16(1)                   # PCM
		f.store_16(1)                   # mono
		f.store_32(wav.mix_rate)
		f.store_32(byte_rate)
		f.store_16(2)                   # block align
		f.store_16(16)                  # bits
		f.store_32(0x61746164)          # "data"
		f.store_32(data.size())
		f.store_buffer(data)
		f.close()
		print("已导出: ", path)
	get_tree().quit()
