extends Node2D

const SIZE := Vector2(480, 270)
const PLAY_RECT := Rect2(24, 48, 432, 196)
const SPEED := 92.0
const THREAD_STEP := 4.0
const ROUND_TIME := 60.0
const BG := Color("0d0b24")
const PANEL := Color("1b1640")
const GOLD := Color("ffd978")
const WHITE := Color("fff7e8")
const PINK := Color("ff78bb")
const BLUE := Color("6ce5ff")
const PURPLE := Color("a87cff")

enum State { MENU, PLAYING, LEVEL_CLEAR, GAME_CLEAR, FAILED }

var state := State.MENU
var level_index := 0
var player := Vector2.ZERO
var trail: PackedVector2Array = []
var knots: Array[Vector2] = []
var nodes: Array[Dictionary] = []
var next_node := 1
var thread_used := 0.0
var thread_limit := 620.0
var remaining := ROUND_TIME
var cat_delay := 4.0
var cat_tick := 0.0
var cat_stun := 0.0
var pulse_cooldown := 0.0
var paused := false
var activate_requested := false
var pause_requested := false
var message := ""
var message_left := 0.0
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var title_label: Label
var info_label: Label
var button: Button

var level_data := [
	{"name":"HEARTBEAT", "hint":"Connect three hearts", "color":PINK, "limit":560.0,
	 "points":[Vector2(240,210),Vector2(155,145),Vector2(205,90),Vector2(240,130),Vector2(275,90),Vector2(325,145)],
	 "symbols":["START","HEART","HEART","HEART","HEART","HEART"]},
	{"name":"FALLING STAR", "hint":"Trace the star path", "color":GOLD, "limit":1120.0,
	 "points":[Vector2(110,205),Vector2(240,70),Vector2(370,205),Vector2(160,125),Vector2(320,125),Vector2(110,205)],
	 "symbols":["START","STAR","STAR","STAR","STAR","STAR"]},
	{"name":"CRESCENT", "hint":"Wake the moon", "color":BLUE, "limit":610.0,
	 "points":[Vector2(150,200),Vector2(115,140),Vector2(155,80),Vector2(245,70),Vector2(205,115),Vector2(245,170),Vector2(150,200)],
	 "symbols":["START","MOON","MOON","MOON","MOON","MOON","MOON"]},
	{"name":"BUTTERFLY", "hint":"Cross the thread to tie a knot", "color":PURPLE, "limit":760.0,
	 "points":[Vector2(240,215),Vector2(145,170),Vector2(150,75),Vector2(240,140),Vector2(330,75),Vector2(335,170),Vector2(240,140),Vector2(240,215)],
	 "symbols":["START","GEM","STAR","KNOT","STAR","GEM","KNOT","FLOWER"]},
	{"name":"MOON CROWN", "hint":"Complete the garden sigil", "color":Color("ff9fe5"), "limit":1120.0,
	 "points":[Vector2(80,210),Vector2(110,95),Vector2(180,155),Vector2(240,70),Vector2(300,155),Vector2(370,95),Vector2(400,210),Vector2(240,180),Vector2(80,210)],
	 "symbols":["START","MOON","HEART","STAR","HEART","MOON","GEM","CROWN","FLOWER"]}
]

func _ready() -> void:
	rng.randomize()
	build_ui()
	show_menu()

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	title_label = Label.new()
	title_label.position = Vector2(45, 63)
	title_label.size = Vector2(390, 45)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", GOLD)
	layer.add_child(title_label)
	info_label = Label.new()
	info_label.position = Vector2(65, 112)
	info_label.size = Vector2(350, 70)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(info_label)
	button = Button.new()
	button.position = Vector2(155, 202)
	button.size = Vector2(170, 36)
	button.pressed.connect(_on_button)
	layer.add_child(button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE: activate_requested = true
		if event.physical_keycode == KEY_P or event.physical_keycode == KEY_ESCAPE: pause_requested = true
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: activate_requested = true
		if event.button_index == JOY_BUTTON_START: pause_requested = true

func show_menu() -> void:
	state = State.MENU
	title_label.visible = true
	info_label.visible = true
	button.visible = true
	title_label.text = "MOON THREAD"
	info_label.text = "Draw magical patterns by walking.\nProtect your glowing thread from the Thread Eater."
	button.text = "BEGIN WEAVING"
	queue_redraw()

func _on_button() -> void:
	match state:
		State.MENU, State.GAME_CLEAR:
			level_index = 0
			start_level()
		State.LEVEL_CLEAR:
			level_index += 1
			start_level()
		State.FAILED:
			start_level()

func start_level() -> void:
	state = State.PLAYING
	title_label.visible = false
	info_label.visible = false
	button.visible = false
	nodes.clear()
	var data: Dictionary = level_data[level_index]
	for i in data.points.size():
		nodes.append({"pos":data.points[i], "symbol":data.symbols[i], "lit":i == 0})
	player = nodes[0].pos
	trail = PackedVector2Array([player])
	knots.clear()
	next_node = 1
	thread_used = 0.0
	thread_limit = data.limit
	remaining = ROUND_TIME
	cat_delay = 7.0
	cat_tick = 0.0
	cat_stun = 0.0
	pulse_cooldown = 0.0
	paused = false
	particles.clear()
	show_message("LEVEL %d: %s" % [level_index + 1, data.name], 2.0)
	queue_redraw()

func _process(delta: float) -> void:
	update_particles(delta)
	if state != State.PLAYING:
		queue_redraw()
		return
	if pause_requested:
		pause_requested = false
		paused = not paused
		show_message("PAUSED" if paused else "WEAVE!", 1.0)
	if paused:
		queue_redraw()
		return
	remaining -= delta
	message_left = maxf(0.0, message_left - delta)
	cat_delay -= delta
	cat_stun = maxf(0.0, cat_stun - delta)
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	if activate_requested:
		activate_requested = false
		cast_pulse()
	move_player(delta)
	update_cat(delta)
	if remaining <= 0.0:
		fail_level("THE MOON FADED")
	elif thread_used >= thread_limit:
		fail_level("THREAD SUPPLY EMPTY")
	queue_redraw()

func move_player(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	input = input.normalized()
	if input == Vector2.ZERO: return
	var old := player
	player += input * SPEED * delta
	player.x = clampf(player.x, PLAY_RECT.position.x, PLAY_RECT.end.x)
	player.y = clampf(player.y, PLAY_RECT.position.y, PLAY_RECT.end.y)
	if trail.is_empty() or player.distance_to(trail[-1]) >= THREAD_STEP:
		var segment_start: Vector2 = trail[-1]
		trail.append(player)
		thread_used += segment_start.distance_to(player)
		check_intersection(segment_start, player)
	check_node_connection(old)

func check_node_connection(_old: Vector2) -> void:
	if next_node >= nodes.size(): return
	var target: Vector2 = nodes[next_node].pos
	if player.distance_to(target) <= 13.0:
		nodes[next_node].lit = true
		player = target
		trail.append(target)
		burst(target, level_data[level_index].color)
		next_node += 1
		show_message("NODE AWAKENED %d/%d" % [next_node, nodes.size()], 0.9)
		if next_node >= nodes.size(): complete_level()

func check_intersection(a: Vector2, b: Vector2) -> void:
	if trail.size() < 12: return
	for i in range(0, trail.size() - 8):
		var c := trail[i]
		var d := trail[i + 1]
		var hit = Geometry2D.segment_intersects_segment(a, b, c, d)
		if hit != null:
			var point: Vector2 = hit
			for knot in knots:
				if knot.distance_to(point) < 12.0: return
			knots.append(point)
			cat_stun = maxf(cat_stun, 2.5)
			burst(point, BLUE)
			show_message("MAGIC KNOT! CAT FROZEN", 1.2)
			return

func update_cat(delta: float) -> void:
	if cat_delay > 0.0 or cat_stun > 0.0 or trail.size() < 3: return
	cat_tick -= delta
	if cat_tick <= 0.0:
		cat_tick = maxf(0.055, 0.13 - level_index * 0.012)
		trail.remove_at(0)
		if trail.size() < 3:
			fail_level("THE THREAD EATER CAUGHT YOUR LIGHT")

func cast_pulse() -> void:
	if pulse_cooldown > 0.0:
		show_message("PULSE RECHARGING", 0.7)
		return
	pulse_cooldown = 6.0
	cat_stun = 1.2
	# Restore a short protective tail behind the cat.
	var restored: PackedVector2Array = []
	for i in 10:
		var t := float(i) / 10.0
		restored.append(nodes[0].pos.lerp(trail[0], t))
	for i in range(restored.size() - 1, -1, -1): trail.insert(0, restored[i])
	burst(trail[0], PINK)
	show_message("MOON PULSE!", 1.0)

func complete_level() -> void:
	state = State.LEVEL_CLEAR if level_index < level_data.size() - 1 else State.GAME_CLEAR
	burst(player, GOLD, 30)
	title_label.visible = true
	info_label.visible = true
	button.visible = true
	if state == State.LEVEL_CLEAR:
		title_label.text = "PATTERN AWAKENED"
		info_label.text = "%s glows in the Moon Garden.\nMagic knots created: %d" % [level_data[level_index].name, knots.size()]
		button.text = "NEXT PATTERN"
	else:
		title_label.text = "THE GARDEN AWAKENS"
		info_label.text = "Five moon patterns join into one living constellation.\nYou wove the light back into the world."
		button.text = "WEAVE AGAIN"

func fail_level(reason: String) -> void:
	if state != State.PLAYING: return
	state = State.FAILED
	title_label.visible = true
	info_label.visible = true
	button.visible = true
	title_label.text = "THREAD BROKEN"
	info_label.text = reason + "\nTry a shorter route or create a Magic Knot."
	button.text = "RETRY PATTERN"

func show_message(text: String, duration: float) -> void:
	message = text
	message_left = duration

func burst(at: Vector2, color: Color, count := 14) -> void:
	for i in count:
		particles.append({"pos":at, "vel":Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(18.0, 55.0), "life":rng.randf_range(0.5, 1.1), "color":color})

func update_particles(delta: float) -> void:
	for p in particles:
		p.pos += p.vel * delta
		p.vel *= 0.96
		p.life -= delta
	for i in range(particles.size() - 1, -1, -1):
		if particles[i].life <= 0.0: particles.remove_at(i)

func symbol_text(symbol: String) -> String:
	match symbol:
		"HEART": return "♥"
		"STAR": return "✦"
		"MOON": return "☾"
		"FLOWER": return "✿"
		"GEM": return "◇"
		"KNOT": return "×"
		"CROWN": return "♛"
		_: return "•"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), BG)
	for i in 32:
		var x := float((i * 83 + 17) % 470)
		var y := float((i * 47 + 29) % 260)
		draw_circle(Vector2(x, y), 1.0, Color(0.55, 0.65, 1.0, 0.22))
	if state != State.PLAYING:
		draw_circle(Vector2(90, 76), 32, Color("34245e"))
		draw_circle(Vector2(103, 67), 29, BG)
		return
	var color: Color = level_data[level_index].color
	draw_rect(PLAY_RECT, PANEL, true)
	draw_rect(PLAY_RECT, Color("504478"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(24, 22), "LEVEL %d/5  %s" % [level_index + 1, level_data[level_index].name], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
	draw_string(ThemeDB.fallback_font, Vector2(300, 22), "TIME %02d" % ceili(remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)
	var left := maxi(0, int(thread_limit - thread_used))
	draw_string(ThemeDB.fallback_font, Vector2(385, 22), "LINE %03d" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if trail.size() >= 2:
		draw_polyline(trail, Color(color, 0.22), 7.0, true)
		draw_polyline(trail, color, 2.2, true)
	for knot in knots:
		draw_circle(knot, 7.0, Color(BLUE, 0.22))
		draw_circle(knot, 3.0, BLUE)
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var lit: bool = node.lit
		var expected := i == next_node
		if lit: draw_circle(node.pos, 12.0, Color(color, 0.18))
		if expected: draw_arc(node.pos, 14.0, 0.0, TAU, 24, WHITE, 1.5)
		draw_circle(node.pos, 8.0, color if lit else Color("4d466b"))
		draw_string(ThemeDB.fallback_font, node.pos + Vector2(-6, 5), symbol_text(node.symbol), HORIZONTAL_ALIGNMENT_CENTER, 12, 13, WHITE if lit else Color("9187ae"))
	# Thread Eater sits at the vanishing end of the thread.
	if cat_delay <= 0.0 and not trail.is_empty():
		var cat := trail[0]
		var cat_color := BLUE if cat_stun > 0.0 else Color("090611")
		draw_circle(cat, 7.0, cat_color)
		draw_colored_polygon(PackedVector2Array([cat+Vector2(-6,-2),cat+Vector2(-5,-10),cat+Vector2(-1,-5)]),cat_color)
		draw_colored_polygon(PackedVector2Array([cat+Vector2(6,-2),cat+Vector2(5,-10),cat+Vector2(1,-5)]),cat_color)
		draw_circle(cat + Vector2(-2, -1), 1.0, GOLD)
		draw_circle(cat + Vector2(2, -1), 1.0, GOLD)
	# Luna and the active spool.
	draw_circle(player, 7.0, Color("ffd9c8"))
	draw_colored_polygon(PackedVector2Array([player+Vector2(-8,7),player+Vector2(8,7),player+Vector2(0,-6)]),PURPLE)
	draw_colored_polygon(PackedVector2Array([player+Vector2(-9,-5),player+Vector2(9,-5),player+Vector2(2,-14)]),Color("6a3ca0"))
	draw_circle(player + Vector2(4, -7), 2.0, PINK)
	for p in particles:
		draw_circle(p.pos, 2.0, Color(p.color, clampf(p.life, 0.0, 1.0)))
	if message_left > 0.0:
		draw_rect(Rect2(110, 239, 260, 24), Color(0.03,0.02,0.1,0.88))
		draw_string(ThemeDB.fallback_font, Vector2(110, 256), message, HORIZONTAL_ALIGNMENT_CENTER, 260, 12, GOLD)
	if pulse_cooldown > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(24, 262), "PULSE %.1fs" % pulse_cooldown, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9c94b8"))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(24, 262), "PULSE READY [SPACE/A]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BLUE)
	if paused:
		draw_rect(Rect2(155, 108, 170, 54), Color(0.03,0.02,0.1,0.94))
		draw_string(ThemeDB.fallback_font, Vector2(155, 142), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 170, 23, GOLD)

