class_name GameRng
extends RefCounted
## Seedable, platform-independent PRNG (xorshift32).
##
## We deliberately do not use Godot's RandomNumberGenerator so that combat
## results stay identical across engine versions and platforms. Only shifts,
## xors and 32-bit masks are used, so there is no integer-overflow ambiguity.

const MASK32 := 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	# Fold 64-bit seed into 32 bits, avoid the all-zero state, then warm up.
	var s := (seed_value ^ (seed_value >> 32) ^ 0x9E3779B9) & MASK32
	if s == 0:
		s = 0x6D2B79F5
	state = s
	for i in 8:
		next_u32()


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK32
	x ^= x >> 17
	x ^= (x << 5) & MASK32
	state = x & MASK32
	return state


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Uniform integer in [lo, hi] (inclusive).
func next_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(next_float() * float(hi - lo + 1))


func next_float_range(lo: float, hi: float) -> float:
	return lo + next_float() * (hi - lo)


func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return next_float() < p


## Picks an index with probability proportional to weights[i]. Returns -1 if empty.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if weights.is_empty():
		return -1
	if total <= 0.0:
		return next_int(0, weights.size() - 1)
	var r := next_float() * total
	for i in weights.size():
		r -= maxf(0.0, float(weights[i]))
		if r < 0.0:
			return i
	return weights.size() - 1


## Derives an independent generator (e.g. one per battle) without consuming
## much of this stream.
func fork(salt: int) -> GameRng:
	return GameRng.new(next_u32() ^ ((salt * 7919) & MASK32))


## Stable 32-bit mix of two integers, used to derive seeds.
static func mix(a: int, b: int) -> int:
	var r := GameRng.new(a ^ ((b << 16) & MASK32) ^ (b >> 16))
	return r.next_u32()

# NOTE: methods are deliberately not named randf/randi_range: inside this class
# such calls would resolve to Godot's global (unseeded) utility functions.
