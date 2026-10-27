extends Reference
# Скины для кооп-мода: прохожие из игры, у которых есть анимация ходьбы.
# Модель собирается из префаба без скриптов, коллизий, звуков и триггеров —
# остаётся только меш со скелетом и AnimationPlayer.

const SKINS = [
	["Man5", "Прохожий в белой куртке", "Guy in a white jacket"],
	["Man4", "Прохожий 4", "Passer-by 4"],
	["Man6", "Прохожий с телефоном", "Guy with a phone"],
	["Man14", "Официант", "Waiter"],
	["Man16", "Прохожий 16", "Passer-by 16"],
	["Man17", "Прохожий 17", "Passer-by 17"],
	["Man18", "Прохожий 18", "Passer-by 18"],
	["Man19", "Пьяный", "Drunk guy"],
	["Man20", "Прохожий 20", "Passer-by 20"],
	["Man21", "Прохожий 21", "Passer-by 21"],
	["Man22", "Прохожий 22", "Passer-by 22"],
	["Man28", "Зритель 28", "Spectator 28"],
	["Man30", "Зритель 30", "Spectator 30"],
	["Man32", "Зритель 32", "Spectator 32"],
	["Man35", "Прохожий 35", "Passer-by 35"],
	["Man36", "Зритель 36", "Spectator 36"],
	["Man37", "Прохожий 37", "Passer-by 37"],
	["Man38Ilya", "Илья", "Ilya"],
	["Woman13", "Прохожая 13", "Passer-by 13"],
	["Woman14", "Зрительница 14", "Spectator 14"],
	["Woman16", "Зрительница 16", "Spectator 16"],
	["Woman18", "Зрительница 18", "Spectator 18"],
	["Woman20", "Зрительница 20", "Spectator 20"],
	["Woman22", "Зрительница 22", "Spectator 22"],
]
const DEFAULT = "Man5"
const STRIP_TYPES = ["Area", "AudioStreamPlayer3D", "AudioStreamPlayer", "RayCast", "AnimationTree",
	"CollisionShape", "Tween", "Timer"]


static func count():
	return SKINS.size()


static func index_of(id):
	for i in range(SKINS.size()):
		if SKINS[i][0] == id:
			return i
	return 0


static func id_at(i):
	return SKINS[posmod(i, SKINS.size())][0]


static func title(id):
	var row = SKINS[index_of(id)]
	return row[1] if TranslationServer.get_locale().begins_with("ru") else row[2]


# Возвращает {"node": Spatial, "player": AnimationPlayer|null, "idle": String, "walk": String}
# или null, если префаб не загрузился. Модель развёрнута лицом к −Z, как игрок.
static func build(id):
	var packed = load("res://Prefabs/%s.tscn" % id)
	if packed == null:
		return null
	var root = packed.instance()
	_strip(root)
	if root is RigidBody:
		root.mode = RigidBody.MODE_KINEMATIC
		root.collision_layer = 0
		root.collision_mask = 0
	root.rotation.y = PI   # префабы смотрят в +Z
	var player = _find_anim_player(root)
	var idle = ""
	var walk = ""
	if player:
		for anim in player.get_animation_list():
			if walk == "" and "Walk" in anim:
				walk = anim
			if "Idle" in anim:
				idle = anim
		if idle == "":
			for anim in player.get_animation_list():
				# «Man38Stand» — стойка, а «…SitToStand» — вставание со стула, не подходит
				if anim.ends_with("Stand") and not anim.ends_with("ToStand"):
					idle = anim
	return {"node": root, "player": player, "idle": idle, "walk": walk}


# Поставить анимацию покоя; у кого её нет — замереть на первом кадре ходьбы.
static func play_idle(skin, blend = 0.25):
	var player = skin["player"]
	if player == null:
		return
	if skin["idle"] != "":
		if player.current_animation != skin["idle"]:
			player.play(skin["idle"], blend)
	elif skin["walk"] != "":
		if not player.is_playing() and player.assigned_animation == skin["walk"]:
			return   # уже замер на первом кадре
		player.play(skin["walk"])
		player.seek(0.0, true)
		player.stop(false)


static func play_walk(skin, blend = 0.25):
	var player = skin["player"]
	if player and skin["walk"] != "" and player.current_animation != skin["walk"]:
		player.play(skin["walk"], blend)


static func _strip(node):
	for child in node.get_children():
		if child.get_class() in STRIP_TYPES:
			node.remove_child(child)
			child.free()
		else:
			_strip(child)
	node.set_script(null)


static func _find_anim_player(node):
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null
