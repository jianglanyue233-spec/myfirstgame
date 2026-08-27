extends Node2D

const COLS := 28
const ROWS := 14
const TILE := 16
const ORIGIN := Vector2(16, 42)
const ROUND_TIME := 60.0
const MAX_CATS := 8
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const BG := Color("130f2b")
const FLOOR := Color("211a45")
const WALL := Color("5546a6")
const WALL_GLOW := Color("8d78e8")
const PEARL := Color("fff1c7")
const GOLD := Color("ffd76a")

enum Screen { MENU, PLAYING, RESULT, LEADERBOARD, COLLECTION }

var screen := Screen.MENU
var grid: Array[Array] = []
var pearls: Dictionary = {}
var powers: Dictionary = {}
var player := Vector2i(1, 1)
var cats: Array[Dictionary] = []
var score := 0
var lives := 3
var inventory := 0
var remaining := ROUND_TIME
var power_left := 0.0
var invincible_left := 0.0
var cat_step_left := 0.0
var move_left := 0.0
var next_cat_time := 40.0
var collected := 0
var player_name := "LUNA"
var paused := false
var status_text := ""
var status_left := 0.0
var activate_requested := false
var pause_requested := false
var leaderboard: Array[Dictionary] = []
var collection: Array[String] = []
var rng := RandomNumberGenerator.new()

var ui: CanvasLayer
var title_label: Label
var info_label: Label
var name_edit: LineEdit
var primary_button: Button
var secondary_button: Button

func _ready() -> void:
	rng.randomize()
	load_save()
	build_ui()
	show_menu()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE: activate_requested = true
		if event.physical_keycode == KEY_P or event.physical_keycode == KEY_ESCAPE: pause_requested = true
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: activate_requested = true
		if event.button_index == JOY_BUTTON_START: pause_requested = true

func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	title_label = Label.new()
	title_label.position = Vector2(40, 46)
	title_label.size = Vector2(400, 50)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", GOLD)
	ui.add_child(title_label)
	info_label = Label.new()
	info_label.position = Vector2(55, 102)
	info_label.size = Vector2(370, 62)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	ui.add_child(info_label)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(150, 168)
	name_edit.size = Vector2(180, 30)
	name_edit.placeholder_text = "TYPE NAME"
	name_edit.max_length = 12
	name_edit.text = player_name
	ui.add_child(name_edit)
	primary_button = Button.new()
	primary_button.position = Vector2(150, 207)
	primary_button.size = Vector2(180, 34)
	primary_button.pressed.connect(_on_primary)
	ui.add_child(primary_button)
	secondary_button = Button.new()
	secondary_button.position = Vector2(150, 240)
	secondary_button.size = Vector2(180, 26)
	secondary_button.pressed.connect(_on_secondary)
	ui.add_child(secondary_button)

func show_menu() -> void:
	screen = Screen.MENU
	title_label.text = "CHARMS SEEKER"
	info_label.text = "Collect stardust pearls. Dodge shadow cats.\nArrow keys / Left stick: move   Space / A: moonlight"
	name_edit.visible = true
	primary_button.text = "START 60s RUN"
	primary_button.visible = true
	secondary_button.text = "COLLECTION"
	secondary_button.visible = true
	queue_redraw()

func _on_primary() -> void:
	match screen:
		Screen.MENU:
			player_name = name_edit.text.strip_edges().to_upper()
			if player_name.is_empty(): player_name = "LUNA"
			start_game()
		Screen.RESULT:
			show_leaderboard()
		Screen.LEADERBOARD:
			show_collection()
		Screen.COLLECTION:
			show_menu()

func _on_secondary() -> void:
	if screen == Screen.MENU:
		show_collection()
	elif screen == Screen.RESULT:
		start_game()
	elif screen == Screen.LEADERBOARD or screen == Screen.COLLECTION:
		show_menu()

func start_game() -> void:
	screen = Screen.PLAYING
	title_label.visible = false
	info_label.visible = false
	name_edit.visible = false
	primary_button.visible = false
	secondary_button.visible = false
	score = 0
	lives = 3
	inventory = 0
	remaining = ROUND_TIME
	power_left = 0.0
	invincible_left = 0.0
	cat_step_left = 0.15
	move_left = 0.0
	next_cat_time = 40.0
	collected = 0
	paused = false
	build_maze()
	place_collectibles()
	player = Vector2i(1, 1)
	cats.clear()
	for i in 3: add_cat(i)
	status("GO! COLLECT THE PEARLS", 1.5)
	queue_redraw()

func build_maze() -> void:
	grid.clear()
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var wall := x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1
			if not wall:
				wall = ((x % 4 == 0 and y % 4 != 2) or (y % 4 == 0 and x % 6 not in [1, 2]))
			row.append(wall)
		grid.append(row)
	# Guaranteed corridors and spawn lanes.
	for x in range(1, COLS - 1):
		grid[1][x] = false
		grid[ROWS - 2][x] = false
	for y in range(1, ROWS - 1):
		grid[y][1] = false
		grid[y][COLS - 2] = false
		grid[y][COLS >> 1] = false
	for y in range(5, 9):
		for x in range(12, 16): grid[y][x] = false

func place_collectibles() -> void:
	pearls.clear()
	powers.clear()
	var power_cells := [Vector2i(1, 1), Vector2i(COLS - 2, 1), Vector2i(1, ROWS - 2), Vector2i(COLS - 2, ROWS - 2)]
	for p in power_cells: powers[p] = true
	var candidates: Array[Vector2i] = []
	for y in range(1, ROWS - 1):
		for x in range(1, COLS - 1):
			var p := Vector2i(x, y)
			if not grid[y][x] and not powers.has(p) and p != Vector2i(14, 7): candidates.append(p)
	candidates.shuffle()
	for i in mini(180, candidates.size()): pearls[candidates[i]] = true

func add_cat(index := 0) -> void:
	if cats.size() >= MAX_CATS: return
	var spawns := [Vector2i(13, 6), Vector2i(14, 6), Vector2i(13, 7), Vector2i(14, 7), Vector2i(15, 7), Vector2i(13, 8), Vector2i(14, 8), Vector2i(15, 8)]
	cats.append({"pos": spawns[(cats.size() + index) % spawns.size()], "frozen": 0.8, "respawn": 0.0, "combo_hit": false})
	status("A SHADOW CAT APPEARED!", 1.2)

func _process(delta: float) -> void:
	if screen != Screen.PLAYING:
		return
	if pause_requested:
		pause_requested = false
		paused = not paused
		status("PAUSED" if paused else "BACK TO THE HUNT", 1.0)
	if paused:
		queue_redraw()
		return
	remaining -= delta
	power_left = maxf(0.0, power_left - delta)
	invincible_left = maxf(0.0, invincible_left - delta)
	status_left = maxf(0.0, status_left - delta)
	move_left -= delta
	cat_step_left -= delta
	if activate_requested:
		activate_requested = false
		if inventory > 0 and power_left <= 0.0:
			inventory -= 1
			power_left = 8.0
			for cat in cats: cat.combo_hit = false
			status("MOONLIGHT! CATS PETRIFIED", 1.2)
	if move_left <= 0.0:
		var direction := input_direction()
		if direction != Vector2i.ZERO:
			try_move_player(direction)
			move_left = 0.105
	if cat_step_left <= 0.0:
		move_cats()
		cat_step_left = 0.19 if power_left <= 0.0 else 0.34
	if remaining <= next_cat_time and cats.size() < 5:
		add_cat()
		next_cat_time -= 20.0
	if remaining <= 0.0:
		finish_game(false)
	queue_redraw()

func input_direction() -> Vector2i:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if absf(v.x) > absf(v.y) and absf(v.x) > 0.3: return Vector2i(1 if v.x > 0.0 else -1, 0)
	if absf(v.y) > 0.3: return Vector2i(0, 1 if v.y > 0.0 else -1)
	return Vector2i.ZERO

func try_move_player(direction: Vector2i) -> void:
	var target := player + direction
	if is_open(target):
		player = target
		collect_at_player()
		check_cat_collisions()

func collect_at_player() -> void:
	if pearls.erase(player):
		score += 10
		collected += 1
	if powers.erase(player):
		score += 30
		inventory = mini(2, inventory + 1)
		status("MOONLIGHT STORED (%d/2)" % inventory, 1.0)
	if pearls.is_empty():
		score += 500
		place_collectibles()
		if cats.size() < MAX_CATS: add_cat()
		status("MAZE CLEARED! +500", 1.5)

func move_cats() -> void:
	var step_seconds := 0.34 if power_left > 0.0 else 0.19
	for cat in cats:
		if cat.respawn > 0.0:
			cat.respawn -= step_seconds
			if cat.respawn <= 0.0:
				cat.pos = Vector2i(14, 7)
				cat.frozen = 0.7
			continue
		if cat.frozen > 0.0:
			cat.frozen -= step_seconds
			continue
		var options: Array[Vector2i] = []
		for d in DIRS:
			var candidate: Vector2i = cat.pos + d
			if is_open(candidate): options.append(candidate)
		if options.is_empty(): continue
		if power_left > 0.0:
			options.sort_custom(func(a, b): return a.distance_squared_to(player) > b.distance_squared_to(player))
			cat.pos = options[0]
		else:
			# Breadth-first pathfinding lets cats chase Luna around maze walls.
			cat.pos = next_step_toward(cat.pos, player)
	check_cat_collisions()

func next_step_toward(start: Vector2i, target: Vector2i) -> Vector2i:
	if start == target: return start
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == target: break
		for direction in DIRS:
			var next: Vector2i = current + direction
			if is_open(next) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)
	if not came_from.has(target): return start
	var step := target
	while came_from[step] != start:
		step = came_from[step]
	return step

func check_cat_collisions() -> void:
	for cat in cats:
		if cat.respawn > 0.0 or cat.pos != player: continue
		if power_left > 0.0:
			var chain := 0
			for c in cats:
				if c.combo_hit: chain += 1
			var rewards := [50, 100, 200, 400]
			score += rewards[mini(chain, 3)]
			cat.combo_hit = true
			cat.respawn = 5.0
			status("SHADOW CAT SHATTERED! +%d" % rewards[mini(chain, 3)], 1.0)
		elif invincible_left <= 0.0:
			lives -= 1
			invincible_left = 1.5
			player = Vector2i(1, 1)
			status("OUCH! %d HEARTS LEFT" % lives, 1.2)
			if lives <= 0: finish_game(true)

func is_open(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < COLS and p.y < ROWS and not grid[p.y][p.x]

func finish_game(early: bool) -> void:
	if screen != Screen.PLAYING: return
	screen = Screen.RESULT
	var chest := chest_for_score(score)
	var charms := ["Moon & Stars Charm", "Sparkling Heart Charm", "Mystic Cat Charm", "Stardust Pearl Charm"]
	var reward: String = charms[rng.randi_range(0, charms.size() - 1)]
	collection.append(reward)
	leaderboard.append({"name": player_name, "score": score})
	leaderboard.sort_custom(func(a, b): return a.score > b.score)
	if leaderboard.size() > 10: leaderboard.resize(10)
	save_game()
	title_label.visible = true
	info_label.visible = true
	name_edit.visible = false
	primary_button.visible = true
	secondary_button.visible = true
	title_label.text = "TIME UP" if not early else "GAME OVER"
	info_label.text = "Score: %d   Pearls: %d\n%s CHEST opened!\nNew charm: %s" % [score, collected, chest, reward]
	primary_button.text = "LEADERBOARD"
	secondary_button.text = "PLAY AGAIN"
	queue_redraw()

func chest_for_score(value: int) -> String:
	if value >= 5000: return "GOLD"
	if value >= 3000: return "SILVER"
	if value >= 1500: return "BRONZE"
	return "WOODEN"

func show_leaderboard() -> void:
	screen = Screen.LEADERBOARD
	title_label.text = "LEADERBOARD"
	var lines: Array[String] = []
	for i in mini(5, leaderboard.size()):
		lines.append("%d. %-12s %5d" % [i + 1, leaderboard[i].name, leaderboard[i].score])
	if lines.is_empty(): lines.append("No runs yet")
	info_label.text = "\n".join(lines)
	info_label.position.y = 95
	info_label.size.y = 100
	primary_button.text = "OPEN COLLECTION"
	secondary_button.text = "MAIN MENU"
	primary_button.visible = true
	secondary_button.visible = true
	queue_redraw()

func show_collection() -> void:
	screen = Screen.COLLECTION
	title_label.visible = true
	info_label.visible = true
	name_edit.visible = false
	primary_button.visible = true
	secondary_button.visible = true
	title_label.text = "CHARM COLLECTION"
	var counts: Dictionary = {}
	for charm in collection: counts[charm] = counts.get(charm, 0) + 1
	var lines: Array[String] = []
	for charm in counts: lines.append("%s  x%d" % [charm, counts[charm]])
	if lines.is_empty(): lines.append("Win a run to open your first chest!")
	info_label.position.y = 95
	info_label.size.y = 100
	info_label.text = "\n".join(lines)
	primary_button.text = "MAIN MENU"
	secondary_button.text = "BACK"
	queue_redraw()

func status(text: String, duration: float) -> void:
	status_text = text
	status_left = duration

func save_game() -> void:
	var file := FileAccess.open("user://charms_seeker.save", FileAccess.WRITE)
	file.store_string(JSON.stringify({"leaderboard": leaderboard, "collection": collection}))

func load_save() -> void:
	if not FileAccess.file_exists("user://charms_seeker.save"): return
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://charms_seeker.save"))
	if data is Dictionary:
		leaderboard.assign(data.get("leaderboard", []))
		collection.assign(data.get("collection", []))

func cell_center(p: Vector2i) -> Vector2:
	return ORIGIN + Vector2(p.x * TILE + TILE / 2, p.y * TILE + TILE / 2)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(480, 270)), BG)
	if screen != Screen.PLAYING:
		draw_circle(Vector2(75, 75), 24, Color("3b2d70"))
		draw_circle(Vector2(405, 75), 18, Color("6a4fa0"))
		return
	draw_string(ThemeDB.fallback_font, Vector2(16, 22), "TIME %02d" % ceili(remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	draw_string(ThemeDB.fallback_font, Vector2(110, 22), "SCORE %05d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(252, 22), "LIFE " + "♥".repeat(lives), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ff718d"))
	draw_string(ThemeDB.fallback_font, Vector2(364, 22), "MOON %d/2" % inventory, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8fe8ff"))
	for y in ROWS:
		for x in COLS:
			var rect := Rect2(ORIGIN + Vector2(x * TILE, y * TILE), Vector2(TILE, TILE))
			draw_rect(rect, WALL if grid[y][x] else FLOOR)
			if grid[y][x]: draw_rect(rect.grow(-3), WALL_GLOW, false, 1.0)
	for p in pearls:
		draw_circle(cell_center(p), 2.5, PEARL)
		draw_circle(cell_center(p) - Vector2(1, 1), 0.8, Color.WHITE)
	for p in powers:
		var c := cell_center(p)
		draw_circle(c, 6, Color("77ddff"))
		draw_circle(c + Vector2(3, -2), 5, FLOOR)
	# Luna: hat, face, cloak and heart badge.
	var pc := cell_center(player)
	var blink := invincible_left > 0.0 and int(invincible_left * 10.0) % 2 == 0
	if not blink:
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-7, 6), pc + Vector2(7, 6), pc + Vector2(0, -7)]), Color("b889ff"))
		draw_circle(pc - Vector2(0, 4), 4, Color("ffd7bc"))
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-7, -6), pc + Vector2(7, -6), pc + Vector2(1, -15)]), Color("6f3ca8"))
		draw_circle(pc + Vector2(3, -8), 2, Color("ff6fae"))
	for cat in cats:
		if cat.respawn > 0.0: continue
		var c: Vector2 = cell_center(cat.pos)
		var petrified := power_left > 0.0
		var cat_color := Color("9eeaff") if petrified else Color("160f22")
		draw_circle(c, 6, cat_color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -3), c + Vector2(-5, -9), c + Vector2(-1, -5)]), cat_color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(6, -3), c + Vector2(5, -9), c + Vector2(1, -5)]), cat_color)
		draw_circle(c + Vector2(-2, -1), 1, Color("ffe55c"))
		draw_circle(c + Vector2(2, -1), 1, Color("ffe55c"))
	if power_left > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(187, 38), "PETRIFIED %.1fs" % power_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8fe8ff"))
		if power_left <= 2.0 and int(power_left * 8.0) % 2 == 0:
			draw_rect(Rect2(2, 2, 476, 266), Color("a8f2ff"), false, 3)
	if status_left > 0.0:
		draw_rect(Rect2(120, 238, 240, 24), Color(0.05, 0.03, 0.12, 0.86))
		draw_string(ThemeDB.fallback_font, Vector2(120, 255), status_text, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, GOLD)
	if paused:
		draw_rect(Rect2(150, 105, 180, 55), Color(0.05, 0.03, 0.12, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(150, 139), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, 180, 24, GOLD)

