extends Control
# «Игра с друзьями» в главном меню — пошагово, как в кооперативных играх:
#   выбор: создать игру / присоединиться к другу
#   создать: 1) персонаж → 2) глава → 3) лобби (игроки, готовность, приглашения, чат) → начать
#   присоединиться: друзья, у которых сейчас открыто лобби в «Неясном»
# Добавляется модом в MainMenuHUD и наследует тему меню (Theme1, Old Standard).

var UI = load("user://mods/coop_ui.gd")
var Skins = load("user://mods/coop_skins.gd")
var Friends = load("user://mods/coop_friends.gd")

enum Page { HUB, CHARACTER, CHAPTER, LOBBY, JOIN }

const X = 49                       # колонка кнопок меню игры
const TOP = 210                    # первая кнопка меню игры
const ROW = 35                     # шаг кнопок меню игры
const INSERT_Y = 315               # пункт меню после «обучения»; ниже стоящие сдвигаются
const SHIFTED = ["SettingsButton", "CreditsButton", "QuitButton"]
const PREVIEW_RECT = Rect2(600, 70, 300, 420)
const PREVIEW_SPIN = 0.5           # рад/с
const ARROW_GAP = 10               # от имени скина до стрелок «<» «>»
const CARDS_RECT = Rect2(430, 120, 480, 186)
const CHAT_RECT = Rect2(430, 316, 480, 150)
const CARD_H = 40
const CHAT_LINES = 6
const JOIN_REFRESH_SECONDS = 2.0
const LEVEL_PATH = "res://Scenes/Level%d.tscn"

const TEXT = {
	"friends": ["игра с друзьями", "play with friends"],
	"create_game": ["создать игру", "host a game"],
	"join_friend": ["присоединиться к другу", "join a friend"],
	"back_to_lobby": ["вернуться в лобби", "back to lobby"],
	"back": ["назад", "back"],
	"next": ["далее", "next"],
	"done": ["готово", "done"],
	"create_lobby": ["создать лобби", "create lobby"],
	"start": ["начать игру", "start game"],
	"ready": ["я готов", "ready"],
	"not_ready": ["не готов", "not ready"],
	"invite": ["пригласить друзей", "invite friends"],
	"character": ["персонаж", "character"],
	"leave": ["покинуть лобби", "leave lobby"],
	"refresh": ["обновить", "refresh"],
	"step_character": ["создать игру · шаг 1 из 3 · персонаж", "host · step 1 of 3 · character"],
	"step_chapter": ["создать игру · шаг 2 из 3 · глава", "host · step 2 of 3 · chapter"],
	"step_lobby": ["лобби · %s", "lobby · %s"],
	"edit_character": ["персонаж", "character"],
	"join_title": ["присоединиться к другу", "join a friend"],
	"hub_hint": ["Создайте игру и пригласите друзей из Steam — или зайдите в лобби друга.",
		"Host a game and invite Steam friends, or join a friend's lobby."],
	"skin_of": ["%d из %d", "%d of %d"],
	"players": ["игроки %d/%d", "players %d/%d"],
	"free_slot": ["свободное место", "free slot"],
	"host": ["хост", "host"],
	"is_ready": ["готов", "ready"],
	"waiting": ["не готов", "not ready"],
	"you": ["вы", "you"],
	"wait_ready": ["Ждём готовности: %s", "Waiting for: %s"],
	"all_ready": ["Все готовы — можно начинать.", "Everyone is ready — start when you like."],
	"alone": ["Пригласите друзей — или начните одни, они смогут зайти позже.",
		"Invite friends — or start alone, they can join later."],
	"wait_host": ["Ждём, когда хост начнёт игру.", "Waiting for the host to start."],
	"started": ["Игра уже идёт — загружаем главу…", "Game in progress — loading chapter…"],
	"creating": ["Создаём лобби…", "Creating lobby…"],
	"no_lobbies": ["Сейчас никто из друзей не собирает лобби. Попросите друга пригласить вас — приглашение придёт в Steam.",
		"No friends are hosting right now. Ask a friend to invite you — it arrives in Steam."],
	"lobby_of": ["лобби %s", "%s's lobby"],
	"message": ["сообщение…", "message…"],
}

var coop
var hud
var open_button
var screen
var page = Page.HUB
var character_return = Page.CHAPTER   # куда «далее/готово» со страницы персонажа
var chapter = 1
var friends_window
var join_timer = 0.0
var join_signature = ""
var chat_lines = []

var small
var italic
var caption
var pages = {}            # Page → Control
var preview_box
var preview_pivot
var preview_skin

# элементы, которые обновляются
var hub_buttons = []
var skin_label
var skin_count
var char_buttons = []
var chapter_box
var chapter_buttons = []
var lobby_buttons = {}
var cards
var lobby_status
var chat_log
var chat_input
var join_list
var join_buttons = []


func _t(key):
	return TEXT[key][0] if TranslationServer.get_locale().begins_with("ru") else TEXT[key][1]


func _ready():
	hud = get_parent()
	set_anchors_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	small = UI.font(UI.REGULAR, 15)
	italic = UI.font(UI.ITALIC, 15)
	_build_open_button()
	_build_screen()
	coop.connect("lobby_changed", self, "_on_lobby_changed")
	coop.connect("chat_event", self, "_on_chat_event")
	if coop.in_lobby():
		call_deferred("_open_screen")


# ── пункт в главном меню ────────────────────────────────────────────────────
func _build_open_button():
	for name in SHIFTED:
		var b = hud.get_node_or_null(name)
		if b:
			b.rect_position.y += ROW
	open_button = UI.button(_t("friends"), Vector2(X, INSERT_Y))
	open_button.connect("pressed", self, "_open_screen")
	add_child(open_button)
	var above = hud.get_node_or_null("TutorialButton")
	var below = hud.get_node_or_null("SettingsButton")
	if above:
		above.focus_neighbour_bottom = above.get_path_to(open_button)
		above.focus_next = above.get_path_to(open_button)
		open_button.focus_neighbour_top = open_button.get_path_to(above)
		open_button.focus_previous = open_button.get_path_to(above)
	if below:
		below.focus_neighbour_top = below.get_path_to(open_button)
		below.focus_previous = below.get_path_to(open_button)
		open_button.focus_neighbour_bottom = open_button.get_path_to(below)
		open_button.focus_next = open_button.get_path_to(below)


# ── каркас экрана ───────────────────────────────────────────────────────────
func _build_screen():
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_WIDE)
	screen.visible = false
	add_child(screen)
	screen.add_child(UI.dim())
	caption = UI.label("", Vector2(X, TOP - 40), Vector2(520, 25), 0.6, italic)
	caption.autowrap = false
	screen.add_child(caption)
	_build_preview()
	pages[Page.HUB] = _build_hub()
	pages[Page.CHARACTER] = _build_character()
	pages[Page.CHAPTER] = _build_chapter()
	pages[Page.LOBBY] = _build_lobby()
	pages[Page.JOIN] = _build_join()
	for p in pages.values():
		screen.add_child(p)


func _page_root():
	var c = Control.new()
	c.set_anchors_preset(Control.PRESET_WIDE)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	return c


func _add_button(parent, key, y, method, args = []):
	var b = UI.button(_t(key), Vector2(X, y))
	b.connect("pressed", self, method, args)
	parent.add_child(b)
	return b


func _build_hub():
	var p = _page_root()
	hub_buttons = [
		_add_button(p, "create_game", TOP, "_on_create_game"),
		_add_button(p, "join_friend", TOP + ROW, "_go", [Page.JOIN]),
		_add_button(p, "back", TOP + ROW * 2, "_close_screen"),
	]
	p.add_child(UI.label(_t("hub_hint"), Vector2(X, TOP + ROW * 3 + 20), Vector2(380, 60), 0.6, italic))
	UI.chain_focus(hub_buttons)
	return p


func _build_character():
	var p = _page_root()
	var prev = UI.button("<", Vector2(X, TOP), 24)
	prev.connect("pressed", self, "_change_skin", [-1])
	p.add_child(prev)
	skin_label = UI.label("", Vector2(X + 28, TOP), Vector2(280, UI.BUTTON_H))
	skin_label.align = Label.ALIGN_CENTER
	skin_label.autowrap = false
	p.add_child(skin_label)
	var next = UI.button(">", Vector2(X + 312, TOP), 24)
	next.connect("pressed", self, "_change_skin", [1])
	p.add_child(next)
	skin_count = UI.label("", Vector2(X + 28, TOP + 26), Vector2(280, 20), 0.5, small)
	skin_count.align = Label.ALIGN_CENTER
	p.add_child(skin_count)
	var ok = _add_button(p, "next", TOP + ROW * 2, "_on_character_done")
	var back = _add_button(p, "back", TOP + ROW * 3, "_on_character_back")
	char_buttons = [prev, next, ok, back]
	UI.chain_focus([prev, ok, back])
	prev.focus_neighbour_right = prev.get_path_to(next)
	next.focus_neighbour_left = next.get_path_to(prev)
	return p


func _build_chapter():
	var p = _page_root()
	chapter_box = Control.new()
	chapter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(chapter_box)
	return p


func _build_lobby():
	var p = _page_root()
	lobby_buttons["main"] = _add_button(p, "start", TOP, "_on_lobby_main")
	lobby_buttons["invite"] = _add_button(p, "invite", TOP + ROW, "_open_friends")
	lobby_buttons["character"] = _add_button(p, "character", TOP + ROW * 2, "_on_edit_character")
	lobby_buttons["leave"] = _add_button(p, "leave", TOP + ROW * 3, "_on_leave")
	lobby_status = UI.label("", Vector2(X, TOP + ROW * 4 + 16), Vector2(340, 70), 0.65, italic)
	p.add_child(lobby_status)

	p.add_child(UI.panel(CARDS_RECT))
	cards = VBoxContainer.new()
	cards.rect_position = CARDS_RECT.position + Vector2(12, 8)
	cards.rect_size = CARDS_RECT.size - Vector2(24, 16)
	cards.add_constant_override("separation", 2)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cards)

	p.add_child(UI.panel(CHAT_RECT))
	chat_log = VBoxContainer.new()
	chat_log.rect_position = CHAT_RECT.position + Vector2(12, 8)
	chat_log.rect_size = Vector2(CHAT_RECT.size.x - 24, CHAT_RECT.size.y - 46)
	chat_log.alignment = BoxContainer.ALIGN_END
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.rect_position = Vector2(CHAT_RECT.position.x + 10, CHAT_RECT.end.y - 34)
	chat_input.rect_size = Vector2(CHAT_RECT.size.x - 20, 26)
	chat_input.placeholder_text = _t("message")
	chat_input.max_length = 200
	chat_input.add_font_override("font", small)
	var input_style = UI.panel_style(0.3)
	for side in [MARGIN_LEFT, MARGIN_TOP, MARGIN_RIGHT, MARGIN_BOTTOM]:
		input_style.set_default_margin(side, 5)
	chat_input.add_stylebox_override("normal", input_style)
	chat_input.add_stylebox_override("focus", input_style)
	chat_input.connect("text_entered", self, "_on_chat_entered")
	p.add_child(chat_input)
	return p


func _build_join():
	var p = _page_root()
	join_list = Control.new()
	join_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(join_list)
	return p


func _build_preview():
	preview_box = ViewportContainer.new()
	preview_box.stretch = true
	preview_box.rect_position = PREVIEW_RECT.position
	preview_box.rect_size = PREVIEW_RECT.size
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.visible = false
	screen.add_child(preview_box)

	var vp = Viewport.new()
	vp.size = PREVIEW_RECT.size
	vp.own_world = true
	vp.transparent_bg = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	preview_box.add_child(vp)

	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-35, 35, 0)
	light.light_energy = 1.1
	vp.add_child(light)

	var cam = Camera.new()
	cam.fov = 32
	cam.translation = Vector3(0, 1.0, 4.2)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.current = true
	vp.add_child(cam)

	preview_pivot = Spatial.new()
	vp.add_child(preview_pivot)


# ── навигация ───────────────────────────────────────────────────────────────
func _open_screen():
	hud.show_main_menu_buttons(false)
	screen.visible = true
	_go(Page.LOBBY if coop.in_lobby() else Page.HUB)


func _close_screen():
	_close_friends()
	screen.visible = false
	_clear_preview()
	hud.show_main_menu_buttons(true)
	open_button.grab_focus()


func _go(to):
	page = to
	for key in pages:
		pages[key].visible = key == to
	preview_box.visible = to == Page.CHARACTER
	match to:
		Page.HUB:
			caption.text = _t("friends")
			hub_buttons[0].text = _t("back_to_lobby") if coop.in_lobby() else _t("create_game")
			hub_buttons[0].grab_focus()
		Page.CHARACTER:
			caption.text = _t("edit_character") if character_return == Page.LOBBY else _t("step_character")
			char_buttons[2].text = _t("done") if character_return == Page.LOBBY else _t("next")
			_show_preview(coop.skin)
			_refresh_skin()
			char_buttons[2].grab_focus()
		Page.CHAPTER:
			caption.text = _t("step_chapter")
			_fill_chapters()
		Page.LOBBY:
			_refresh_lobby()
			lobby_buttons["main"].grab_focus()
		Page.JOIN:
			caption.text = _t("join_title")
			_fill_join()
	if to != Page.CHARACTER:
		_clear_preview()


# Esc / «назад» геймпада — шаг назад, как кнопка «назад» на странице.
func _go_back():
	if friends_window:
		_close_friends()
		return
	match page:
		Page.HUB:
			_close_screen()
		Page.CHARACTER:
			_on_character_back()
		Page.CHAPTER:
			_go(Page.CHARACTER)
		Page.LOBBY:
			_close_screen()   # лобби остаётся; в него можно вернуться из меню
		Page.JOIN:
			_go(Page.HUB)


func _input(event):
	if not screen.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back"):
		if chat_input.has_focus():
			chat_input.release_focus()
			lobby_buttons["main"].grab_focus()
		else:
			_go_back()
		get_tree().set_input_as_handled()


# ── хаб ─────────────────────────────────────────────────────────────────────
func _on_create_game():
	if coop.in_lobby():
		_go(Page.LOBBY)
		return
	character_return = Page.CHAPTER
	_go(Page.CHARACTER)


# ── персонаж ────────────────────────────────────────────────────────────────
func _change_skin(step):
	coop.set_skin(Skins.id_at(Skins.index_of(coop.skin) + step))
	_show_preview(coop.skin)
	_refresh_skin()


func _refresh_skin():
	skin_label.text = Skins.title(coop.skin)
	skin_count.text = _t("skin_of") % [Skins.index_of(coop.skin) + 1, Skins.count()]
	# стрелки прижимаются к имени, а не стоят по краям колонки
	var half = skin_label.get_font("font").get_string_size(skin_label.text).x / 2
	var center = skin_label.rect_position.x + skin_label.rect_size.x / 2
	char_buttons[0].rect_position.x = max(X, center - half - ARROW_GAP - char_buttons[0].rect_size.x)
	char_buttons[1].rect_position.x = center + half + ARROW_GAP


func _on_character_done():
	_go(character_return)


func _on_character_back():
	_go(Page.LOBBY if character_return == Page.LOBBY else Page.HUB)


func _show_preview(id):
	_clear_preview()
	preview_skin = Skins.build(id)
	if preview_skin == null:
		return
	preview_pivot.add_child(preview_skin["node"])
	preview_pivot.rotation.y = PI   # лицом к камере
	Skins.play_idle(preview_skin, 0.0)


func _clear_preview():
	if preview_skin:
		preview_skin["node"].queue_free()
		preview_skin = null


# ── глава ───────────────────────────────────────────────────────────────────
# Главы, открытые у этого игрока (хост выбирает только из пройденного).
func _chapters():
	var out = []
	var opened = max(1, int(PlayerVariables.chapter_opened))
	for c in _chapters_all():
		if c["n"] <= opened:
			out.append(c)
	return out


func _chapters_all():
	var out = []
	for n in range(1, 6):
		var b = hud.get_node_or_null("ChooseChapterScreen/Chapter%dButton" % n)
		if b:
			out.append({"n": n, "title": tr(b.text), "level": LEVEL_PATH % n})
	return out


func _fill_chapters():
	for c in chapter_box.get_children():
		c.queue_free()
	chapter_buttons = []
	var list = _chapters()
	if chapter > list.size():
		chapter = 1
	var y = TOP
	for c in list:
		var b = UI.button(c["title"], Vector2(X, y), 340)
		if c["n"] == chapter:   # выбранная глава — голубым, как нажатая кнопка меню
			b.add_color_override("font_color", UI.ACCENT)
			b.add_color_override("font_color_hover", UI.ACCENT)
			b.add_color_override("font_color_focus", UI.ACCENT)
		b.connect("pressed", self, "_select_chapter", [c["n"]])
		chapter_box.add_child(b)
		chapter_buttons.append(b)
		y += ROW
	y += 15
	var create = UI.button(_t("create_lobby"), Vector2(X, y))
	create.connect("pressed", self, "_on_create_lobby")
	chapter_box.add_child(create)
	var back = UI.button(_t("back"), Vector2(X, y + ROW))
	back.connect("pressed", self, "_go", [Page.CHARACTER])
	chapter_box.add_child(back)
	UI.chain_focus(chapter_buttons + [create, back])
	create.grab_focus()


func _select_chapter(n):
	chapter = n
	_fill_chapters()
	chapter_buttons[n - 1].grab_focus()


func _on_create_lobby():
	for c in _chapters():
		if c["n"] == chapter:
			coop.create_lobby(c["level"], c["n"])
	_go(Page.LOBBY)


# ── лобби ───────────────────────────────────────────────────────────────────
func _on_lobby_changed():
	if not screen.visible:
		if coop.in_lobby() and hud.get_node("NewGameButton").visible:
			_open_screen()   # приняли приглашение, стоя в главном меню
		return
	if page == Page.LOBBY:
		if coop.in_lobby():
			_refresh_lobby()
		else:
			_go(Page.HUB)
	elif page == Page.HUB:
		_go(Page.HUB)


func _refresh_lobby():
	# в данных лобби — номер главы (Steam плохо хранит кириллицу), название берём из меню игры
	var chapter_title = "…"
	for c in _chapters_all():
		if str(c["n"]) == coop.lobby_value("chapter"):
			chapter_title = c["title"]
	caption.text = _t("step_lobby") % chapter_title
	var host = coop.is_host()
	var main = lobby_buttons["main"]
	main.text = _t("start") if host else (_t("not_ready") if coop.me_ready else _t("ready"))
	main.disabled = not coop.in_lobby()
	lobby_buttons["invite"].disabled = not coop.in_lobby()
	UI.chain_focus([main, lobby_buttons["invite"], lobby_buttons["character"], lobby_buttons["leave"], chat_input])

	var members = coop.members()
	for c in cards.get_children():
		c.queue_free()
	cards.add_child(UI.label(_t("players") % [members.size(), coop.max_members()], Vector2(), Vector2(400, 22), 0.55, small))
	for m in members:
		cards.add_child(_card(m))
	for _i in range(coop.max_members() - members.size()):
		var free = UI.label(_t("free_slot"), Vector2(), Vector2(400, CARD_H - 8), 0.3, italic)
		cards.add_child(free)

	if not coop.in_lobby():
		lobby_status.text = _t("creating")
	elif coop.is_started() and not host:
		lobby_status.text = _t("started")
	elif host:
		var waiting = []
		for m in members:
			if not m["ready"] and not m["host"]:
				waiting.append(m["name"])
		if members.size() <= 1:
			lobby_status.text = _t("alone")
		elif waiting.empty():
			lobby_status.text = _t("all_ready")
		else:
			lobby_status.text = _t("wait_ready") % PoolStringArray(waiting).join(", ")
	else:
		lobby_status.text = _t("wait_host")


func _card(m):
	var row = Control.new()
	row.rect_min_size = Vector2(CARDS_RECT.size.x - 24, CARD_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name = m["name"] + ("  (" + _t("you") + ")" if m["me"] else "")
	var n = UI.label(name, Vector2(0, 0), Vector2(300, 22))
	n.autowrap = false
	n.clip_text = true
	row.add_child(n)
	var skin_title = Skins.title(m["skin"]) if m["skin"] != "" else "…"
	row.add_child(UI.label(skin_title, Vector2(0, 21), Vector2(300, 18), 0.55, italic))
	var state = _t("host") if m["host"] else (_t("is_ready") if m["ready"] else _t("waiting"))
	var s = UI.label(state, Vector2(330, 4), Vector2(120, 22), 1.0, italic)
	s.align = Label.ALIGN_RIGHT
	if m["host"] or m["ready"]:
		s.add_color_override("font_color", UI.ACCENT)
	else:
		s.modulate.a = 0.45
	row.add_child(s)
	return row


func _on_lobby_main():
	if coop.is_host():
		coop.start_game()
	else:
		coop.set_ready(not coop.me_ready)
		_refresh_lobby()


func _on_edit_character():
	character_return = Page.LOBBY
	_go(Page.CHARACTER)


func _on_leave():
	coop.leave()
	_go(Page.HUB)


func _open_friends():
	if friends_window or not coop.in_lobby():
		return
	friends_window = Friends.new()
	friends_window.coop = coop
	friends_window.connect("closed", self, "_on_friends_closed")
	screen.add_child(friends_window)


func _close_friends():
	if friends_window:
		friends_window.close()


func _on_friends_closed():
	friends_window = null
	if page == Page.LOBBY:
		lobby_buttons["invite"].grab_focus()


# ── чат лобби ───────────────────────────────────────────────────────────────
func _on_chat_entered(text):
	text = text.strip_edges()
	chat_input.text = ""
	if text != "":
		coop.send_chat(text)


func _on_chat_event(author, text, is_system):
	var l = RichTextLabel.new()
	l.fit_content_height = true
	l.scroll_active = false
	l.rect_min_size = Vector2(CHAT_RECT.size.x - 24, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_font_override("normal_font", small)
	if is_system:
		l.push_font(italic)
		l.push_color(Color(1, 1, 1, 0.55))
		l.add_text(text)
		l.pop()
		l.pop()
	else:
		l.push_font(italic)
		l.push_color(UI.ACCENT)
		l.add_text(author)
		l.pop()
		l.pop()
		l.add_text("  " + text)
	chat_log.add_child(l)
	chat_lines.append(l)
	while chat_lines.size() > CHAT_LINES:
		chat_lines.pop_front().queue_free()


# ── присоединиться ──────────────────────────────────────────────────────────
func _join_signature():
	var parts = []
	for f in coop.friends():
		if f["lobby"] != 0:
			parts.append(str(f["lobby"]))
	return PoolStringArray(parts).join(",")


func _fill_join():
	join_signature = _join_signature()
	for c in join_list.get_children():
		c.queue_free()
	join_buttons = []
	var y = TOP
	for f in coop.friends():
		if f["lobby"] == 0:
			continue
		var b = UI.button(_t("lobby_of") % f["name"], Vector2(X, y), 340)
		b.connect("pressed", self, "_on_join", [f["lobby"]])
		join_list.add_child(b)
		join_buttons.append(b)
		y += ROW
	if join_buttons.empty():
		join_list.add_child(UI.label(_t("no_lobbies"), Vector2(X, y), Vector2(380, 70), 0.6, italic))
		y += 80
	else:
		y += 15
	var refresh = UI.button(_t("refresh"), Vector2(X, y))
	refresh.connect("pressed", self, "_fill_join")
	join_list.add_child(refresh)
	var back = UI.button(_t("back"), Vector2(X, y + ROW))
	back.connect("pressed", self, "_go", [Page.HUB])
	join_list.add_child(back)
	UI.chain_focus(join_buttons + [refresh, back])
	(join_buttons[0] if not join_buttons.empty() else refresh).grab_focus()


func _on_join(lobby):
	coop.join(lobby)
	_go(Page.LOBBY)


# ── кадр ────────────────────────────────────────────────────────────────────
func _process(delta):
	# пункт меню виден вместе с остальными (их прячут экраны настроек, титров…)
	var new_game = hud.get_node_or_null("NewGameButton")
	open_button.visible = new_game.visible if new_game else true
	if preview_box.visible and preview_pivot:
		preview_pivot.rotation.y += PREVIEW_SPIN * delta
	if screen.visible and page == Page.JOIN:
		join_timer += delta
		if join_timer >= JOIN_REFRESH_SECONDS:
			join_timer = 0.0
			if _join_signature() != join_signature:
				_fill_join()   # только если список лобби изменился — не сбиваем фокус
