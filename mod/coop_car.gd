extends Node
# Машины: смотришь на машину из игры → «нажмите [E], чтобы сесть» → едешь сам.
# Сюжетный транспорт (автобусы, Car9) не берём: там E нужна сюжету.
# Едущие машины в игре — VehicleBody со своим скриптом-автопилотом. Скрипт не меняем: на время
# поездки выключаем его _physics_process и сами задаём engine_force / steering / brake.
# Припаркованные — просто модели; при посадке coop_parked.gd собирает из них VehicleBody.
# Игрок «пристёгивается» к машине (статичный, без столкновений), камера — от третьего лица.
#
# Управление: W/S — газ/назад, A/D — руль, пробел — ручник, E — выйти, мышь — оглядеться.
# F1 — поставить перед собой машину из игры (модель по кругу).
# За рулём: N — следующий трек, L — предыдущий (музыка из машин игры, coop_radio.gd),
# V — камера ближе/дальше.
# Машина друга: E рядом с ней — сесть пассажиром (камера едет с ней, E — выйти).

const HINT_ENTER = "нажмите [E], чтобы сесть"
const HINT_EXIT = "[E] — выйти"
const HINT_RIDE = "нажмите [E], чтобы сесть к другу"
# Скрипты машин-автопилотов из городского трафика; у сюжетных (Bus1, Bus2, Car9) скрипты другие.
const TRAFFIC_SCRIPTS = ["Car2", "Car2_2"]
const ENGINE_FORCE = 1800.0
const REVERSE_FORCE = 900.0
const MAX_SPEED = 25.0          # м/с, ~90 км/ч
const COAST_BRAKE = 1.5         # без газа машина плавно тормозит
const BRAKE_FORCE = 25.0        # S на ходу вперёд (или W на ходу назад) — тормоз, а не реверс
const HAND_BRAKE = 20.0
const MAX_STEER = 0.45          # на месте
const MIN_STEER = 0.12          # на скорости STEER_FADE_SPEED и выше
const STEER_FADE_SPEED = 20.0
const STEER_SPEED = 1.6         # рад/с: руль крутится плавно
const STEER_RETURN = 3.0        # а возвращается прямо быстрее
const SAFE_SAMPLE = 0.5         # раз в столько секунд запоминаем место, где машина стоит на колёсах
const SAFE_KEEP = 6             # возвращаем на самое старое из них (~3 с назад), подальше от края
const FALL_DEPTH = 15.0         # на столько ниже последнего надёжного места — значит, упала
const FLIPPED_SECONDS = 3.0
const CAMERA_KEY = KEY_V        # дальность камеры по кругу, как в GTA: San Andreas
const CAM_ZOOMS = [1.0, 1.6, 2.4]
const CAM_ZOOM_NAMES = ["близко", "средне", "далеко"]
const SEAT_HEIGHT = 0.5
const EXIT_SIDE_GAP = 1.6
const DEFAULT_CAR_LENGTH = 4.5
const CAM_LOOK_HEIGHT = 1.2
const CAM_FOLLOW = 6.0          # чем больше, тем жёстче камера держится за машиной
const CAM_LOOK_FOLLOW = 12.0
const CAM_RECENTER_DELAY = 1.5
const CAM_RECENTER_SPEED = 2.0
const CAM_MAX_PITCH = 1.2
const SPAWN_KEY = KEY_F1           # F2–F8 и F11 заняты игрой, F12 — скриншот Steam
const NEXT_TRACK_KEY = KEY_N       # физические клавиши: работают и в русской раскладке
const LAST_TRACK_KEY = KEY_L
const SPAWN_DISTANCE = 5.0
const SPAWN_LIMIT = 3           # больше — самая старая поставленная машина исчезает
const PARKED_BRAKE = 5.0
const TOUCHED_LIMIT = 3
const NET_CARS_LIMIT = 4
# Машины-автопилоты из игры; при постановке их скрипт снимаем, остаётся модель с физикой.
const SPAWN_PREFABS = [
	"res://Prefabs/Car2.tscn", "res://Prefabs/Car3.tscn", "res://Prefabs/Car4.tscn",
	"res://Prefabs/Car5_2.tscn", "res://Prefabs/Car6.tscn", "res://Prefabs/Car7_4.tscn",
	"res://Prefabs/Car8_2.tscn",
]

var Parked = load("user://mods/coop_parked.gd")
var Radio = load("user://mods/coop_radio.gd")
const WORLD_BORDERS_BIT = 1     # слой невидимых стен уровня (WorldBorders)

var coop                        # CoopMod: нужен, чтобы не ездить, пока открыт чат
var parked = []                 # припаркованные машины текущей сцены
var parked_scene_id = 0
var car = null                  # VehicleBody, в которой сидим
var riding = false              # car — машина друга (копия у нас), мы пассажир
var player = null
var camera = null
var player_cam = null           # камера игрока, вернём её после поездки
var spawned = []
var spawn_index = 0
var spawn_serial = 0            # для id поставленных машин в сети
var touched = []                # машины, в которых ездили (не поставленные): их тоже видят друзья
var player_layer = 0
var player_mask = 0
var player_mode = RigidBody.MODE_RIGID
var engine_pitch = 1.0
var cam_yaw = 0.0
var cam_pitch = 0.0
var cam_idle = 0.0
var cam_back = 6.0
var cam_up = 2.5
var cam_zoom = 0                # номер в CAM_ZOOMS; запоминается между поездками
var look_point = Vector3()
var hint_shown = false
var safe_spots = []             # [Transform] последние места, где машина уверенно стояла на дороге
var safe_timer = 0.0
var flipped_time = 0.0


func driving():
	return car != null


# ── вход и выход ───────────────────────────────────────────────────────────
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == SPAWN_KEY:
		if not _blocked() and not driving():
			_spawn()
		return
	if driving() and event is InputEventKey and event.pressed and not event.echo and not _blocked():
		if riding and event.physical_scancode in [NEXT_TRACK_KEY, LAST_TRACK_KEY]:
			return   # музыку в своей машине выбирает друг
		if event.physical_scancode == NEXT_TRACK_KEY:
			_switch_track(1)
			return
		if event.physical_scancode == LAST_TRACK_KEY:
			_switch_track(-1)
			return
		if event.physical_scancode == CAMERA_KEY:
			cam_zoom = (cam_zoom + 1) % CAM_ZOOMS.size()
			_notify("камера: " + CAM_ZOOM_NAMES[cam_zoom])
			return
	if not event.is_action_pressed("interact") or event.is_echo() or _blocked():
		if driving() and event is InputEventMouseMotion:
			_look(event.relative)
		return
	if driving():
		_exit()
	else:
		var target = _looked_at_car()
		if target != null:
			_enter(target, target.has_meta("coop_ghost"))


func _enter(target, passenger = false):
	player = _player()
	player_cam = get_viewport().get_camera()
	if player == null or player_cam == null or _view_of(player) == null:
		player = null
		return
	riding = passenger
	if passenger:
		car = target
		# копия машины друга двигается в своём _process; камеру ставим сразу после неё
		car.connect("moved", self, "_on_ride_moved")
		_mute_interact_fail()
		_seat_player()
		_start_camera()
		return
	if not (target is VehicleBody):
		var path = str(get_tree().current_scene.get_path_to(target))
		parked.erase(target)
		target = Parked.make_drivable(target)
		_tag(target, "p:" + path, "parked", path)
	elif not target.has_meta("coop_id"):
		_tag(target, "t%d" % target.get_instance_id(), "prefab", target.filename.get_file().get_basename())
	if not (target in spawned or target in touched):
		touched.append(target)
		if touched.size() > TOUCHED_LIMIT:
			touched.pop_front()
	car = target
	car.set_collision_mask_bit(WORLD_BORDERS_BIT, true)   # невидимые стены по краю уровня
	safe_spots = []
	safe_timer = 0.0
	flipped_time = 0.0
	car.set_physics_process(false)   # выключаем автопилот машины
	_mute_interact_fail()
	car.sleeping = false
	var engine = _engine_audio()
	engine_pitch = engine.pitch_scale if engine else 1.0
	_seat_player()
	_start_camera()


# Игрок «пристёгивается»: стоит неподвижно, без столкновений, управление у машины.
func _seat_player():
	player_layer = player.collision_layer
	player_mask = player.collision_mask
	player_mode = player.mode
	player.is_active = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.mode = RigidBody.MODE_STATIC
	_set_crosshair(false)


func _start_camera():
	var length = _car_length()
	cam_back = length * 1.2 + 1.0
	cam_up = length * 0.35 + 1.0
	cam_yaw = 0.0
	cam_pitch = 0.0
	camera = Camera.new()
	# дальность прорисовки как у камеры игрока: у новой Camera far = 100 м, и дома мигают
	camera.fov = player_cam.fov
	camera.near = player_cam.near
	camera.far = player_cam.far
	camera.cull_mask = player_cam.cull_mask
	camera.environment = player_cam.environment
	camera.doppler_tracking = player_cam.doppler_tracking
	get_tree().current_scene.add_child(camera)
	camera.global_transform = _camera_target()
	look_point = car.global_transform.origin + Vector3.UP * CAM_LOOK_HEIGHT
	camera.make_current()


func _on_ride_moved(delta):
	if not riding or not is_instance_valid(car) or not is_instance_valid(player):
		return
	player.global_transform.origin = car.global_transform.origin + Vector3.UP * SEAT_HEIGHT
	_update_camera(delta)


func _exit():
	if riding and is_instance_valid(car) and car.is_connected("moved", self, "_on_ride_moved"):
		car.disconnect("moved", self, "_on_ride_moved")
	if is_instance_valid(car) and not riding:
		car.engine_force = 0
		car.steering = 0
		car.brake = PARKED_BRAKE
		var engine = _engine_audio()
		if engine:
			engine.pitch_scale = engine_pitch
	if is_instance_valid(player):
		var side = car.global_transform.basis.x if is_instance_valid(car) else Vector3.RIGHT
		if riding:
			side = -side   # пассажир выходит с другой стороны
		player.global_transform.origin += -side * EXIT_SIDE_GAP + Vector3.UP * 0.5
		player.mode = player_mode
		player.collision_layer = player_layer
		player.collision_mask = player_mask
		player.linear_velocity = Vector3.ZERO
		# игрок оживает со следующего кадра, чтобы это же нажатие E не сработало у игры
		player.call_deferred("set", "is_active", true)
		if is_instance_valid(player_cam):
			player_cam.make_current()
		_set_crosshair(true)
	if is_instance_valid(camera):
		camera.queue_free()
	car = null
	riding = false
	player = null
	camera = null
	player_cam = null


# Машину или игрока убрала сцена (смена уровня, машина доехала и исчезла).
func _drop_if_gone():
	if not driving():
		return
	if is_instance_valid(player) and is_instance_valid(car) and car.is_inside_tree():
		return
	if is_instance_valid(player):
		_exit()
		return
	if is_instance_valid(camera):
		camera.queue_free()
	car = null
	riding = false
	player = null
	camera = null


# ── музыка ─────────────────────────────────────────────────────────────────
func _switch_track(step):
	var count = Radio.TRACKS.size()
	var index = Radio.track_of(car)
	if index == Radio.NONE:
		index = 0 if step > 0 else count - 1
	else:
		index = posmod(index + step, count)
	Radio.set_track(car, index)
	_notify("музыка: " + Radio.title(index))


# ── падение с карты ────────────────────────────────────────────────────────
# Не телепортируем в другое место: возвращаем машину на дорогу, где она была ~3 с назад.
func _watch_fall(delta):
	var upright = car.global_transform.basis.y.y > 0.8
	safe_timer += delta
	if safe_timer >= SAFE_SAMPLE:
		safe_timer = 0.0
		if upright and _wheels_on_ground():
			safe_spots.append(car.global_transform)
			if safe_spots.size() > SAFE_KEEP:
				safe_spots.pop_front()
	flipped_time = 0.0 if upright else flipped_time + delta
	if safe_spots.empty():
		return
	var fell = car.global_transform.origin.y < safe_spots[-1].origin.y - FALL_DEPTH
	if fell or flipped_time > FLIPPED_SECONDS:
		_recover()


func _recover():
	var spot = safe_spots[0]
	car.global_transform = Transform(Basis(Vector3.UP, spot.basis.get_euler().y), spot.origin + Vector3.UP * 0.5)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.steering = 0.0
	safe_spots = [car.global_transform]
	flipped_time = 0.0
	_notify("машина возвращена на дорогу")


func _wheels_on_ground():
	var any = false
	for child in car.get_children():
		if child is VehicleWheel:
			any = true
			if not child.is_in_contact():
				return false
	return any


func _notify(text):
	if coop and coop.has_method("notify"):
		coop.notify(text)


# ── езда ───────────────────────────────────────────────────────────────────
func _physics_process(delta):
	_drop_if_gone()
	if not driving() or riding:
		return
	var throttle = 0.0
	var steer = 0.0
	var hand = false
	if not _blocked():
		throttle = Input.get_action_strength("forward") - Input.get_action_strength("backward")
		steer = Input.get_action_strength("left") - Input.get_action_strength("right")
		hand = Input.is_action_pressed("jump")
	var speed = car.linear_velocity.length()
	var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)   # перед — +Z
	var braking = (throttle < 0 and forward_speed > 1.0) or (throttle > 0 and forward_speed < -1.0)
	if braking or throttle == 0:
		car.engine_force = 0.0
	elif throttle > 0:
		car.engine_force = ENGINE_FORCE * throttle if speed < MAX_SPEED else 0.0
	else:
		car.engine_force = REVERSE_FORCE * throttle
	if hand:
		car.brake = HAND_BRAKE
	elif braking:
		car.brake = BRAKE_FORCE * abs(throttle)
	else:
		car.brake = COAST_BRAKE if throttle == 0 else 0.0
	# на скорости руль слабее, иначе машину резко бросает в сторону
	var limit = lerp(MAX_STEER, MIN_STEER, clamp(speed / STEER_FADE_SPEED, 0.0, 1.0))
	var rate = STEER_RETURN if steer == 0 else STEER_SPEED
	car.steering = move_toward(car.steering, steer * limit, rate * delta)
	_watch_fall(delta)
	var engine = _engine_audio()
	if engine:
		engine.pitch_scale = clamp(engine_pitch * (0.8 + speed / MAX_SPEED), 0.5, 2.5)
	# игрок сидит в машине: так его видят друзья, и он не отстанет при выходе
	player.global_transform.origin = car.global_transform.origin + Vector3.UP * SEAT_HEIGHT
	_update_camera(delta)


func _process(_delta):
	_refresh_parked()
	_update_hint()


# Камера двигается в физическом шаге, вместе с машиной. В _process на кадр иногда приходится
# 0 или 2 шага физики (60 Гц), и машина на экране дёргалась относительно камеры.
func _update_camera(delta):
	if not is_instance_valid(camera):
		return
	cam_idle += delta
	if cam_idle > CAM_RECENTER_DELAY:
		cam_yaw = lerp(cam_yaw, 0.0, min(1.0, CAM_RECENTER_SPEED * delta))
		cam_pitch = lerp(cam_pitch, 0.0, min(1.0, CAM_RECENTER_SPEED * delta))
	var target = _camera_target()
	var t = min(1.0, CAM_FOLLOW * delta)
	camera.global_transform.origin = camera.global_transform.origin.linear_interpolate(target.origin, t)
	# точка взгляда тоже сглажена: подвеска качает кузов, и камера не трясётся вместе с ним
	var look = car.global_transform.origin + Vector3.UP * CAM_LOOK_HEIGHT
	look_point = look_point.linear_interpolate(look, min(1.0, CAM_LOOK_FOLLOW * delta))
	camera.look_at(look_point, Vector3.UP)


func _look(relative):
	var vars = get_node_or_null("/root/PlayerVariables")
	var sx = vars.mouse_sensitivity_x if vars else 1.0
	var sy = vars.mouse_sensitivity_y if vars else 1.0
	cam_yaw -= deg2rad(relative.x * sx * 0.2)
	cam_pitch = clamp(cam_pitch + deg2rad(relative.y * sy * 0.2), -0.3, CAM_MAX_PITCH)
	cam_idle = 0.0


# Точка за машиной с учётом поворота камеры мышью; крен и тангаж машины не важны.
func _camera_target():
	var origin = car.global_transform.origin
	var back = -car.global_transform.basis.z   # перед машин в игре — +Z
	back.y = 0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	back = back.rotated(Vector3.UP, cam_yaw)
	var dist = cam_back * CAM_ZOOMS[cam_zoom]
	var height = cam_up * CAM_ZOOMS[cam_zoom]
	var offset = back * dist * cos(cam_pitch) + Vector3.UP * (height + dist * sin(cam_pitch))
	var xf = Transform(Basis(), origin + offset)
	return xf.looking_at(origin + Vector3.UP * CAM_LOOK_HEIGHT, Vector3.UP)


# ── подсказка ──────────────────────────────────────────────────────────────
# HUDRay игры стирает подсказку каждый физический кадр; пишем её в _process, после физики.
func _update_hint():
	var label = _hint_label()
	if label == null:
		hint_shown = false
		return
	var text = ""
	if driving():
		text = HINT_EXIT
	elif not _blocked():
		var target = _looked_at_car()
		if target != null:
			text = HINT_RIDE if target.has_meta("coop_ghost") else HINT_ENTER
	if text != "":
		label.text = text
		hint_shown = true
	elif hint_shown:
		if label.text in [HINT_ENTER, HINT_EXIT, HINT_RIDE]:
			label.text = ""
		hint_shown = false


# Едущая машина: луч подсказок игры (1.95 м) попадает в кузов или в его зоны (SafeArea и т.п.).
# Припаркованная: свой луч против габаритов кузова.
func _looked_at_car():
	var p = _player()
	if p == null or not p.is_active:
		return null
	var ray = p.get_node_or_null("RotationHelper/HUDRay")
	if ray == null:
		return null
	var node = ray.get_collider()
	for _i in range(3):
		if node == null:
			break
		if node is VehicleBody:
			return node if node.is_visible_in_tree() and _is_drivable(node) else null
		node = node.get_parent()
	var view = _view_of(p)
	if view == null:
		return null
	var cam = view.global_transform
	var standing = Parked.looked_at(parked, cam.origin, -cam.basis.z)
	return standing if standing != null else _looked_at_ghost(cam.origin, -cam.basis.z)


# Машина друга без столкновений — луч игры её не видит; свой луч против габаритов кузова.
func _looked_at_ghost(from, dir):
	if coop == null or not ("avatars" in coop):
		return null
	var best = null
	var best_t = 1.0
	for avatar in coop.avatars.values():
		if not is_instance_valid(avatar):
			continue
		for ghost in avatar.ghosts.values():
			if not is_instance_valid(ghost) or not ghost.is_visible_in_tree():
				continue
			var body = _body_mesh_of(ghost)
			if body == null:
				continue
			var to_local = body.global_transform.affine_inverse()
			var t = Parked._segment_hits_box(to_local.xform(from), to_local.xform(from + dir * Parked.REACH), body.get_aabb())
			if t >= 0 and t < best_t:
				best = ghost
				best_t = t
	return best


func _body_mesh_of(vehicle):
	for child in vehicle.get_children():
		if child is MeshInstance:
			return child
	return null


# Наши машины (поставленные или собранные из припаркованных) — без скрипта; из игры — только трафик.
func _is_drivable(vehicle):
	var script = vehicle.get_script()
	if script == null:
		return true
	return script.resource_path.get_file().get_basename() in TRAFFIC_SCRIPTS


# Новая сцена — заново ищем в ней припаркованные машины.
func _refresh_parked():
	var scene = get_tree().current_scene
	if scene == null or scene.get_instance_id() == parked_scene_id:
		return
	parked_scene_id = scene.get_instance_id()
	parked = [] if coop._in_main_menu() else Parked.find_all(scene)
	spawned = []
	touched = []


# ── сеть ───────────────────────────────────────────────────────────────────
# Метка машины для друзей: id (свой у каждого игрока) и как собрать такую же модель.
func _tag(vehicle, id, kind, ref):
	vehicle.set_meta("coop_id", id)
	vehicle.set_meta("coop_kind", kind)
	vehicle.set_meta("coop_ref", ref)


# Наши машины для пакета состояния: та, в которой сидим, поставленные по F1 и те, в которых
# ездили. Не больше NET_CARS_LIMIT: ненадёжный пакет Steam вмещает только 1200 байт.
func net_cars():
	var out = []
	var listed = []
	for c in [car] + spawned + touched:
		if out.size() >= NET_CARS_LIMIT or c in listed:
			continue
		if not is_instance_valid(c) or not c.is_inside_tree() or not c.has_meta("coop_id"):
			continue
		listed.append(c)
		out.append({
			"i": c.get_meta("coop_id"),
			"k": c.get_meta("coop_kind"),
			"r": c.get_meta("coop_ref"),
			"p": c.global_transform.origin,
			"q": Quat(c.global_transform.basis.orthonormalized()),
			"w": c.steering,
			"v": c.linear_velocity.dot(c.global_transform.basis.z),
			"m": Radio.track_of(c),
		})
	return out


# Друг взял стоящую машину: забираем её модель из нашего списка, чтобы собрать из неё копию.
func claim_parked(path):
	var scene = get_tree().current_scene
	for root in parked:
		if is_instance_valid(root) and str(scene.get_path_to(root)) == path:
			parked.erase(root)
			return root
	return null


# ── постановка машин ───────────────────────────────────────────────────────
# Машина встаёт боком в SPAWN_DISTANCE м перед игроком, чтобы сразу можно было подойти к двери.
func _spawn():
	var p = _player()
	var view = _view_of(p) if p else null
	if view == null:
		return
	var prefab = load(SPAWN_PREFABS[spawn_index % SPAWN_PREFABS.size()])
	spawn_index += 1
	if prefab == null:
		return
	var new_car = prefab.instance()
	new_car.set_script(null)   # без автопилота: ему нужен маршрут из уровня
	var forward = -view.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var origin = p.global_transform.origin + forward * SPAWN_DISTANCE + Vector3.UP * 0.5
	get_tree().current_scene.add_child(new_car)
	new_car.global_transform = Transform(Basis(Vector3.UP, atan2(forward.x, forward.z) + PI / 2), origin)
	new_car.brake = PARKED_BRAKE
	new_car.set_collision_mask_bit(WORLD_BORDERS_BIT, true)
	spawn_serial += 1
	_tag(new_car, "s%d" % spawn_serial, "prefab", prefab.resource_path.get_file().get_basename())
	spawned.append(new_car)
	_notify("машина появилась")
	_trim_spawned()


func _trim_spawned():
	var alive = []
	for c in spawned:
		if is_instance_valid(c):
			alive.append(c)
	while alive.size() > SPAWN_LIMIT:
		var old = alive.pop_front()
		if old != car:
			old.queue_free()
	spawned = alive


# ── помощники ──────────────────────────────────────────────────────────────
func _blocked():
	if get_tree().paused:
		return true
	return coop != null and coop.chat != null and coop.chat.is_open()


func _player():
	if coop == null:
		return null
	return coop._local_player()


# Камера игрока (PlayerDrunkCamera) на старте уходит из RotationHelper в корень уровня и
# каждый кадр догоняет RotationHelper — поэтому направление взгляда берём у него.
func _view_of(p):
	return p.get_node_or_null("RotationHelper")


func _hint_label():
	var p = _player()
	return p.get_node_or_null("HUD/Hint") if p else null


func _set_crosshair(visible):
	var crosshair = player.get_node_or_null("HUD/Crosshair")
	if crosshair:
		crosshair.visible = visible


# InteractRay игры тоже ловит E и, не найдя interact() у машины, щёлкает «не получилось».
func _mute_interact_fail():
	var sound = player.get_node_or_null("RotationHelper/InteractRay/InteractFailSound")
	if sound:
		sound.call_deferred("stop")


func _engine_audio():
	for path in ["EngineSound", "EngineAudio"]:
		var node = car.get_node_or_null(path)
		if node is AudioStreamPlayer3D:
			return node
	return null


func _car_length():
	for child in car.get_children():
		if child is MeshInstance:
			return max(child.get_aabb().size.z, child.get_aabb().size.x)
	return DEFAULT_CAR_LENGTH
