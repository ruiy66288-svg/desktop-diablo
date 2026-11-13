class_name SfxMixer extends RefCounted

## 性能友好型音效调度器 + 6 声道真实混音池 (依据《02_系统架构与数值_v6.md》§3.3 & §6.3 规范)
## 同帧同类音效合并，随机音高 ±5%，单类并发上限 4，并与 VfxBudget 单帧总上限 6 协同
## 100% 保留 request_play_sound(sound_id, budget) 签名与返回字典；挂载宿主节点后真实发声

const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const SfxBankScript = preload("res://presentation/audio/SfxBank.gd")

const MAX_CONCURRENT_PER_TYPE: int = 4
const PITCH_MIN: float = 0.95
const PITCH_MAX: float = 1.05
const CHANNEL_COUNT: int = 6
const DEFAULT_VOLUME_DB: float = -7.0

var _played_counts_this_frame: Dictionary = {}
var _merged_counts_this_frame: Dictionary = {}

var _host: Node = null
var _players: Array[AudioStreamPlayer] = []
var _next_channel: int = 0
var _muted: bool = false
var _volume_db: float = DEFAULT_VOLUME_DB
var _started_total: int = 0
var _last_started_ids: Array[String] = []
var _pitch_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func begin_frame() -> void:
	_played_counts_this_frame.clear()
	_merged_counts_this_frame.clear()

## 挂载 6 个 AudioStreamPlayer 节点池到宿主节点 (幂等)
func attach_host(host: Node) -> void:
	if host == null or _host == host:
		return
	_host = host
	_players.clear()
	for i: int in range(CHANNEL_COUNT):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "SfxChannel_%d" % i
		p.volume_db = _volume_db
		p.max_polyphony = 1
		host.add_child(p)
		_players.push_back(p)

func get_channel_count() -> int:
	return _players.size()

func get_started_total() -> int:
	return _started_total

func get_last_started_ids() -> Array[String]:
	return _last_started_ids.duplicate()

func is_muted() -> bool:
	return _muted

func set_muted(muted: bool) -> void:
	_muted = muted
	if muted:
		for p: AudioStreamPlayer in _players:
			p.stop()

func toggle_muted() -> bool:
	set_muted(not _muted)
	return _muted

func set_volume_db(db: float) -> void:
	_volume_db = clampf(db, -40.0, 6.0)
	for p: AudioStreamPlayer in _players:
		p.volume_db = _volume_db

func get_volume_db() -> float:
	return _volume_db

## 请求播放音效 (带并发限制、VfxBudget 协同与随机音高计算)
## 返回 Dictionary: {"play": bool, "pitch_scale": float, "merged": bool}
func request_play_sound(sound_id: String, budget: VfxBudgetScript = null) -> Dictionary:
	var current_count: int = int(_played_counts_this_frame.get(sound_id, 0))
	if current_count >= MAX_CONCURRENT_PER_TYPE:
		_merged_counts_this_frame[sound_id] = int(_merged_counts_this_frame.get(sound_id, 0)) + 1
		return {"play": false, "pitch_scale": 1.0, "merged": true}

	if budget != null and not budget.request_sfx():
		_merged_counts_this_frame[sound_id] = int(_merged_counts_this_frame.get(sound_id, 0)) + 1
		return {"play": false, "pitch_scale": 1.0, "merged": true}

	_played_counts_this_frame[sound_id] = current_count + 1
	var pitch: float = _pitch_rng.randf_range(PITCH_MIN, PITCH_MAX)
	_start_on_channel(sound_id, pitch)
	return {"play": true, "pitch_scale": pitch, "merged": false}

func get_merged_count(sound_id: String) -> int:
	return int(_merged_counts_this_frame.get(sound_id, 0))

func _start_on_channel(sound_id: String, pitch: float) -> bool:
	if _muted or _players.is_empty():
		return false
	var stream: AudioStreamWAV = SfxBankScript.get_stream(sound_id)
	if stream == null:
		return false
	var chosen: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _players[_next_channel % _players.size()]
		_next_channel += 1
	if not chosen.is_inside_tree():
		return false
	chosen.stream = stream
	chosen.pitch_scale = pitch
	chosen.volume_db = _volume_db
	chosen.play()
	_started_total += 1
	_last_started_ids.push_back(SfxBankScript.resolve_id(sound_id))
	if _last_started_ids.size() > 16:
		_last_started_ids.remove_at(0)
	return true
