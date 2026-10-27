extends Node
# Кооп-мод для «Неясного»: Steam-лобби + P2P, второй игрок виден в мире, чат.
# Подключается без правки игры: override.cfg рядом с исполняемым файлом добавляет
# этот скрипт в автозагрузку (CoopMod="*user://mods/coop.gd").
#
# Сценарий: главное меню → «игра с друзьями» → персонаж → глава → лобби (пригласить друзей,
# готовность) → хост жмёт «начать», и все загружают выбранную главу.
# В игре: Enter — чат, F9 — пригласить (или создать лобби на текущем уровне), F10 — выйти.
#
# Состояние лобби хранится в данных Steam-лобби (видны всем участникам):
#   лобби:     neyasnoe_coop = VERSION, level = путь сцены, chapter = номер главы, started = "1"
#   участник:  skin, ready = "1"

signal lobby_changed
signal chat_event(author, text, is_system, color)
signal chat_cleared

const VERSION = 3
const APP_ID = 2435180
const MAX_MEMBERS = 4
const LOBBY_FRIENDS_ONLY = 1
const SEND_UNRELIABLE_NO_DELAY = 1
const CHANNEL = 0
const SEND_INTERVAL = 1.0 / 15.0
const POLL_INTERVAL = 0.5
const PLAYER_FEET_OFFSET = 0.9   # капсула игрока: radius 0.35 + height/2 0.55
const MAIN_MENU_SCENE = "res://Scenes/MainMenu.tscn"
const SETTINGS_PATH = "user://mods/coop.cfg"
const MENU_NODE = "CoopFriendsMenu"
const MENU_INJECT_DELAY_FRAMES = 10
const FRIEND_FLAG_IMMEDIATE = 4
const PERSONA_OFFLINE = 0

var Avatar = load("user://mods/coop_avatar.gd")
var Chat = load("user://mods/coop_chat.gd")
var Menu = load("user://mods/coop_menu.gd")
var Skins = load("user://mods/coop_skins.gd")
var UI = load("user://mods/coop_ui.gd")
var Car = load("user://mods/coop_car.gd")
var Toast = load("user://mods/coop_toast.gd")

var lobby_id = 0
var my_id = 0
var skin = ""
var me_ready = false
var loading_level = false  # change_scene уже запрошен
var avatars = {}          # steam_id → узел аватара
var send_timer = 0.0
var poll_timer = 0.0
var last_snapshot = ""    # чтобы слать lobby_changed только при изменениях
var pending_lobby = {}    # что записать в лобби, когда Steam его создаст
var chat
var car                   # своя машина: сесть, ехать, выйти
var toast                 # уведомления сверху по центру
var menu_scene_id = 0     # instance_id текущей сцены меню
var menu_frames = 0       # сколько кадров эта сцена меню уже живёт


func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	_load_settings()
	toast = Toast.new()
	toast.coop = self
	add_child(toast)
	car = Car.new()
	car.coop = self
	car.pause_mode = Node.PAUSE_MODE_STOP   # на паузе машина не едет
	add_child(car)   # машины работают и без Steam
	if not Engine.has_singleton("Steam"):
		push_warning("CoopMod: нет Steam — мод выключен")
		set_process_input(false)
		set_process(false)
		return
	my_id = Steam.getSteamID()
	Steam.allowP2PPacketRelay(true)
	Steam.connect("lobby_created", self, "_on_lobby_created")
	Steam.connect("lobby_joined", self, "_on_lobby_joined")
	Steam.connect("join_requested", self, "_on_join_requested")
	Steam.connect("join_game_requested", self, "_on_join_game_requested")
	Steam.connect("lobby_chat_update", self, "_on_lobby_chat_update")
	Steam.connect("lobby_message", self, "_on_lobby_message")
	Steam.connect("p2p_session_request", self, "_on_p2p_session_request")
	Steam.connect("p2p_session_connect_fail", self, "_on_p2p_fail")
	chat = Chat.new()
	chat.connect("submitted", self, "send_chat")
	add_child(chat)
	connect("lobby_changed", self, "_on_own_lobby_changed")
	print("CoopMod v%d: ready" % VERSION)
	call_deferred("_join_from_cmdline")


func _join_from_cmdline():
	var args = OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == "+connect_lobby":
			join(int(args[i + 1]))


# ── публичное API (для меню) ────────────────────────────────────────────────
func in_lobby():
	return lobby_id != 0


func max_members():
	return MAX_MEMBERS


func is_host():
	return lobby_id != 0 and Steam.getLobbyOwner(lobby_id) == my_id


func lobby_value(key):
	return Steam.getLobbyData(lobby_id, key) if lobby_id != 0 else ""


func is_started():
	return lobby_value("started") == "1"


# [{id, name, skin, ready, host, me}] — по порядку входа в лобби
func members():
	var out = []
	var owner = Steam.getLobbyOwner(lobby_id) if lobby_id != 0 else 0
	for id in _members():
		out.append({
			"id": id,
			"name": Steam.getFriendPersonaName(id),
			"skin": Steam.getLobbyMemberData(lobby_id, id, "skin"),
			"ready": Steam.getLobbyMemberData(lobby_id, id, "ready") == "1",
			"host": id == owner,
			"me": id == my_id,
			"color": color_of(id),
		})
	return out


# Цвет ника. Каждый хочет «свой» цвет по хешу Steam ID; при совпадении в лобби
# следующий свободный. Участники перебираются по возрастанию ID — у всех одинаково.
func color_of(id):
	var count = UI.PLAYER_COLORS.size()
	var ids = _members()
	ids.sort()
	var taken = {}
	for member in ids:
		var slot = _preferred_color(member)
		for i in count:
			if not taken.has(slot):
				break
			slot = (slot + 1) % count
		taken[slot] = true
		if member == id:
			return UI.PLAYER_COLORS[slot]
	return UI.PLAYER_COLORS[_preferred_color(id)]   # уже не в лобби


func _preferred_color(id):
	return abs(hash(str(id))) % UI.PLAYER_COLORS.size()


# Друзья для окна приглашений: сначала те, кто в «Неясном», потом в сети; офлайн — в конце.
func friends():
	var out = []
	for i in range(Steam.getFriendCount(FRIEND_FLAG_IMMEDIATE)):
		var id = Steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE)
		var game = Steam.getFriendGamePlayed(id)
		var in_game = typeof(game) == TYPE_DICTIONARY and int(game.get("id", 0)) == APP_ID
		out.append({
			"id": id,
			"name": Steam.getFriendPersonaName(id),
			"online": Steam.getFriendPersonaState(id) != PERSONA_OFFLINE,
			"in_game": in_game,
			"lobby": int(game.get("lobby", 0)) if in_game else 0,
		})
	out.sort_custom(self, "_friend_order")
	return out


func _friend_order(a, b):
	var ra = 0 if a["in_game"] else (1 if a["online"] else 2)
	var rb = 0 if b["in_game"] else (1 if b["online"] else 2)
	if ra != rb:
		return ra < rb
	return a["name"].to_lower() < b["name"].to_lower()


func create_lobby(level, chapter_n):
	if lobby_id != 0:
		leave()
	_clear_chat()
	pending_lobby = {"level": level, "chapter": str(chapter_n), "started": "0"}
	_system("Создаю лобби…")
	Steam.createLobby(LOBBY_FRIENDS_ONLY, MAX_MEMBERS)


func invite(friend_id):
	if lobby_id != 0:
		Steam.inviteUserToLobby(lobby_id, friend_id)


func open_steam_invites():
	if lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)


func join(id):
	if id == 0 or id == lobby_id:
		return
	if lobby_id != 0:
		leave()
	_clear_chat()
	_system("Подключаюсь к лобби…")
	Steam.joinLobby(id)


func leave():
	if lobby_id == 0:
		return
	for id in _members():
		if id != my_id:
			Steam.closeP2PSessionWithUser(id)
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	me_ready = false
	last_snapshot = ""
	for id in avatars.keys():
		_remove_avatar(id)
	_system("Вы вышли из лобби")
	emit_signal("lobby_changed")


func set_skin(id):
	skin = Skins.id_at(Skins.index_of(id))
	var cfg = ConfigFile.new()
	cfg.set_value("coop", "skin", skin)
	cfg.save(SETTINGS_PATH)
	if lobby_id != 0:
		Steam.setLobbyMemberData(lobby_id, "skin", skin)


func set_ready(value):
	me_ready = value
	if lobby_id != 0:
		Steam.setLobbyMemberData(lobby_id, "ready", "1" if value else "0")


# Хост начинает: отметка в лобби, все участники подхватят её при опросе и загрузят главу.
func start_game():
	if not is_host():
		return
	Steam.setLobbyData(lobby_id, "started", "1")
	Steam.setLobbyJoinable(lobby_id, true)   # опоздавшие тоже смогут зайти
	_load_level(lobby_value("level"))


func send_chat(text):
	if lobby_id == 0:
		_system("Вы не в лобби — позовите друга: F9 или «игра с друзьями» в меню")
		return
	Steam.sendLobbyChatMsg(lobby_id, text)


func _load_settings():
	var cfg = ConfigFile.new()
	skin = Skins.DEFAULT
	if cfg.load(SETTINGS_PATH) == OK:
		skin = Skins.id_at(Skins.index_of(cfg.get_value("coop", "skin", Skins.DEFAULT)))


# Новое лобби — чистая лента: переписка прошлого лобби к нему не относится.
func _clear_chat():
	chat.clear()
	emit_signal("chat_cleared")


func _system(text):
	chat.system(text)
	emit_signal("chat_event", "", text, true, null)


# ── клавиши ─────────────────────────────────────────────────────────────────
func _input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _in_main_menu():
		return   # в меню всё делается через экран «игра с друзьями»
	if event.scancode == KEY_F9:
		if lobby_id != 0:
			open_steam_invites()
			notify("приглашение друзей")
		else:
			notify("создаю лобби…")
			var scene = get_tree().current_scene
			var n = scene.filename.get_file().get_basename().replace("Level", "")
			create_lobby(scene.filename, n if n.is_valid_integer() else "")
			pending_lobby["started"] = "1"   # мы уже на уровне: друзья сразу загрузят его
	elif event.scancode == KEY_F10:
		if lobby_id != 0:
			notify("вы вышли из лобби")
		leave()
	elif event.scancode == KEY_ENTER or event.scancode == KEY_KP_ENTER:
		if not chat.is_open():
			chat.open()
			get_tree().set_input_as_handled()


func notify(text):
	if toast:
		toast.show_text(text)


# ── сигналы Steam ───────────────────────────────────────────────────────────
func _on_lobby_created(result, id):
	if result != 1:
		_system("Не удалось создать лобби (код %d)" % result)
		return
	lobby_id = id
	Steam.setLobbyData(id, "neyasnoe_coop", str(VERSION))
	for key in pending_lobby:
		Steam.setLobbyData(id, key, pending_lobby[key])
	pending_lobby = {}
	Steam.setLobbyJoinable(id, true)
	Steam.setLobbyMemberData(id, "skin", skin)
	set_ready(true)   # хост всегда готов
	_system("Лобби создано")
	if not _in_main_menu():
		open_steam_invites()
	emit_signal("lobby_changed")


func _on_lobby_joined(id, _permissions, _locked, response):
	if response != 1:
		_system("Не удалось войти в лобби (код %d)" % response)
		return
	lobby_id = id
	Steam.setLobbyMemberData(id, "skin", skin)
	set_ready(false)
	var names = []
	for m in members():
		names.append(m["name"])
	_system("В лобби: " + PoolStringArray(names).join(", "))
	emit_signal("lobby_changed")
	_follow_host()


# GodotSteam объявляет (from, connect_string), но шлёт (lobby_id, friend_id) —
# разбираем оба варианта по виду Steam ID (лобби: 0x018…, пользователь: 0x011…).
func _on_join_requested(a, b):
	for v in [a, b]:
		if typeof(v) == TYPE_INT and (v >> 52) == 0x018:
			join(v)
			return
		if typeof(v) == TYPE_STRING and "+connect_lobby" in v:
			join(int(v.split(" ")[-1]))
			return


func _on_join_game_requested(_user, connect):
	if "+connect_lobby" in connect:
		join(int(connect.split(" ")[-1]))


func _on_lobby_chat_update(id, changed_id, _making_change_id, chat_state):
	if id != lobby_id or changed_id == my_id:
		return
	var who = Steam.getFriendPersonaName(changed_id)
	if chat_state == 1:
		_system(who + " присоединился")
	else:
		_system(who + " вышел")
		_remove_avatar(changed_id)
	emit_signal("lobby_changed")


func _on_lobby_message(id, user, message, _chat_type):
	if id == lobby_id:
		var author = Steam.getFriendPersonaName(user)
		var color = color_of(user)
		chat.message(author, message, color)
		emit_signal("chat_event", author, message, false, color)


func _on_p2p_session_request(remote_id):
	if remote_id in _members():
		Steam.acceptP2PSessionWithUser(remote_id)


func _on_p2p_fail(remote_id, err):
	push_warning("CoopMod: P2P с %s не удалось (%d)" % [str(remote_id), err])


# ── кадр: меню, опрос лобби, синхронизация ──────────────────────────────────
func _process(delta):
	_inject_menu()
	chat.set_hidden(_in_main_menu())   # в меню чат живёт на экране лобби
	if lobby_id == 0:
		return
	poll_timer += delta
	if poll_timer >= POLL_INTERVAL:
		poll_timer = 0.0
		_poll_lobby()
	_receive()
	send_timer += delta
	if send_timer >= SEND_INTERVAL:
		send_timer = 0.0
		_send_state()


# Данные лобби меняются у других участников — опрашиваем и сообщаем меню об изменениях.
func _poll_lobby():
	var snapshot = str(members()) + lobby_value("started") + lobby_value("level")
	if snapshot != last_snapshot:
		last_snapshot = snapshot
		emit_signal("lobby_changed")
	_follow_host()


# Хост начал игру — участник из меню загружает ту же главу.
func _follow_host():
	if is_host() or not is_started():
		return
	var level = lobby_value("level")
	if level != "" and _in_main_menu():
		_load_level(level)


func _load_level(level):
	if loading_level or level == "" or not level.begins_with("res://Scenes/"):
		return   # путь приходит из данных лобби — только сцены игры
	var scene = get_tree().current_scene
	if scene and scene.filename == level:
		return
	loading_level = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var loading = scene.get_node_or_null("MainMenuHUD/LoadingScreen") if scene else null
	if loading:
		loading.show()
	for _i in range(5):
		yield(get_tree(), "idle_frame")
	get_tree().paused = false
	get_tree().change_scene(level)
	loading_level = false


func _in_main_menu():
	var scene = get_tree().current_scene
	return scene != null and scene.filename == MAIN_MENU_SCENE


# Экран «игра с друзьями» добавляется в каждый новый экземпляр главного меню.
# Пока сцена меню собирается, add_child в неё падает («Parent node is busy»), поэтому
# ждём несколько кадров и проверяем по имени, что меню действительно на месте.
func _inject_menu():
	if not _in_main_menu():
		menu_frames = 0
		return
	var scene = get_tree().current_scene
	if scene.get_instance_id() != menu_scene_id:
		menu_scene_id = scene.get_instance_id()
		menu_frames = 0
	menu_frames += 1
	if menu_frames < MENU_INJECT_DELAY_FRAMES or menu_frames % MENU_INJECT_DELAY_FRAMES != 0:
		return
	var hud = scene.get_node_or_null("MainMenuHUD")
	if hud == null or hud.has_node(MENU_NODE):
		return
	var menu = Menu.new()
	menu.name = MENU_NODE
	menu.coop = self
	hud.add_child(menu)


func _send_state():
	var player = _local_player()
	if player == null or _in_main_menu():
		return
	var state = {
		"v": VERSION,
		"sc": get_tree().current_scene.filename,
		"p": player.global_transform.origin - Vector3(0, PLAYER_FEET_OFFSET, 0),
		"y": player.global_transform.basis.get_euler().y,
		"s": player.linear_velocity.length(),
		"k": skin,
		"d": car.driving(),       # за рулём: у друзей вместо жителя — машина
		"c": car.net_cars(),      # наши машины: поставленные по F1 и те, в которых ездили
	}
	var bytes = var2bytes(state)
	for id in _members():
		if id != my_id:
			Steam.sendP2PPacket(id, bytes, SEND_UNRELIABLE_NO_DELAY, CHANNEL)


func _receive():
	var size = Steam.getAvailableP2PPacketSize(CHANNEL)
	while size > 0:
		var packet = Steam.readP2PPacket(size, CHANNEL)
		size = Steam.getAvailableP2PPacketSize(CHANNEL)
		if packet.empty():
			continue
		var state = bytes2var(packet["data"])
		if typeof(state) != TYPE_DICTIONARY or state.get("v") != VERSION:
			continue
		_apply_state(packet["steam_id_remote"], state)


func _apply_state(id, state):
	var scene = get_tree().current_scene
	if scene == null or state.get("sc") != scene.filename or _in_main_menu():
		_remove_avatar(id)   # друг на другом уровне (или мы в меню)
		return
	var avatar = avatars.get(id)
	if avatar == null or not is_instance_valid(avatar):
		avatar = Avatar.new()
		avatar.name = "CoopRemote_%s" % str(id)   # не «Player»: игра ищет find_node("Player")
		avatar.display_name = Steam.getFriendPersonaName(id)
		avatar.name_color = color_of(id)
		scene.add_child(avatar)
		avatars[id] = avatar
	avatar.push_state(state["p"], state["y"], state.get("s", 0.0), state.get("k", Skins.DEFAULT),
		state.get("d") == true)
	avatar.push_cars(state.get("c", []), car)


# Состав лобби изменился: список онлайн слева сверху и цвета имён над головами.
func _on_own_lobby_changed():
	var roster = []
	for m in members():
		roster.append({"name": m["name"], "color": m["color"]})
	chat.set_roster(roster)
	for id in avatars:
		if is_instance_valid(avatars[id]):
			avatars[id].set_name_color(color_of(id))


func _remove_avatar(id):
	var avatar = avatars.get(id)
	if avatar != null and is_instance_valid(avatar):
		avatar.queue_free()
	avatars.erase(id)


# ── помощники ───────────────────────────────────────────────────────────────
func _members():
	var out = []
	if lobby_id == 0:
		return out
	for i in range(Steam.getNumLobbyMembers(lobby_id)):
		out.append(Steam.getLobbyMemberByIndex(lobby_id, i))
	return out


func _local_player():
	var scene = get_tree().current_scene
	if scene == null:
		return null
	var player = scene.find_node("Player", true, false)
	if player is RigidBody:
		return player
	return null
