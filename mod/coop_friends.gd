extends Control
# Окно «пригласить друзей»: список друзей Steam прямо в игре. Сначала те, кто сейчас
# в «Неясном», потом остальные в сети; не в сети — по кнопке. Приглашение уходит
# через Steam (inviteUserToLobby) и приходит другу уведомлением.

signal closed

var UI = load("user://mods/coop_ui.gd")

const RECT = Rect2(220, 70, 520, 400)
const ROW_H = 30
const REFRESH_SECONDS = 3.0

const TEXT = {
	"title": ["пригласить друзей", "invite friends"],
	"in_game": ["в «Неясном»", "in Neyasnoe"],
	"online": ["в сети", "online"],
	"offline": ["не в сети", "offline"],
	"invite": ["пригласить", "invite"],
	"sent": ["отправлено", "sent"],
	"in_lobby": ["уже в лобби", "in lobby"],
	"show_offline": ["показать не в сети", "show offline"],
	"hide_offline": ["скрыть не в сети", "hide offline"],
	"steam": ["открыть Steam", "open Steam"],
	"close": ["закрыть", "close"],
	"empty": ["Никого из друзей нет в сети.", "No friends online."],
}

var coop
var list
var show_offline = false
var sent = {}             # friend_id → true, чтобы кнопка помнила «отправлено»
var refresh_timer = 0.0
var offline_button
var close_button
var steam_button
var italic


func _t(key):
	return TEXT[key][0] if TranslationServer.get_locale().begins_with("ru") else TEXT[key][1]


func _ready():
	set_anchors_preset(Control.PRESET_WIDE)
	italic = UI.font(UI.ITALIC, 15)
	var dim = UI.dim()
	dim.color = Color(0, 0, 0, 0.8)   # лобби за окном не должно просвечивать
	add_child(dim)
	add_child(UI.panel(RECT, 0.97))
	var x = RECT.position.x + 20
	add_child(UI.label(_t("title"), Vector2(x, RECT.position.y + 14), Vector2(300, 25)))

	var scroll = ScrollContainer.new()
	scroll.rect_position = Vector2(x, RECT.position.y + 52)
	scroll.rect_size = Vector2(RECT.size.x - 40, RECT.size.y - 110)
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)
	list = VBoxContainer.new()
	list.rect_min_size = Vector2(RECT.size.x - 52, 0)
	scroll.add_child(list)

	var bottom = RECT.end.y - 42
	offline_button = UI.button(_t("show_offline"), Vector2(x, bottom), 190)
	offline_button.connect("pressed", self, "_toggle_offline")
	add_child(offline_button)
	steam_button = UI.button(_t("steam"), Vector2(x + 200, bottom), 150)
	steam_button.connect("pressed", coop, "open_steam_invites")
	add_child(steam_button)
	close_button = UI.button(_t("close"), Vector2(RECT.end.x - 100, bottom), 80)
	close_button.connect("pressed", self, "close")
	add_child(close_button)
	_rebuild()
	close_button.grab_focus()


func close():
	emit_signal("closed")
	queue_free()


func _toggle_offline():
	show_offline = not show_offline
	offline_button.text = _t("hide_offline") if show_offline else _t("show_offline")
	_rebuild()


func _process(delta):
	refresh_timer += delta
	if refresh_timer >= REFRESH_SECONDS:
		refresh_timer = 0.0
		_rebuild()


func _rebuild():
	for child in list.get_children():
		child.queue_free()
	var in_lobby = {}
	for m in coop.members():
		in_lobby[m["id"]] = true
	var shown = 0
	for f in coop.friends():
		if not f["online"] and not show_offline:
			continue
		list.add_child(_row(f, in_lobby.has(f["id"])))
		shown += 1
	if shown == 0:
		list.add_child(UI.label(_t("empty"), Vector2(), Vector2(RECT.size.x - 60, ROW_H), 0.6, italic))


func _row(f, already_in_lobby):
	var row = Control.new()
	row.rect_min_size = Vector2(RECT.size.x - 60, ROW_H)
	var name = UI.label(f["name"], Vector2(0, 2), Vector2(220, ROW_H), 1.0 if f["online"] else 0.45)
	name.autowrap = false
	name.clip_text = true
	row.add_child(name)
	var status = _t("in_game") if f["in_game"] else (_t("online") if f["online"] else _t("offline"))
	var status_label = UI.label(status, Vector2(228, 8), Vector2(120, ROW_H), 0.55, italic)
	if f["in_game"]:
		status_label.add_color_override("font_color", UI.ACCENT)
		status_label.modulate.a = 1.0
	row.add_child(status_label)
	var b = UI.button("", Vector2(350, 2), 110)
	if already_in_lobby:
		b.text = _t("in_lobby")
		b.disabled = true
	elif sent.has(f["id"]):
		b.text = _t("sent")
		b.disabled = true
	else:
		b.text = _t("invite")
		b.connect("pressed", self, "_invite", [f["id"], b])
	row.add_child(b)
	return row


func _invite(friend_id, b):
	coop.invite(friend_id)
	sent[friend_id] = true
	b.text = _t("sent")
	b.disabled = true


func _input(event):
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back"):
		close()
		get_tree().set_input_as_handled()
