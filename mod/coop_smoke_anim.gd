extends Reference
# Курение у аватара друга той же анимацией, что у игрока от первого лица.
# Руки игрока (PlayerSmokingHands1) — отдельная модель на скелете Mixamo, как и скины прохожих.
# Анимацию проигрываем на невидимой копии рук и перекладываем на левую руку скина: поворот
# каждой кости относительно груди (Spine2) отсчитываем от позы покоя у рук и повторяем у скина.
#
# В анимации рука то у рта, то опущена за кадр. Опущенная рука в осях рук смотрит в сторону,
# у скина это выглядит как вытянутая рука, поэтому вес смешивания зависит от того, насколько
# рука близко ко рту: у рта — поза из анимации, вдали — обычная ходьба или стойка скина.

const HANDS_SCENE = "res://Prefabs/PlayerSmokingHands1.tscn"
const ANIMATION = "PlayerSmoking1"
const ARM_PARTS = ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]
const CHEST = "Spine2"
const CIGARETTE_BONE = "LeftHandIndex2"
# Расстояние кисть—голова в длинах предплечья: 0.84 — у рта, 2.97 — рука опущена.
const NEAR_RATIO = 1.2
const FAR_RATIO = 2.6
const KEEP_TYPES = ["Skeleton", "AnimationPlayer"]

var hands                       # невидимая копия рук: Spatial → Armature (Skeleton) → AnimationPlayer
var hands_skel
var player
var length = 0.0
var pairs = []                  # [[кость рук, кость скина]] для левой руки, от плеча к пальцам
var src_chest = -1
var dst_chest = -1
var src_rest_rel = {}           # кость рук → покой относительно груди
var dst_rest_rel = {}
var hand_bone = -1
var head_bone = -1
var fore_bone = -1
var cigarette_bone = -1


# owner — узел, под которым живёт копия рук (аватар); skel — скелет скина.
# Возвращает false, если анимацию на этот скин переложить нельзя.
func setup(owner, skel):
	var packed = load(HANDS_SCENE)
	if packed == null or skel == null:
		return false
	hands = packed.instance()
	_strip(hands)
	hands.visible = false
	owner.add_child(hands)
	hands_skel = hands.get_node_or_null("Armature")
	player = hands_skel.get_node_or_null("AnimationPlayer") if hands_skel else null
	if player == null or not player.has_animation(ANIMATION):
		return false
	player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	player.play(ANIMATION)
	length = player.get_animation(ANIMATION).length
	src_chest = hands_skel.find_bone("mixamorig" + CHEST)
	dst_chest = _skin_bone(skel, CHEST)
	if src_chest < 0 or dst_chest < 0:
		return false
	var src_chest_rest = _rest_global(hands_skel, src_chest).basis.orthonormalized()
	var dst_chest_rest = _rest_global(skel, dst_chest).basis.orthonormalized()
	for sb in range(hands_skel.get_bone_count()):
		var name = hands_skel.get_bone_name(sb).replace("mixamorig", "")
		if not _is_arm(name):
			continue
		var db = _skin_bone(skel, name)
		if db < 0:
			continue
		pairs.append([sb, db])
		src_rest_rel[sb] = src_chest_rest.inverse() * _rest_global(hands_skel, sb).basis.orthonormalized()
		dst_rest_rel[db] = dst_chest_rest.inverse() * _rest_global(skel, db).basis.orthonormalized()
	hand_bone = hands_skel.find_bone("mixamorigLeftHand")
	head_bone = hands_skel.find_bone("mixamorigHead")
	fore_bone = hands_skel.find_bone("mixamorigLeftForeArm")
	cigarette_bone = _skin_bone(skel, CIGARETTE_BONE)
	return not pairs.empty() and hand_bone >= 0 and head_bone >= 0 and fore_bone >= 0


func free_hands():
	if hands and is_instance_valid(hands):
		hands.queue_free()


# Кадр t анимации поверх уже выставленной позы скина (ходьба или стойка). Возвращает вес 0..1.
func apply(skel, t):
	if t >= length:
		return 0.0
	player.seek(t, true)
	var weight = _mouth_weight()
	if weight <= 0.0:
		return 0.0
	var src_chest_g = hands_skel.get_bone_global_pose(src_chest).basis.orthonormalized()
	var dst_chest_g = skel.get_bone_global_pose(dst_chest).basis.orthonormalized()
	var placed = {}             # кость скина → её новый глобальный поворот (для детей)
	for pair in pairs:
		var sb = pair[0]
		var db = pair[1]
		var src_rel = src_chest_g.inverse() * hands_skel.get_bone_global_pose(sb).basis.orthonormalized()
		var delta = src_rel * src_rest_rel[sb].inverse()
		var target = dst_chest_g * delta * dst_rest_rel[db]
		var parent = skel.get_bone_parent(db)
		var parent_g = placed[parent] if placed.has(parent) else skel.get_bone_global_pose(parent).basis.orthonormalized()
		var local_full = parent_g.inverse() * target
		var anim_pose = Quat((skel.get_bone_rest(db).basis.orthonormalized().inverse() * local_full).orthonormalized())
		var pose = skel.get_bone_pose(db)
		var blended = Quat(pose.basis.orthonormalized()).slerp(anim_pose, weight)
		skel.set_bone_pose(db, Transform(Basis(blended), pose.origin))
		placed[db] = (parent_g * skel.get_bone_rest(db).basis.orthonormalized() * Basis(blended)).orthonormalized()
	return weight


# Где сейчас пальцы с сигаретой у скина (глобально); null, если такой кости нет.
func cigarette_point(skel):
	if cigarette_bone < 0:
		return null
	return skel.global_transform.xform(skel.get_bone_global_pose(cigarette_bone).origin)


func _mouth_weight():
	var hand = hands_skel.get_bone_global_pose(hand_bone).origin
	var head = hands_skel.get_bone_global_pose(head_bone).origin
	var fore = hands_skel.get_bone_global_pose(fore_bone).origin
	var unit = hand.distance_to(fore)
	if unit <= 0.0001:
		return 0.0
	var ratio = hand.distance_to(head) / unit
	return smoothstep(FAR_RATIO, NEAR_RATIO, ratio)


static func _is_arm(name):
	for part in ARM_PARTS:
		if name.begins_with(part):
			return true
	return false


static func _skin_bone(skel, name):
	for prefix in ["mixamorig_", "mixamorig"]:
		var b = skel.find_bone(prefix + name)
		if b >= 0:
			return b
	return -1


static func _rest_global(skel, bone):
	var t = skel.get_bone_rest(bone)
	var p = skel.get_bone_parent(bone)
	while p >= 0:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t


# Из копии рук убираем всё, кроме скелета, проигрывателя и звука затяжки: свет зажигалки, дым,
# AnimationTree и скрипты игры (они ищут игрока и трогают его фонарик).
static func _strip(node):
	node.set_script(null)
	for child in node.get_children():
		if child.get_class() in KEEP_TYPES or child.name == "Armature":
			_strip(child)
		elif child.name == "SmokingSound":
			pass   # анимация сама включает звук затяжки: друг слышит его рядом с аватаром
		elif child is MeshInstance and node is Skeleton:
			child.visible = false   # сами руки: нужен только их скелет
		else:
			node.remove_child(child)
			child.free()
