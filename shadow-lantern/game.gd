extends Node2D

const W := 480.0
const H := 270.0
const GROUND_Y := 213.0
const BG := Color("100d24")
const WALL := Color("292247")
const GOLD := Color("ffd66f")
const MOON := Color("9be9ff")
const PINK := Color("ff82bd")
const SHADOW := Color("090711")

enum State { MENU, PLAYING, LEVEL_CLEAR, COMPLETE }

var state := State.MENU
var level_index := 0
var in_shadow := false
var real_x := 60.0
var shadow_x := 60.0
var lights: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var floors: Array[Vector2] = []
var active_light := 0
var dragging := -1
var message := ""
var message_left := 0.0
var paused := false
var switch_requested := false
var grow_requested := false
var restart_requested := false
var seal_requested := false
var tab_requested := false
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var title_label: Label
var info_label: Label
var button: Button

var levels := [
	{"name":"THE FIRST BRIDGE", "hint":"Move the lamp left of the box, then enter the shadow.", "kind":"exit",
	 "floors":[Vector2(20,155),Vector2(325,460)], "lights":[60.0],
	 "objects":[{"type":"box","x":174.0,"height":44.0}], "exit":430.0},
	{"name":"TWO LIGHTS", "hint":"Cast one shadow right and the other left until they meet.", "kind":"exit",
	 "floors":[Vector2(20,135),Vector2(350,460)], "lights":[48.0,432.0],
	 "objects":[{"type":"box","x":146.0,"height":38.0},{"type":"box","x":338.0,"height":38.0}], "exit":430.0},
	{"name":"CATWALK", "hint":"Enter the moving cat shadow and keep pace with it.", "kind":"exit",
	 "floors":[Vector2(20,150),Vector2(365,460)], "lights":[38.0],
	 "objects":[{"type":"cat","x":148.0,"height":28.0,"min":145.0,"max":350.0,"speed":24.0,"dir":1.0}], "exit":430.0},
	{"name":"GROWING DARK", "hint":"Press G three times. A taller plant casts a longer road.", "kind":"exit",
	 "floors":[Vector2(20,150),Vector2(365,460)], "lights":[55.0],
	 "objects":[{"type":"plant","x":170.0,"height":20.0,"stage":0}], "exit":430.0},
	{"name":"LIVING BRIDGE", "hint":"Grow the plant, align both lights, then use the cat shadow.", "kind":"exit",
	 "floors":[Vector2(20,135),Vector2(380,460)], "lights":[42.0,440.0],
	 "objects":[{"type":"plant","x":150.0,"height":20.0,"stage":0},{"type":"cat","x":250.0,"height":26.0,"min":220.0,"max":345.0,"speed":19.0,"dir":1.0},{"type":"box","x":365.0,"height":34.0}], "exit":430.0},
	{"name":"NO SHADOW FOR THE KING", "hint":"Place the two lamps on the glowing marks and press Enter.", "kind":"boss",
	 "floors":[Vector2(20,460)], "lights":[70.0,410.0],
	 "objects":[{"type":"boss","x":240.0,"height":82.0}], "targets":[205.0,275.0], "exit":430.0}
]

func _ready() -> void:
	rng.randomize()
	build_ui()
	show_menu()

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	title_label = Label.new()
	title_label.position = Vector2(40, 58)
	title_label.size = Vector2(400, 46)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 27)
	title_label.add_theme_color_override("font_color", GOLD)
	layer.add_child(title_label)
	info_label = Label.new()
	info_label.position = Vector2(62, 106)
	info_label.size = Vector2(356, 76)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(info_label)
	button = Button.new()
	button.position = Vector2(155, 201)
	button.size = Vector2(170, 36)
	button.pressed.connect(_on_button)
	layer.add_child(button)

func show_menu() -> void:
	state = State.MENU
	title_label.visible = true
	info_label.visible = true
	button.visible = true
	title_label.text = "SHADOW LANTERN"
	info_label.text = "Move light. Shape shadow. Create a road.\nPress Space to walk inside the world you made."
	button.text = "ENTER THE TOY HOUSE"
	queue_redraw()

func _on_button() -> void:
	if state == State.MENU or state == State.COMPLETE:
		level_index = 0
		start_level()
	elif state == State.LEVEL_CLEAR:
		level_index += 1
		start_level()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: switch_requested = true
			KEY_G: grow_requested = true
			KEY_R: restart_requested = true
			KEY_ENTER: seal_requested = true
			KEY_TAB: tab_requested = true
			KEY_P, KEY_ESCAPE: paused = not paused
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: switch_requested = true
		if event.button_index == JOY_BUTTON_Y: grow_requested = true
		if event.button_index == JOY_BUTTON_START: paused = not paused
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not in_shadow and state == State.PLAYING:
			dragging = nearest_light(event.position)
		else:
			dragging = -1
	elif event is InputEventMouseMotion and dragging >= 0 and not in_shadow:
		lights[dragging].x = clampf(event.position.x, 30.0, 450.0)

func nearest_light(at: Vector2) -> int:
	var best := -1
	var distance := 28.0
	for i in lights.size():
		var d: float = at.distance_to(Vector2(lights[i].x, 55.0))
		if d < distance:
			distance = d
			best = i
	if best >= 0: active_light = best
	return best

func start_level() -> void:
	state = State.PLAYING
	title_label.visible = false
	info_label.visible = false
	button.visible = false
	in_shadow = false
	real_x = 60.0
	shadow_x = real_x
	active_light = 0
	dragging = -1
	particles.clear()
	var data: Dictionary = levels[level_index]
	floors.clear()
	for floor in data.floors: floors.append(floor)
	lights.clear()
	for x in data.lights: lights.append({"x":x})
	objects.clear()
	for source in data.objects: objects.append(source.duplicate(true))
	show_message("LEVEL %d: %s" % [level_index + 1, data.name], 2.2)
	queue_redraw()

func _process(delta: float) -> void:
	update_particles(delta)
	if state != State.PLAYING:
		queue_redraw()
		return
	if paused:
		queue_redraw()
		return
	message_left = maxf(0.0, message_left - delta)
	if restart_requested:
		restart_requested = false
		start_level()
		return
	if tab_requested:
		tab_requested = false
		active_light = (active_light + 1) % lights.size()
		show_message("LAMP %d SELECTED" % [active_light + 1], 0.8)
	if grow_requested:
		grow_requested = false
		grow_plants()
	if switch_requested:
		switch_requested = false
		toggle_world()
	if seal_requested:
		seal_requested = false
		try_boss_seal()
	update_moving_objects(delta)
	if in_shadow:
		move_shadow(delta)
	else:
		move_active_light(delta)
	queue_redraw()

func move_active_light(delta: float) -> void:
	if lights.is_empty(): return
	var axis := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A): axis -= 1.0
	if Input.is_key_pressed(KEY_D): axis += 1.0
	if absf(axis) > 0.1:
		lights[active_light].x = clampf(lights[active_light].x + axis * 105.0 * delta, 30.0, 450.0)

func move_shadow(delta: float) -> void:
	var axis := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A): axis -= 1.0
	if Input.is_key_pressed(KEY_D): axis += 1.0
	axis = clampf(axis, -1.0, 1.0)
	if absf(axis) < 0.1: return
	var candidate := clampf(shadow_x + axis * 86.0 * delta, 20.0, 460.0)
	if is_walkable(candidate):
		shadow_x = candidate
	elif not is_walkable(shadow_x):
		fall_from_shadow()
	else:
		show_message("THE SHADOW ROAD ENDS HERE", 0.5)
	var exit_x: float = levels[level_index].exit
	if shadow_x >= exit_x - 8.0:
		real_x = exit_x
		in_shadow = false
		complete_level()

func toggle_world() -> void:
	if levels[level_index].kind == "boss":
		show_message("ALIGN BOTH LAMPS, THEN PRESS ENTER", 1.0)
		return
	if in_shadow:
		if on_floor(shadow_x):
			real_x = shadow_x
			in_shadow = false
			burst(Vector2(real_x, GROUND_Y - 15.0), GOLD)
			show_message("RETURNED TO REALITY", 0.8)
		else:
			show_message("YOU CAN ONLY RETURN ON SOLID GROUND", 1.0)
	else:
		shadow_x = real_x
		if is_walkable(shadow_x):
			in_shadow = true
			burst(Vector2(shadow_x, GROUND_Y - 7.0), MOON)
			show_message("SHADOW WORLD", 0.8)

func grow_plants() -> void:
	if in_shadow:
		show_message("PLANTS ONLY HEAR YOU IN REALITY", 1.0)
		return
	var grew := false
	for object in objects:
		if object.type == "plant" and object.stage < 3:
			object.stage += 1
			object.height = 20.0 + object.stage * 20.0
			burst(Vector2(object.x, GROUND_Y - object.height), Color("8cff9d"))
			grew = true
	if grew: show_message("THE PLANT GREW — ITS SHADOW IS LONGER", 1.2)
	else: show_message("NO PLANT CAN GROW FURTHER", 0.8)

func update_moving_objects(delta: float) -> void:
	for object in objects:
		if object.type == "cat":
			object.x += object.speed * object.dir * delta
			if object.x >= object.max:
				object.x = object.max
				object.dir = -1.0
			elif object.x <= object.min:
				object.x = object.min
				object.dir = 1.0
	if in_shadow and not is_walkable(shadow_x): fall_from_shadow()

func fall_from_shadow() -> void:
	in_shadow = false
	real_x = 60.0
	shadow_x = real_x
	show_message("THE SHADOW MOVED AWAY — TRY AGAIN", 1.4)
	burst(Vector2(shadow_x, GROUND_Y), PINK)

func shadow_segments() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for object in objects:
		for lamp in lights:
			var difference: float = object.x - lamp.x
			var direction := 1.0 if difference >= 0.0 else -1.0
			var length := clampf(absf(difference) * 0.82 + float(object.height) * 1.55, 24.0, 230.0)
			var end: float = object.x + direction * length
			result.append(Vector2(minf(object.x, end), maxf(object.x, end)))
	return merge_segments(result)

func merge_segments(source: Array[Vector2]) -> Array[Vector2]:
	if source.is_empty(): return []
	source.sort_custom(func(a, b): return a.x < b.x)
	var merged: Array[Vector2] = [source[0]]
	for i in range(1, source.size()):
		var current := source[i]
		var last := merged[-1]
		if current.x <= last.y + 3.0:
			merged[-1] = Vector2(last.x, maxf(last.y, current.y))
		else:
			merged.append(current)
	return merged

func on_floor(x: float) -> bool:
	for segment in floors:
		if x >= segment.x and x <= segment.y: return true
	return false

func is_walkable(x: float) -> bool:
	if on_floor(x): return true
	for segment in shadow_segments():
		if x >= segment.x and x <= segment.y: return true
	return false

func try_boss_seal() -> void:
	if levels[level_index].kind != "boss": return
	var targets: Array = levels[level_index].targets
	var correct := true
	for i in lights.size():
		if absf(lights[i].x - float(targets[i])) > 13.0: correct = false
	if correct:
		burst(Vector2(240, 120), GOLD, 40)
		complete_level()
	else:
		show_message("THE KING STILL HAS A SHADOW", 1.0)

func complete_level() -> void:
	state = State.LEVEL_CLEAR if level_index < levels.size() - 1 else State.COMPLETE
	title_label.visible = true
	info_label.visible = true
	button.visible = true
	if state == State.LEVEL_CLEAR:
		title_label.text = "ROOM AWAKENED"
		info_label.text = "%s solved.\nThe toy house opens another door." % levels[level_index].name
		button.text = "NEXT ROOM"
	else:
		title_label.text = "DAWN RETURNS"
		info_label.text = "With nowhere left to hide, the Shadow King dissolves.\nLight and darkness belong to the garden again."
		button.text = "PLAY AGAIN"

func show_message(text: String, duration: float) -> void:
	message = text
	message_left = duration

func burst(at: Vector2, color: Color, count := 14) -> void:
	for i in count:
		particles.append({"pos":at,"vel":Vector2.from_angle(rng.randf_range(0.0,TAU))*rng.randf_range(20.0,60.0),"life":rng.randf_range(0.5,1.0),"color":color})

func update_particles(delta: float) -> void:
	for p in particles:
		p.pos += p.vel * delta
		p.vel *= 0.95
		p.life -= delta
	for i in range(particles.size()-1,-1,-1):
		if particles[i].life <= 0.0: particles.remove_at(i)

func draw_lamp(x: float, selected: bool) -> void:
	var pos := Vector2(x,55)
	if selected: draw_circle(pos,18.0,Color(GOLD,0.18))
	draw_line(Vector2(x,25),Vector2(x,45),Color("9183ae"),2.0)
	draw_colored_polygon(PackedVector2Array([pos+Vector2(-11,-6),pos+Vector2(11,-6),pos+Vector2(7,6),pos+Vector2(-7,6)]),GOLD)
	draw_circle(pos+Vector2(0,7),4.0,Color("fff6ca"))

func draw_object(object: Dictionary) -> void:
	var x: float = object.x
	var height: float = object.height
	match object.type:
		"box":
			draw_rect(Rect2(x-11,GROUND_Y-height,22,height),Color("a66a55"))
			draw_rect(Rect2(x-11,GROUND_Y-height,22,height),Color("e5a978"),false,2.0)
		"cat":
			var c := Vector2(x,GROUND_Y-8)
			draw_circle(c,8.0,Color("181121"))
			draw_colored_polygon(PackedVector2Array([c+Vector2(-7,-3),c+Vector2(-5,-13),c+Vector2(-1,-7)]),Color("181121"))
			draw_colored_polygon(PackedVector2Array([c+Vector2(7,-3),c+Vector2(5,-13),c+Vector2(1,-7)]),Color("181121"))
			draw_circle(c+Vector2(-3,-1),1.2,GOLD)
			draw_circle(c+Vector2(3,-1),1.2,GOLD)
		"plant":
			draw_line(Vector2(x,GROUND_Y),Vector2(x,GROUND_Y-height),Color("65b86e"),4.0)
			var crown := Vector2(x,GROUND_Y-height)
			for angle in [0.0,1.25,2.5,3.75,5.0]: draw_circle(crown+Vector2.from_angle(angle)*9.0,7.0,Color("75d984"))
			draw_circle(crown,6.0,PINK)
		"boss":
			draw_colored_polygon(PackedVector2Array([Vector2(x-38,GROUND_Y),Vector2(x+38,GROUND_Y),Vector2(x+22,GROUND_Y-height),Vector2(x-22,GROUND_Y-height)]),Color("24152f"))
			draw_circle(Vector2(x,GROUND_Y-height),25.0,Color("24152f"))
			draw_circle(Vector2(x-9,GROUND_Y-height),3.0,PINK)
			draw_circle(Vector2(x+9,GROUND_Y-height),3.0,PINK)

func _draw() -> void:
	draw_rect(Rect2(0,0,W,H),BG)
	for i in 28: draw_circle(Vector2((i*79+13)%470,(i*43+21)%190),1.0,Color(0.6,0.7,1.0,0.2))
	if state != State.PLAYING:
		draw_rect(Rect2(52,44,376,170),Color("1e1938"))
		draw_circle(Vector2(99,73),27.0,Color("4b3974"))
		draw_circle(Vector2(111,66),25.0,BG)
		return
	var overlay := Color(0.02,0.015,0.07,0.48) if in_shadow else Color(0,0,0,0)
	# Light cones.
	if not in_shadow:
		for lamp in lights:
			draw_colored_polygon(PackedVector2Array([Vector2(lamp.x,65),Vector2(maxf(0,lamp.x-135),GROUND_Y),Vector2(minf(W,lamp.x+135),GROUND_Y)]),Color(1.0,0.88,0.48,0.08))
	# Floor and gaps.
	for floor in floors:
		draw_rect(Rect2(floor.x,GROUND_Y,floor.y-floor.x,18),Color("655071"))
		draw_line(Vector2(floor.x,GROUND_Y),Vector2(floor.y,GROUND_Y),Color("a98bb2"),2.0)
	for segment in shadow_segments():
		draw_rect(Rect2(segment.x,GROUND_Y-5,segment.y-segment.x,8),Color(SHADOW,0.95))
		draw_line(Vector2(segment.x,GROUND_Y-5),Vector2(segment.y,GROUND_Y-5),MOON if in_shadow else Color("34283e"),2.0)
	for i in lights.size(): draw_lamp(lights[i].x,i==active_light and not in_shadow)
	for object in objects: draw_object(object)
	if levels[level_index].kind == "boss":
		for target in levels[level_index].targets:
			draw_arc(Vector2(target,55),20.0,0.0,TAU,24,MOON,2.0)
	# Door.
	if levels[level_index].kind != "boss":
		var exit_x: float = levels[level_index].exit
		draw_rect(Rect2(exit_x-13,GROUND_Y-48,26,48),Color("6d467d"))
		draw_circle(Vector2(exit_x+7,GROUND_Y-24),2.0,GOLD)
	# Girl or her shadow.
	var px := shadow_x if in_shadow else real_x
	var body_color := Color("151020") if in_shadow else Color("8a63c4")
	draw_circle(Vector2(px,GROUND_Y-27),7.0,Color("1a1323") if in_shadow else Color("ffd8c4"))
	draw_colored_polygon(PackedVector2Array([Vector2(px-9,GROUND_Y),Vector2(px+9,GROUND_Y),Vector2(px,GROUND_Y-24)]),body_color)
	if in_shadow: draw_circle(Vector2(px,GROUND_Y-18),13.0,Color(MOON,0.12))
	draw_rect(Rect2(0,0,W,H),overlay)
	# HUD after overlay.
	draw_string(ThemeDB.fallback_font,Vector2(18,20),"ROOM %d/6  %s"%[level_index+1,levels[level_index].name],HORIZONTAL_ALIGNMENT_LEFT,-1,13,GOLD)
	draw_string(ThemeDB.fallback_font,Vector2(330,20),"SHADOW" if in_shadow else "REALITY",HORIZONTAL_ALIGNMENT_LEFT,-1,13,MOON if in_shadow else WHITE)
	draw_string(ThemeDB.fallback_font,Vector2(18,252),levels[level_index].hint,HORIZONTAL_ALIGNMENT_LEFT,450,11,Color("c6bbd5"))
	if message_left>0.0:
		draw_rect(Rect2(115,28,250,24),Color(0.03,0.02,0.08,0.9))
		draw_string(ThemeDB.fallback_font,Vector2(115,45),message,HORIZONTAL_ALIGNMENT_CENTER,250,11,GOLD)
	for p in particles: draw_circle(p.pos,2.0,Color(p.color,clampf(p.life,0.0,1.0)))
	if paused:
		draw_rect(Rect2(155,105,170,54),Color(0.03,0.02,0.08,0.94))
		draw_string(ThemeDB.fallback_font,Vector2(155,140),"PAUSED",HORIZONTAL_ALIGNMENT_CENTER,170,23,GOLD)

