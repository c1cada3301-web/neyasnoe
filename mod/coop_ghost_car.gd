extends VehicleBody
# Машина другого игрока у нас в мире: та же модель, но без своей физики. Неподвижное тело
# без столкновений (сквозь неё проезжают), которое плавно догоняет присланные положения.
# Колёса крутим и поворачиваем сами: у неподвижного VehicleBody игра их не двигает.

const FOLLOW_SPEED = 10.0
const TELEPORT_DISTANCE = 8.0
const DEFAULT_WHEEL_RADIUS = 0.35

var Radio = load("user://mods/coop_radio.gd")
var track = -2                  # ещё не знаем, что играет у друга

var target_pos = Vector3()
var target_rot = Quat()
var steer = 0.0
var speed = 0.0                 # м/с вдоль машины, со знаком
var has_state = false
var rolled = 0.0                # сколько метров проехали колёса — из этого их угол
var engine_pitch = 1.0


func setup():
	set_physics_process(false)
	set_process(true)   # скрипт мог быть назначен узлу, который уже в сцене
	mode = RigidBody.MODE_STATIC
	collision_layer = 0
	collision_mask = 0
	set_as_toplevel(true)
	set_meta("coop_ghost", true)
	var engine = _engine_audio()
	if engine:
		engine_pitch = engine.pitch_scale


func push(pos, rot, steering, forward_speed):
	target_pos = pos
	target_rot = rot
	steer = steering
	speed = forward_speed
	if not has_state or global_transform.origin.distance_to(pos) > TELEPORT_DISTANCE:
		global_transform = Transform(Basis(rot), pos)
	has_state = true


# Номер трека из TRACKS или NONE; меняем, только если у друга сменился трек.
func set_track(index):
	if index < Radio.NONE or index >= Radio.TRACKS.size() or index == track:
		return
	track = index
	Radio.set_track(self, index)


func _process(delta):
	if not has_state:
		return
	var k = clamp(delta * FOLLOW_SPEED, 0.0, 1.0)
	var rot = Quat(global_transform.basis).slerp(target_rot, k)
	global_transform = Transform(Basis(rot), global_transform.origin.linear_interpolate(target_pos, k))
	_turn_wheels(delta)
	var engine = _engine_audio()
	if engine:
		engine.pitch_scale = clamp(engine_pitch * (0.8 + abs(speed) / 25.0), 0.5, 2.5)


# Перед машины — +Z: при езде вперёд верх колеса уходит к +Z, это поворот вокруг +X.
func _turn_wheels(delta):
	rolled += speed * delta
	for wheel in get_children():
		if not (wheel is VehicleWheel):
			continue
		var radius = wheel.wheel_radius if wheel.wheel_radius > 0.01 else DEFAULT_WHEEL_RADIUS
		var yaw = steer if wheel.use_as_steering else 0.0
		wheel.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, fmod(rolled / radius, TAU))


func _engine_audio():
	for path in ["EngineSound", "EngineAudio"]:
		var node = get_node_or_null(path)
		if node is AudioStreamPlayer3D:
			return node
	return null
