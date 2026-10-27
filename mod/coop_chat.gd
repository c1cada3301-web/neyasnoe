extends CanvasLayer
# Чат кооп-мода в стиле игры: шрифт Old Standard, как в субтитрах, белый текст с чёрной тенью,
# имена — курсивом голубым, как кнопки меню. Лента в левом нижнем углу, растёт вверх.
# Пока строка ввода открыта, все игровые действия InputMap временно сняты, чтобы буквы
# не двигали игрока и не нажимали «взаимодействовать».

signal submitted(text)

const FONT_REGULAR = "res://Assets/Fonts/OldStandardRegular.tres"
const FONT_ITALIC = "res://Assets/Fonts/OldStandardItalic.tres"
const FONT_SIZE = 13               # вьюпорт игры 960×540 растягивается на экран
const ACCENT = Color("#69b2ff")    # Theme2: Button/colors/font_color
const SYSTEM = Color(1, 1, 1, 0.7)
const WIDTH = 380
const MARGIN_LEFT = 24
const MARGIN_BOTTOM = 24
const MAX_LINES = 8
const LINE_SECONDS = 12.0
const MAX_LENGTH = 200
const BACKDROP_PAD = 10            # насколько виньетка шире ленты
const BACKDROP_ALPHA = 0.45

var regular
var italic
var box
var backdrop              # мягкое затемнение под лентой, чтобы текст читался на любом фоне
var input
var lines = []            # [{label, time}]
var saved_actions = {}    # action → [InputEvent]


func _init():
	layer = 100
	pause_mode = Node.PAUSE_MODE_PROCESS


func _ready():
	regular = _font(FONT_REGULAR)
	italic = _font(FONT_ITALIC)

	backdrop = Panel.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_stylebox_override("panel", _backdrop_style())
	backdrop.visible = false
	add_child(backdrop)   # раньше ленты — рисуется под ней

	box = VBoxContainer.new()
	# привязка к низу экрана: новые строки добавляют высоту вверх
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.margin_left = MARGIN_LEFT
	box.margin_right = MARGIN_LEFT + WIDTH
	box.margin_top = -MARGIN_BOTTOM
	box.margin_bottom = -MARGIN_BOTTOM
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	input = LineEdit.new()
	input.rect_min_size = Vector2(WIDTH, 0)
	input.max_length = MAX_LENGTH
	input.placeholder_text = "Сообщение…"
	input.caret_blink = true
	if regular:
		input.add_font_override("font", regular)
	input.add_color_override("font_color", Color(1, 1, 1))
	input.add_color_override("cursor_color", Color(1, 1, 1))
	input.add_stylebox_override("normal", _input_style())
	input.add_stylebox_override("focus", _input_style())
	input.visible = false
	input.connect("text_entered", self, "_on_text_entered")
	input.connect("gui_input", self, "_on_input_gui")
	box.add_child(input)   # строка ввода — последней, под сообщениями


func _font(path):
	var base = load(path)
	if not (base is DynamicFont):
		return null
	var f = base.duplicate()
	f.size = FONT_SIZE
	return f


# Тёмная подложка со скруглением и размытой тенью того же цвета — края уходят в ноль.
func _backdrop_style():
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, BACKDROP_ALPHA)
	s.shadow_color = Color(0, 0, 0, BACKDROP_ALPHA)
	s.shadow_size = 18
	s.set_corner_radius_all(12)
	return s


func _input_style():
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.35)
	s.border_color = Color(1, 1, 1, 0.35)
	s.border_width_bottom = 1
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


# В главном меню ленту прячем: там чат показывает экран лобби.
func set_hidden(value):
	if box.visible == value:
		box.visible = not value
	if value and is_open():
		close()


func is_open():
	return input.visible


func open():
	if is_open():
		return
	_block_game_input()
	input.text = ""
	input.visible = true
	input.grab_focus()
	_refresh_fade()


func close():
	if not is_open():
		return
	input.release_focus()
	input.visible = false
	_restore_game_input()


func clear():
	for line in lines:
		line["label"].queue_free()
	lines.clear()


func message(author, text):
	var label = _add_line()
	_italic(label, author, ACCENT)
	label.add_text("  " + text)   # add_text не разбирает BBCode — скобки в сообщении безопасны


func system(text):
	_italic(_add_line(), text, SYSTEM)


func _italic(label, text, color):
	if italic:
		label.push_font(italic)
	label.push_color(color)
	label.add_text(text)
	label.pop()
	if italic:
		label.pop()


func _on_text_entered(text):
	text = text.strip_edges()
	close()
	if text != "":
		emit_signal("submitted", text)


func _on_input_gui(event):
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()


func _add_line():
	var label = RichTextLabel.new()
	label.fit_content_height = true
	label.scroll_active = false
	label.rect_min_size = Vector2(WIDTH, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if regular:
		label.add_font_override("normal_font", regular)
	label.add_color_override("default_color", Color(1, 1, 1))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	box.add_child(label)
	box.move_child(input, box.get_child_count() - 1)
	lines.append({"label": label, "time": OS.get_ticks_msec() / 1000.0})
	while lines.size() > MAX_LINES:
		lines.pop_front()["label"].queue_free()
	return label


func _process(_delta):
	_refresh_fade()


# Старые строки гаснут; при открытом чате видны все.
func _refresh_fade():
	var now = OS.get_ticks_msec() / 1000.0
	var strongest = 1.0 if is_open() else 0.0
	for line in lines:
		var age = now - line["time"]
		var alpha = 1.0 if is_open() else clamp(LINE_SECONDS - age, 0.0, 1.0)
		line["label"].modulate.a = alpha
		strongest = max(strongest, alpha)
	# виньетка гаснет вместе с последней видимой строкой
	backdrop.visible = box.visible and strongest > 0.0
	if backdrop.visible:
		backdrop.modulate.a = strongest
		backdrop.rect_position = box.rect_position - Vector2(BACKDROP_PAD, BACKDROP_PAD)
		backdrop.rect_size = box.rect_size + Vector2(BACKDROP_PAD, BACKDROP_PAD) * 2


func _block_game_input():
	saved_actions.clear()
	for action in InputMap.get_actions():
		saved_actions[action] = InputMap.get_action_list(action)
		InputMap.action_erase_events(action)
		Input.action_release(action)   # иначе зажатая W «залипнет» до закрытия чата


func _restore_game_input():
	for action in saved_actions:
		for event in saved_actions[action]:
			InputMap.action_add_event(action, event)
	saved_actions.clear()
