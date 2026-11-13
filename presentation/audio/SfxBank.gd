class_name SfxBank extends RefCounted

## 程序化确定性 16-bit PCM 音效合成库 (木刻暗黑质感, 零外部素材, 零版权风险)
## 每个音效由若干「层」叠加: 正弦/方波/锯齿/低通噪声 + 线性变频 + 指数衰减包络
## 噪声源使用固定种子 LCG, 同一音效任何时刻渲染结果逐字节一致

const SAMPLE_RATE: int = 22050
const MAX_DURATION_SEC: float = 1.8

const SOUND_IDS: Array[String] = [
	"hit_thud",
	"crit_slash",
	"coin_pickup",
	"smelt_ember",
	"drop_blue",
	"drop_purple",
	"drop_unique",
	"drop_primal",
	"shield_shatter",
	"toll_unlock",
	"prestige_bell",
	"meteor_impact",
	"hammer_slam"
]

const ALIASES: Dictionary = {
	"hit": "hit_thud",
	"crit": "crit_slash",
	"drop_normal": "coin_pickup",
	"drop_white": "coin_pickup",
	"drop_rare": "drop_unique",
	"smelt": "smelt_ember",
	"meteor": "meteor_impact",
	"hammer": "hammer_slam",
	"gold_storm": "coin_pickup",
	"fountain_burst": "drop_primal"
}

const WAVE_SINE: int = 0
const WAVE_SQUARE: int = 1
const WAVE_SAW: int = 2
const WAVE_NOISE: int = 3

static var _stream_cache: Dictionary = {}
static var _sample_cache: Dictionary = {}

static func resolve_id(sound_id: String) -> String:
	if SOUND_IDS.has(sound_id):
		return sound_id
	return str(ALIASES.get(sound_id, ""))

static func has_sound(sound_id: String) -> bool:
	return not resolve_id(sound_id).is_empty()

static func get_all_sound_ids() -> Array[String]:
	return SOUND_IDS.duplicate()

static func clear_cache() -> void:
	_stream_cache.clear()
	_sample_cache.clear()

## 获取 AudioStreamWAV (16-bit 单声道 PCM); 未知 ID 返回 null
static func get_stream(sound_id: String) -> AudioStreamWAV:
	var rid: String = resolve_id(sound_id)
	if rid.is_empty():
		return null
	if _stream_cache.has(rid):
		return _stream_cache[rid] as AudioStreamWAV
	var samples: PackedFloat32Array = render_samples(rid)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var v: int = clampi(int(round(samples[i] * 32767.0)), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	_stream_cache[rid] = stream
	return stream

## 渲染原始浮点采样 (归一化至峰值 0.9)
static func render_samples(sound_id: String) -> PackedFloat32Array:
	var rid: String = resolve_id(sound_id)
	if rid.is_empty():
		return PackedFloat32Array()
	if _sample_cache.has(rid):
		return _sample_cache[rid] as PackedFloat32Array
	var layers: Array[Dictionary] = _layers_for(rid)
	var out: PackedFloat32Array = _synth(layers)
	_sample_cache[rid] = out
	return out

static func get_duration_sec(sound_id: String) -> float:
	return float(render_samples(sound_id).size()) / float(SAMPLE_RATE)

static func _layer(
	t0: float,
	dur: float,
	f0: float,
	f1: float,
	wave: int,
	vol: float,
	decay: float,
	lp: float = 1.0,
	attack: float = 0.002
) -> Dictionary:
	return {
		"t0": t0, "dur": dur, "f0": f0, "f1": f1, "wave": wave,
		"vol": vol, "decay": decay, "lp": lp, "attack": attack
	}

static func _layers_for(rid: String) -> Array[Dictionary]:
	var L: Array[Dictionary] = []
	match rid:
		"hit_thud":
			L.push_back(_layer(0.0, 0.14, 150.0, 48.0, WAVE_SINE, 0.85, 26.0))
			L.push_back(_layer(0.0, 0.06, 0.0, 0.0, WAVE_NOISE, 0.35, 60.0, 0.16))
		"crit_slash":
			L.push_back(_layer(0.0, 0.20, 0.0, 0.0, WAVE_NOISE, 0.50, 20.0, 0.92))
			L.push_back(_layer(0.0, 0.16, 1900.0, 820.0, WAVE_SAW, 0.20, 18.0))
			L.push_back(_layer(0.02, 0.32, 2410.0, 2380.0, WAVE_SINE, 0.16, 11.0))
			L.push_back(_layer(0.02, 0.24, 1330.0, 1310.0, WAVE_SQUARE, 0.06, 14.0))
		"coin_pickup":
			L.push_back(_layer(0.0, 0.08, 1568.0, 1568.0, WAVE_SINE, 0.40, 28.0))
			L.push_back(_layer(0.05, 0.22, 2093.0, 2093.0, WAVE_SINE, 0.40, 13.0))
			L.push_back(_layer(0.05, 0.22, 4186.0, 4186.0, WAVE_SINE, 0.08, 16.0))
		"smelt_ember":
			L.push_back(_layer(0.0, 0.34, 0.0, 0.0, WAVE_NOISE, 0.32, 7.0, 0.55, 0.02))
			L.push_back(_layer(0.0, 0.34, 92.0, 70.0, WAVE_SINE, 0.22, 6.0, 1.0, 0.02))
			L.push_back(_layer(0.08, 0.10, 0.0, 0.0, WAVE_NOISE, 0.30, 30.0, 0.95))
		"drop_blue":
			L.push_back(_layer(0.0, 0.32, 660.0, 660.0, WAVE_SINE, 0.36, 10.0, 1.0, 0.004))
			L.push_back(_layer(0.06, 0.30, 990.0, 990.0, WAVE_SINE, 0.24, 11.0, 1.0, 0.004))
		"drop_purple":
			L.push_back(_layer(0.0, 0.50, 523.3, 523.3, WAVE_SINE, 0.30, 6.5, 1.0, 0.004))
			L.push_back(_layer(0.07, 0.46, 659.3, 659.3, WAVE_SINE, 0.26, 6.5, 1.0, 0.004))
			L.push_back(_layer(0.14, 0.42, 784.0, 784.0, WAVE_SINE, 0.24, 6.5, 1.0, 0.004))
		"drop_unique":
			L.push_back(_layer(0.0, 1.00, 196.0, 196.0, WAVE_SINE, 0.50, 3.6, 1.0, 0.006))
			L.push_back(_layer(0.0, 1.00, 293.7, 293.7, WAVE_SINE, 0.34, 3.8, 1.0, 0.006))
			L.push_back(_layer(0.0, 0.90, 392.0, 392.0, WAVE_SINE, 0.28, 4.2, 1.0, 0.006))
			L.push_back(_layer(0.0, 0.60, 541.0, 541.0, WAVE_SINE, 0.14, 6.0, 1.0, 0.006))
			L.push_back(_layer(0.0, 0.05, 0.0, 0.0, WAVE_NOISE, 0.18, 70.0, 0.4))
		"drop_primal":
			L.push_back(_layer(0.0, 1.10, 58.0, 36.0, WAVE_SINE, 0.85, 2.6, 1.0, 0.01))
			L.push_back(_layer(0.0, 0.90, 116.0, 108.0, WAVE_SAW, 0.18, 3.6, 1.0, 0.02))
			L.push_back(_layer(0.0, 0.80, 0.0, 0.0, WAVE_NOISE, 0.22, 4.0, 0.06, 0.02))
			L.push_back(_layer(0.25, 0.80, 174.6, 174.6, WAVE_SINE, 0.22, 3.4, 1.0, 0.02))
		"shield_shatter":
			L.push_back(_layer(0.0, 0.36, 0.0, 0.0, WAVE_NOISE, 0.40, 13.0, 0.96))
			L.push_back(_layer(0.0, 0.20, 3200.0, 3180.0, WAVE_SINE, 0.18, 20.0))
			L.push_back(_layer(0.02, 0.24, 4100.0, 4060.0, WAVE_SINE, 0.14, 18.0))
			L.push_back(_layer(0.05, 0.28, 5200.0, 5100.0, WAVE_SINE, 0.10, 16.0))
		"toll_unlock":
			L.push_back(_layer(0.0, 0.07, 110.0, 90.0, WAVE_SQUARE, 0.40, 40.0))
			L.push_back(_layer(0.0, 0.05, 0.0, 0.0, WAVE_NOISE, 0.30, 70.0, 0.7))
			L.push_back(_layer(0.10, 0.34, 220.0, 330.0, WAVE_SINE, 0.34, 7.0, 1.0, 0.01))
			L.push_back(_layer(0.26, 0.40, 70.0, 52.0, WAVE_SINE, 0.60, 7.0, 1.0, 0.004))
		"prestige_bell":
			L.push_back(_layer(0.0, 1.70, 261.6, 261.6, WAVE_SINE, 0.46, 2.2, 1.0, 0.004))
			L.push_back(_layer(0.0, 1.50, 392.0, 392.0, WAVE_SINE, 0.28, 2.4, 1.0, 0.004))
			L.push_back(_layer(0.0, 1.20, 523.3, 523.3, WAVE_SINE, 0.20, 3.0, 1.0, 0.004))
			L.push_back(_layer(0.0, 0.90, 785.0, 785.0, WAVE_SINE, 0.12, 4.2, 1.0, 0.004))
		"meteor_impact":
			L.push_back(_layer(0.0, 0.90, 92.0, 30.0, WAVE_SINE, 0.90, 3.8, 1.0, 0.012))
			L.push_back(_layer(0.0, 0.90, 0.0, 0.0, WAVE_NOISE, 0.70, 3.4, 0.08, 0.02))
			L.push_back(_layer(0.0, 0.10, 0.0, 0.0, WAVE_NOISE, 0.30, 40.0, 0.8))
		"hammer_slam":
			L.push_back(_layer(0.0, 0.50, 100.0, 34.0, WAVE_SINE, 0.90, 7.0))
			L.push_back(_layer(0.0, 0.28, 0.0, 0.0, WAVE_NOISE, 0.60, 17.0, 0.20))
			L.push_back(_layer(0.0, 0.05, 1500.0, 700.0, WAVE_SQUARE, 0.14, 45.0))
		_:
			pass
	return L

static func _synth(layers: Array[Dictionary]) -> PackedFloat32Array:
	var total: float = 0.05
	for ly: Dictionary in layers:
		total = maxf(total, float(ly["t0"]) + float(ly["dur"]))
	total = minf(total + 0.03, MAX_DURATION_SEC)
	var n: int = int(ceil(total * float(SAMPLE_RATE)))
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)

	var layer_idx: int = 0
	for ly: Dictionary in layers:
		layer_idx += 1
		var start: int = int(float(ly["t0"]) * float(SAMPLE_RATE))
		var len_s: int = int(float(ly["dur"]) * float(SAMPLE_RATE))
		var f0: float = float(ly["f0"])
		var f1: float = float(ly["f1"])
		var wave: int = int(ly["wave"])
		var vol: float = float(ly["vol"])
		var decay: float = float(ly["decay"])
		var lp: float = clampf(float(ly["lp"]), 0.001, 1.0)
		var attack: float = maxf(0.0005, float(ly["attack"]))
		var phase: float = 0.0
		var lcg: int = 1103515245 + layer_idx * 7919
		var lp_state: float = 0.0
		var fade_samples: int = int(0.004 * float(SAMPLE_RATE))
		for k: int in range(len_s):
			var idx: int = start + k
			if idx >= n:
				break
			var t: float = float(k) / float(SAMPLE_RATE)
			var frac: float = float(k) / float(maxi(1, len_s))
			var env: float = minf(1.0, t / attack) * exp(-decay * t)
			var tail: int = len_s - k
			if tail < fade_samples:
				env *= float(tail) / float(fade_samples)
			var s: float = 0.0
			if wave == WAVE_NOISE:
				lcg = (lcg * 1103515245 + 12345) & 0x7FFFFFFF
				var white: float = float(lcg) / 1073741823.5 - 1.0
				lp_state += (white - lp_state) * lp
				s = lp_state
			else:
				var f: float = f0 + (f1 - f0) * frac
				phase += f / float(SAMPLE_RATE)
				phase -= floor(phase)
				if wave == WAVE_SINE:
					s = sin(TAU * phase)
				elif wave == WAVE_SQUARE:
					s = 0.7 if phase < 0.5 else -0.7
				else:
					s = 2.0 * phase - 1.0
			buf[idx] += s * env * vol

	var peak: float = 0.0001
	for i: int in range(n):
		peak = maxf(peak, absf(buf[i]))
	var gain: float = 0.9 / peak
	for i: int in range(n):
		buf[i] = clampf(buf[i] * gain, -1.0, 1.0)
	return buf
