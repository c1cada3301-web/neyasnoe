extends Reference
# Музыка в машине: те же 10 треков, что играют в машинах игры (узел CarMusic у префабов).
# Номер трека передаётся друзьям, чтобы у копии машины играло то же самое.

const NONE = -1
const TRACKS = [
	"res://Assets/Audios/Music/CarMusic1 SK - 1980 Something.ogg",
	"res://Assets/Audios/Music/CarMusic2 HoliznaCC0 - Way Of The Samurai.ogg",
	"res://Assets/Audios/Music/CarMusic3 Yshwa - I Think I Can.ogg",
	"res://Assets/Audios/Music/CarMusic4 iamlamprey - Through You.ogg",
	"res://Assets/Audios/Music/CarMusic5 Turku Nomads of the Silk Road - Macka Yollari.ogg",
	"res://Assets/Audios/Music/CarMusic6 Ushko - Opening.ogg",
	"res://Assets/Audios/Music/CarMusic7 Ushko - Angel_150.ogg",
	"res://Assets/Audios/Music/CarMusic8 Ushko - Volvo.ogg",
	"res://Assets/Audios/Music/CarMusic9 Ushko - Maska_Iz_Kapel.ogg",
	"res://Assets/Audios/Music/CarMusic10 Ushko - O4nis.ogg",
]


static func player(car):
	var node = car.get_node_or_null("CarMusic")
	return node if node is AudioStreamPlayer3D else null


# У машин, собранных из стоящих моделей, своего CarMusic нет — ставим такой же, как у префабов.
static func ensure_player(car):
	var node = player(car)
	if node:
		return node
	node = AudioStreamPlayer3D.new()
	node.name = "CarMusic"
	node.unit_db = 8.0
	node.unit_size = 3.0
	node.max_db = 1.0
	node.max_distance = 200.0
	node.translation = Vector3(0, 0.5, 0)
	car.add_child(node)
	return node


# Что сейчас играет: номер в TRACKS или NONE, если тихо (или трек не из списка).
static func track_of(car):
	var node = player(car)
	if node == null or not node.playing or node.stream == null:
		return NONE
	return TRACKS.find(node.stream.resource_path)


static func set_track(car, index):
	if index == NONE:
		var node = player(car)
		if node:
			node.stop()
		return
	var stream = load(TRACKS[index])
	if stream == null:
		return
	var node = ensure_player(car)
	node.stream = stream
	node.play()


# «CarMusic8 Ushko - Volvo.ogg» → «Ushko — Volvo»
static func title(index):
	var name = TRACKS[index].get_file().get_basename()
	return name.substr(name.find(" ") + 1).replace(" - ", " — ")
