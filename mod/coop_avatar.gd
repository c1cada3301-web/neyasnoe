extends Spatial
# Второй игрок в мире: выбранный им скин (прохожий из игры без скрипта, коллизий и триггеров),
# плавно догоняет присланные позиции. Над головой — имя из Steam. Сигарета и фонарик —
# из coop_props.gd.

var Skins = load("user://mods/coop_skins.gd")
var Ghost = load("user://mods/coop_ghost_car.gd")
var Props = load("user://mods/coop_props.gd")

const WALK_THRESHOLD = 0.5
const FOLLOW_SPEED = 12.0
const NAME_HEIGHT = 2.0
const NAME_FONT_SIZE = 13
const TELEPORT_DISTANCE = 8.0
const MAX_CARS = 8              # больше машин от одного игрока не принимаем
const PREFAB_DIR = "res://Prefabs/"
const STORY_PREFABS = ["res://Prefabs/Car9.tscn"]

var display_name = ""
var name_color = Color(1, 1, 1)
var skin_id = ""
var skin
var target_pos = Vector3()
var target_yaw = 0.0
var speed = 0.0
var has_state = false
var label
var ghosts = {}                 # id машины друга → её копия у нас
var failed = {}                 # id, которые не удалось собрать: не пробуем каждый пакет
var cigarette                   # у рта скина; пересобирается со скином
var flashlight
var smoking = false
var lit = false
var pitch = 0.0
var driving_now = false


func _ready():
	# пауза у каждого своя: друг продолжает ходить, даже когда у нас открыто меню паузы
	pause_mode = Node.PAUSE_MODE_PROCESS
	# курсив Old Standard, как в субтитрах игры (у шрифта Godot по умолчанию нет кириллицы)
	var base = load("res://Assets/Fonts/OldStandardItalic.tres")
	label = Label.new()
	if base is DynamicFont:
		var font = base.duplicate()
		font.size = NAME_FONT_SIZE
		label.add_font_override("font", font)
	label.text = display_name
	label.align = Label.ALIGN_CENTER
	label.add_color_override("font_color", name_color)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	label.visible = false   # покажем, когда будет известно, где голова
	var layer = CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
	flashlight = Props.flashlight()
	add_child(flashlight)
	visible = false


func set_name_color(color):
	name_color = color
	if label:
		label.add_color_override("font_color", color)


func set_skin(id):
	id = Skins.id_at(Skins.index_of(id))   # только из списка: id приходит по сети
	if id == skin_id:
		return
	skin_id = id
	if skin:
		skin["node"].queue_free()
	skin = Skins.build(id)
	if skin == null:
		push_warning("CoopMod: не удалось собрать скин " + id)
		return
	add_child(skin["node"])
	Skins.play_idle(skin, 0.0)
	if cigarette and is_instance_valid(cigarette):
		cigarette.queue_free()
	cigarette = Props.attach_cigarette(self, skin["node"])
	_update_props()


func push_state(pos, yaw, move_speed, id, driving = false):
	driving_now = driving
	set_skin(id)
	if skin:
		skin["node"].visible = not driving   # за рулём видна машина, над ней — имя
	_update_props()
	target_pos = pos
	target_yaw = yaw
	speed = move_speed
	if not has_state or global_transform.origin.distance_to(pos) > TELEPORT_DISTANCE:
		global_transform.origin = pos
		rotation.y = yaw
	has_state = true
	visible = true


# Курит ли друг, горит ли у него фонарик и куда он смотрит (наклон головы, радианы).
func push_props(is_smoking, is_lit, look_pitch):
	smoking = is_smoking
	lit = is_lit
	pitch = clamp(look_pitch, -1.5, 1.5)
	_update_props()


func _update_props():
	if cigarette and is_instance_valid(cigarette):
		cigarette.visible = smoking and not driving_now
	if flashlight:
		flashlight.visible = lit and not driving_now
		flashlight.rotation.x = pitch


# ── машины друга ───────────────────────────────────────────────────────────
# cars приходят по сети: каждую запись проверяем, модель берём только из машин игры.
func push_cars(cars, local_cars):
	if typeof(cars) != TYPE_ARRAY:
		cars = []
	var seen = {}
	for n in range(min(cars.size(), MAX_CARS)):
		var c = cars[n]
		if not _valid_car(c):
			continue
		var id = c["i"]
		seen[id] = true
		var ghost = ghosts.get(id)
		if (ghost == null or not is_instance_valid(ghost)) and not failed.has(id):
			ghost = _build_ghost(c, local_cars)
			if ghost == null:
				failed[id] = true
				continue
			ghosts[id] = ghost
		if ghost != null and is_instance_valid(ghost):
			ghost.push(c["p"], c["q"], clamp(c["w"], -1.0, 1.0), c["v"])
			var track = c.get("m")
			if typeof(track) == TYPE_INT:
				ghost.set_track(track)
	for id in ghosts.keys():
		if not seen.has(id):
			if is_instance_valid(ghosts[id]):
				ghosts[id].queue_free()
			ghosts.erase(id)


func _valid_car(c):
	if typeof(c) != TYPE_DICTIONARY:
		return false
	return typeof(c.get("i")) == TYPE_STRING and typeof(c.get("k")) == TYPE_STRING \
		and typeof(c.get("r")) == TYPE_STRING and typeof(c.get("p")) == TYPE_VECTOR3 \
		and typeof(c.get("q")) == TYPE_QUAT and typeof(c.get("w")) == TYPE_REAL \
		and typeof(c.get("v")) == TYPE_REAL


func _build_ghost(c, local_cars):
	var scene = get_tree().current_scene
	var vehicle = null
	if c["k"] == "prefab":
		var ref = c["r"]   # имя сцены машины, например Car5_2
		if not ref.begins_with("Car") or not ref.substr(3).replace("_", "").is_valid_integer():
			return null
		var path = PREFAB_DIR + ref + ".tscn"
		if path in STORY_PREFABS:
			return null
		var prefab = load(path)
		if not (prefab is PackedScene):
			return null
		vehicle = prefab.instance()
		if not (vehicle is VehicleBody):
			vehicle.free()
			return null
		vehicle.set_script(Ghost)
		scene.add_child(vehicle)
	elif c["k"] == "parked" and local_cars:
		var root = local_cars.claim_parked(c["r"])   # у нас эта модель уходит со своего места
		if root == null:
			return null
		vehicle = local_cars.Parked.make_drivable(root)
		vehicle.set_script(Ghost)
	else:
		return null
	vehicle.setup()
	return vehicle


func _exit_tree():
	for id in ghosts:
		if is_instance_valid(ghosts[id]):
			ghosts[id].queue_free()
	ghosts = {}


func _process(delta):
	if not has_state:
		return
	var k = clamp(delta * FOLLOW_SPEED, 0.0, 1.0)
	global_transform.origin = global_transform.origin.linear_interpolate(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)
	if skin:
		if speed > WALK_THRESHOLD:
			Skins.play_walk(skin)
		else:
			Skins.play_idle(skin)
	_update_label()


func _update_label():
	var cam = get_viewport().get_camera()
	var head = global_transform.origin + Vector3(0, NAME_HEIGHT, 0)
	if cam == null or cam.is_position_behind(head):
		label.visible = false
		return
	label.visible = true
	var p = cam.unproject_position(head)
	label.rect_position = p - Vector2(label.rect_size.x / 2.0, label.rect_size.y)
