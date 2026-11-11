class_name SpriteMotion
extends RefCounted
## Conservative single-image motion. The Sprite2D's world anchor never moves.


static func pose(seconds: float, phase: float, riding: bool) -> Vector3:
	if riding:
		# Mounted motion is now drawn gait frames, never whole-sprite deformation.
		return Vector3(1.0, 1.0, 0.0)
	var breath := sin(seconds * 1.65 + phase)
	return Vector3(1.0 - breath * 0.004, 1.0 + breath * 0.012, 0.0)
