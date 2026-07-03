extends Control

# Latency spike: gdcef v0.17.0 (CPU-OSR) on Godot 4.4.1.
# Measures touch-drag latency of a web page rendered to a Godot texture.
# The crosshair marks where Godot saw the pointer this frame; the visible gap
# between it and the page's puck is the webview pipeline's added latency.

const TEST_PAGE_SRC = "res://dragtest.html"
const TEST_PAGE_DST = "user://dragtest.html"

@onready var view: TextureRect = $view
@onready var url_edit: LineEdit = $topbar/hbox/url
@onready var hud: Label = $topbar/hbox/hud
@onready var fr_btn: Button = $topbar/hbox/fr
@onready var mode_btn: Button = $topbar/hbox/mode
@onready var crosshair: Node2D = $crosshair

var browser = null
var frame_rate: int = 60
# true = forward InputEventScreenTouch/Drag directly (production-representative);
# false = rely on Godot's emulate_mouse_from_touch synthesized mouse events
var touch_direct: bool = true
var mouse_pressed: bool = false
# forked dll exposes per-finger set_touch_down/move/up; stock dll does not
var has_touch_api: bool = false
var selftest: bool = false
var selftest_started: bool = false
# live fingers (index -> last position), so recreate/focus-loss can cancel them
var active_touches: Dictionary = {}

func _ready() -> void:
	selftest = OS.get_cmdline_args().has("--touch-selftest") || OS.get_cmdline_user_args().has("--touch-selftest")
	# raw per-event touch delivery instead of one merged move per frame
	Input.set_use_accumulated_input(false)
	_copy_test_page()
	# placeholder node = libgdcef.dll failed to load (usually missing MSVC runtime)
	if !$CEF.has_method("initialize"):
		hud.text = "gdcef DLL failed to load — install VC++ redist: aka.ms/vs/17/release/vc_redist.x64.exe"
		push_error("GDCef class missing: libgdcef.dll load failed (missing MSVCP140/VCRUNTIME140? install vc_redist.x64)")
		_fail_selftest("gdcef dll failed to load")
		return
	# --software falls back to SwiftShader if GPU OSR misbehaves on a machine
	var gpu = !OS.get_cmdline_args().has("--software")
	if !$CEF.initialize({
		"incognito": false,
		"locale": "en-US",
		"enable_gpu": gpu,
	}):
		hud.text = "CEF init FAILED: " + str($CEF.get_error())
		push_error($CEF.get_error())
		_fail_selftest("CEF initialize failed")
		return
	print("CEF version: " + $CEF.get_full_version())
	browser = await _create_browser(_test_page_url(), frame_rate)
	if browser != null:
		print("MULTITOUCH_API: " + str(browser.has_method("set_touch_down")))
	else:
		_fail_selftest("browser creation failed")
	_update_labels()

# selftest must exit 1 on broken boots, never hang for an unattended runner
func _fail_selftest(reason: String) -> void:
	if selftest:
		print("TOUCH_SELFTEST_FAIL: " + reason)
		get_tree().quit(1)

func _copy_test_page() -> void:
	var src = FileAccess.open(TEST_PAGE_SRC, FileAccess.READ)
	if src == null:
		push_error("dragtest.html missing")
		return
	var dst = FileAccess.open(TEST_PAGE_DST, FileAccess.WRITE)
	dst.store_string(src.get_as_text())
	dst.close()

func _test_page_url() -> String:
	var p = ProjectSettings.globalize_path(TEST_PAGE_DST)
	if p.begins_with("/"):
		return "file://" + p
	return "file:///" + p

func _create_browser(url: String, fps: int):
	# wait one frame so the TextureRect has its size
	await get_tree().process_frame
	var b = $CEF.create_browser(url, view, {
		"javascript": true,
		"webgl": true,
		"frame_rate": fps,
	})
	if b == null:
		hud.text = "create_browser FAILED: " + str($CEF.get_error())
		push_error($CEF.get_error())
		return null
	b.connect("on_page_loaded", _on_page_loaded)
	b.connect("on_page_failed_loading", _on_page_failed)
	b.resize(view.get_size())
	has_touch_api = b.has_method("set_touch_down")
	return b

func _on_page_loaded(b) -> void:
	url_edit.text = b.get_url()
	print("loaded: " + b.get_url())
	if selftest && !selftest_started:
		selftest_started = true
		_run_touch_selftest()

func _on_page_failed(err_code, err_msg, b) -> void:
	var html = "<html><body bgcolor=\"white\"><h2>Failed to load %s</h2><p>%s (%s)</p></body></html>" % [b.get_url(), err_msg, str(err_code)]
	b.load_data_uri(html, "text/html")

####
#### Touch selftest (--touch-selftest): 2-finger down/drag/up, verified via page title
####

func _run_touch_selftest() -> void:
	# give the page JS time to settle before injecting touches
	await get_tree().create_timer(1.0).timeout
	if !has_touch_api:
		print("TOUCH_SELFTEST_FAIL: no multitouch API")
		get_tree().quit(1)
		return
	browser.set_touch_down(0, 600, 500)
	browser.set_touch_down(1, 1200, 500)
	for i in range(10):
		await get_tree().process_frame
		browser.set_touch_move(0, 600 + i * 5, 500 + i * 3)
		browser.set_touch_move(1, 1200 - i * 5, 500 + i * 3)
	if !await _wait_for_title("touches:2"):
		return
	browser.set_touch_up(0, 645, 527)
	browser.set_touch_up(1, 1155, 527)
	if !await _wait_for_title("touches:0"):
		return
	print("TOUCH_SELFTEST_PASS")
	get_tree().quit(0)

func _wait_for_title(want: String) -> bool:
	var last = ""
	for i in range(180):
		await get_tree().process_frame
		last = str(browser.get_title())
		if last.contains(want):
			return true
	print("TOUCH_SELFTEST_FAIL: timed out waiting for title '%s', last title '%s'" % [want, last])
	get_tree().quit(1)
	return false

####
#### URL bar / buttons
####

func _navigate(url: String) -> void:
	if browser == null || url.strip_edges() == "":
		return
	var u = url.strip_edges()
	if !u.contains("://"):
		u = "https://" + u
	browser.load_url(u)
	url_edit.release_focus()

func _on_url_submitted(text: String) -> void:
	_navigate(text)

func _on_go_pressed() -> void:
	_navigate(url_edit.text)

func _on_testpage_pressed() -> void:
	if browser != null:
		browser.load_url(_test_page_url())
	url_edit.release_focus()

func _on_fr_pressed() -> void:
	_toggle_frame_rate()

func _on_mode_pressed() -> void:
	touch_direct = !touch_direct
	_update_labels()

func _toggle_frame_rate() -> void:
	frame_rate = 60 if frame_rate == 30 else 30
	var url = _test_page_url()
	if browser != null:
		url = browser.get_url()
		_cancel_all_touches()
		browser.close()
		browser = null
	browser = await _create_browser(url, frame_rate)
	_update_labels()

func _cancel_all_touches() -> void:
	if browser != null && has_touch_api:
		for idx in active_touches:
			browser.set_touch_cancel(idx)
	active_touches.clear()
	crosshair.clear_touches()

# a finger held across focus loss would stay pressed in CEF forever
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_all_touches()

func _update_labels() -> void:
	fr_btn.text = "FR:%d" % frame_rate
	mode_btn.text = "Input:Touch" if touch_direct else "Input:Emulated"

####
#### Input forwarding
####

func _on_view_gui_input(event) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
		else:
			active_touches.erase(event.index)
		# emulated mode: the synthesized mouse draws the single -1 ring instead
		if touch_direct:
			crosshair.set_finger(event.index, event.position, event.pressed)
		if browser == null || !touch_direct:
			return
		if has_touch_api:
			if event.pressed:
				browser.set_touch_down(event.index, event.position.x, event.position.y)
			elif event.canceled:
				browser.set_touch_cancel(event.index)
			else:
				browser.set_touch_up(event.index, event.position.x, event.position.y)
		else:
			# stock dll: collapse touches onto the mouse
			browser.set_mouse_moved(event.position.x, event.position.y)
			if event.pressed:
				browser.set_mouse_left_down()
			else:
				browser.set_mouse_left_up()
		return
	if event is InputEventScreenDrag:
		if active_touches.has(event.index):
			active_touches[event.index] = event.position
		if touch_direct:
			crosshair.set_finger(event.index, event.position, true)
		if browser == null || !touch_direct:
			return
		if has_touch_api:
			browser.set_touch_move(event.index, event.position.x, event.position.y)
		else:
			browser.set_mouse_moved(event.position.x, event.position.y)
		return
	if browser == null:
		return
	if event is InputEventMouseButton:
		# in touch-direct mode, drop the synthesized mouse to avoid double-forwarding
		if touch_direct && event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			browser.set_mouse_wheel_vertical(2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			browser.set_mouse_wheel_vertical(-2)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			mouse_pressed = event.pressed
			crosshair.set_finger(-1, event.position, event.pressed)
			if mouse_pressed:
				browser.set_mouse_left_down()
			else:
				browser.set_mouse_left_up()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				browser.set_mouse_right_down()
			else:
				browser.set_mouse_right_up()
	elif event is InputEventMouseMotion:
		if touch_direct && event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		crosshair.set_finger(-1, event.position, mouse_pressed)
		if mouse_pressed:
			browser.set_mouse_left_down()
		browser.set_mouse_moved(event.position.x, event.position.y)

func _on_view_resized() -> void:
	if browser != null:
		browser.resize(view.get_size())

func _input(event) -> void:
	if event is InputEventKey && event.pressed && !event.echo:
		match event.keycode:
			KEY_F1:
				_on_mode_pressed()
				return
			KEY_F2:
				_toggle_frame_rate()
				return
			KEY_F3:
				crosshair.visible = !crosshair.visible
				return
			KEY_F11:
				_toggle_fullscreen()
				return
			KEY_ESCAPE:
				get_tree().quit()
				return
	if browser == null || url_edit.has_focus():
		return
	if event is InputEventKey:
		browser.set_key_pressed(
			event.unicode if event.unicode != 0 else event.keycode,
			event.pressed, event.shift_pressed, event.alt_pressed,
			event.is_command_or_control_pressed())

func _toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	hud.text = " %d fps | %d fingers | F1 input F2 fr F3 xhair F11 fs Esc quit" % [Engine.get_frames_per_second(), crosshair.down_count()]
