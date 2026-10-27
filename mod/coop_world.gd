extends Node
# Общий мир: предметы в руках, разбитые бутылки, включённые радио и свечи, открытая дверь.
#
# Предметы и вещи на уровне есть у каждого игрока свои, но лежат по одним и тем же путям
# в сцене — по пути и находим «тот же» предмет у друга.
#
#   • Предмет в руках (DragRay игры): путь и положение идут в пакете состояния («g»), пока
#     держим и ещё SETTLE секунд после броска. У друга предмет на это время становится
#     кинематическим и плавно повторяет движение, потом снова падает и катится сам.
#   • Включил радио или свечу, открыл дверь, выпил пиво — надёжное событие (send_event).
#     Только по нажатию E у себя: принятые от друга события дальше не пересылаем.
#   • Бутылка разбилась у того, кто её бросил, — событие, у друга она бьётся тоже.

const SETTLE = 2.5              # сколько ещё слать брошенный предмет, пока он летит и катится
const FOLLOW_SPEED = 14.0
const TELEPORT_DISTANCE = 6.0
# Скрипт → поле «включено». Переключаются через interact() — со звуком, как у самой игры.
const TOGGLES = {"Radio1": "is_active", "MoonlightCandle1": "is_active"}
const DOOR = "OldDoor1"         # дверь открывается один раз: perform()
const BEER = "BeerDrinker1"     # Area на бутылке: у друга бутылка просто пустеет
const WATCH_LIMIT = 8           # сколько последних взятых в руки предметов проверяем на «разбился»

var coop
var held = null                 # что держим сами (или бросили и ещё досылаем)
var held_path = ""
var released_at = -1.0          # OS.get_ticks_msec() / 1000 в момент броска
var watched = {}                # путь → предмет, которые мы держали: следим, не разбились ли
var remote = {}                 # steam id друга → {"node", "path", "mode", "target", "rot", "lv"}
var scene_id = 0


# ── свои предметы ──────────────────────────────────────────────────────────
func _physics_process(_delta):
	_reset_on_new_scene()
	var player = coop._local_player() if coop else null
	var ray = player.get_node_or_null("RotationHelper/DragRay") if player else null
	var now = OS.get_ticks_msec() / 1000.0
	var dragged = ray.dragged_object if ray else null
	if dragged != null and is_instance_valid(dragged):
		if dragged != held:
			held = dragged
			held_path = _path_of(held)
			watched.erase(held_path)
			watched[held_path] = held   # в конец: самые старые вылетают первыми
			while watched.size() > WATCH_LIMIT:
				watched.erase(watched.keys()[0])
		released_at = -1.0
	elif held != null:
		if released_at < 0:
			released_at = now
		if not is_instance_valid(held) or now - released_at > SETTLE:
			held = null
			held_path = ""
	_watch_breaks()


# Новый уровень: старые предметы уже удалены сценой — это не «разбились».
func _reset_on_new_scene():
	var scene = get_tree().current_scene
	var id = scene.get_instance_id() if scene else 0
	if id == scene_id:
		return
	scene_id = id
	held = null
	held_path = ""
	watched = {}
	remote = {}


# Для пакета состояния: что у нас в руках (или ещё летит после броска), иначе null.
func held_state():
	if held == null or not is_instance_valid(held) or held_path == "":
		return null
	if held.get("is_breaking") == true:
		return null
	return {
		"p": held_path,
		"o": held.global_transform.origin,
		"q": Quat(held.global_transform.basis.orthonormalized()),
		"lv": held.linear_velocity,
	}


func _watch_breaks():
	for path in watched.keys():
		var node = watched[path]
		if not is_instance_valid(node) or node.get("is_breaking") == true:
			coop.send_event({"k": "br", "p": path})
			watched.erase(path)


# ── E: радио, свеча, дверь, пиво ───────────────────────────────────────────
# Наш _input идёт после игры (автозагрузка выше сцены), поэтому interact() уже сработал
# и у предмета новое состояние — его и отправляем.
func _input(event):
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	var player = coop._local_player() if coop else null
	var ray = player.get_node_or_null("RotationHelper/InteractRay") if player else null
	var body = ray.get_collider() if ray else null
	if body == null:
		return
	var kind = _script_name(body)
	var path = _path_of(body)
	if path == "":
		return
	if TOGGLES.has(kind) or kind == DOOR:
		call_deferred("_send_toggle", body, path, kind)
	elif kind == BEER:
		coop.send_event({"k": "beer", "p": path})


func _send_toggle(body, path, kind):
	if not is_instance_valid(body):
		return
	var field = TOGGLES.get(kind, "is_active")
	coop.send_event({"k": "tg", "p": path, "a": body.get(field) == true})


# ── от друга ───────────────────────────────────────────────────────────────
func apply_event(e, scene):
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("p")) != TYPE_STRING:
		return
	var node = scene.get_node_or_null(e["p"])
	if node == null:
		return
	match e.get("k"):
		"tg":
			_apply_toggle(node, e.get("a") == true)
		"br":
			if node.has_method("blow_up") and node.get("is_breaking") != true:
				_release_remote_node(node)
				node.blow_up()
		"beer":
			if _script_name(node) == BEER and node.get("is_acitve") != true:
				node.is_acitve = true   # опечатка игры: is_acitve
				node.hint = ""
				node.drink_mesh.mesh = node.empty_vessel_mesh


func _apply_toggle(node, on):
	var kind = _script_name(node)
	if TOGGLES.has(kind):
		if (node.get(TOGGLES[kind]) == true) != on:
			node.interact()
	elif kind == DOOR:
		if on and node.get("is_active") != true:
			node.perform()


# Друг держит предмет g (или null — отпустил). У нас предмет на это время кинематический.
func apply_held(id, g, scene):
	var slot = remote.get(id)
	var path = g.get("p") if typeof(g) == TYPE_DICTIONARY else null
	if slot != null and (path == null or path != slot["path"]):
		_release_slot(slot)
		remote.erase(id)
		slot = null
	if typeof(path) != TYPE_STRING:
		return
	if typeof(g.get("o")) != TYPE_VECTOR3 or typeof(g.get("q")) != TYPE_QUAT:
		return
	if slot == null:
		var node = scene.get_node_or_null(path)
		if not (node is RigidBody) or not node.has_method("start_drag") or node == held:
			return
		slot = {"node": node, "path": path, "mode": node.mode}
		node.mode = RigidBody.MODE_KINEMATIC
		node.global_transform = Transform(Basis(g["q"]), g["o"])
		remote[id] = slot
	slot["target"] = g["o"]
	slot["rot"] = g["q"]
	slot["lv"] = g.get("lv") if typeof(g.get("lv")) == TYPE_VECTOR3 else Vector3()


func forget(id):
	if remote.has(id):
		_release_slot(remote[id])
		remote.erase(id)


func _process(delta):
	var k = clamp(delta * FOLLOW_SPEED, 0.0, 1.0)
	for id in remote.keys():
		var slot = remote[id]
		var node = slot["node"]
		if not is_instance_valid(node) or not slot.has("target"):
			continue
		var origin = node.global_transform.origin
		if origin.distance_to(slot["target"]) > TELEPORT_DISTANCE:
			origin = slot["target"]
		var rot = Quat(node.global_transform.basis.orthonormalized()).slerp(slot["rot"], k)
		node.global_transform = Transform(Basis(rot), origin.linear_interpolate(slot["target"], k))


func _release_slot(slot):
	var node = slot["node"]
	if not is_instance_valid(node):
		return
	node.mode = slot["mode"]
	node.linear_velocity = slot.get("lv", Vector3())
	node.sleeping = false


func _release_remote_node(node):
	for id in remote.keys():
		if remote[id]["node"] == node:
			_release_slot(remote[id])
			remote.erase(id)


# ── помощники ──────────────────────────────────────────────────────────────
func _path_of(node):
	var scene = get_tree().current_scene
	if scene == null or not is_instance_valid(node) or not scene.is_a_parent_of(node):
		return ""
	return str(scene.get_path_to(node))


static func _script_name(node):
	var script = node.get_script()
	return script.resource_path.get_file().get_basename() if script else ""
