#+build js
package platform

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"
import "core:strings"
import js "core:sys/wasm/js"
import "src:core/events"
import "src:core/render"
import webgl "vendor:wasm/WebGL"

WEB_RELEASE :: 0
WEB_PRESS   :: 1
WEB_REPEAT  :: 2

@(private = "file")
DEFAULT_CANVAS :: "banana-canvas"

@(private = "file")
Web_State :: struct {
	canvas:    string,
	allocator: runtime.Allocator,
	window:    ^Window,
	closed:    bool,
	listening: bool,
	clipboard: string,
}

@(private = "file")
_active: ^Web_State

@(private = "file")
_state_size :: proc() -> int { return size_of(Web_State) }

@(private = "file")
_set_active_state :: proc(state: rawptr) {
	_active = cast(^Web_State)(state)
}

@(private = "file")
_init :: proc(
	state: rawptr,
	opts: Init_Options,
	allocator: runtime.Allocator,
) -> render.Render_Interface {
	_active = cast(^Web_State)(state)
	_active^ = {}
	_active.allocator = allocator
	canvas := opts.canvas
	if canvas == "" do canvas = DEFAULT_CANVAS
	_active.canvas = strings.clone(canvas, allocator)

	_poll_size()
	_set_title(string(opts.title))

	return render.Render_Interface {
		state            = state,
		make_context     = _make_context,
		make_current     = _make_current,
		present          = _present,
		resize           = _resize,
		destroy          = _destroy,
		get_proc_address = _get_proc_address,
	}
}

@(private = "file")
_shutdown :: proc() {
	if _active == nil do return
	_remove_listeners(_active)
	delete(_active.canvas, _active.allocator)
	delete(_active.clipboard, _active.allocator)
	_active^ = {}
}

@(private = "file")
_should_close :: proc() -> bool {
	return _active == nil || _active.closed
}

@(private = "file")
_poll_events :: proc() {
	// Browser events are delivered directly by the JavaScript event loop.
}

@(private = "file")
_poll_size :: proc() -> (int, int) {
	if _active == nil do return 0, 0
	rect := js.get_bounding_client_rect(_active.canvas)
	scale := _content_scale()
	w := int(rect.width * f64(scale))
	h := int(rect.height * f64(scale))
	// Assigning canvas.width/height clears its drawing buffer, even when the
	// value is unchanged, so only touch the properties on an actual resize.
	if int(js.get_element_key_f64(_active.canvas, "width")) != w {
		js.set_element_key_f64(_active.canvas, "width", f64(w))
	}
	if int(js.get_element_key_f64(_active.canvas, "height")) != h {
		js.set_element_key_f64(_active.canvas, "height", f64(h))
	}
	return w, h
}

@(private = "file")
_content_scale :: proc() -> f32 {
	scale := f32(js.device_pixel_ratio())
	return scale > 0 ? scale : 1
}

@(private = "file")
_request_close :: proc() {
	if _active != nil do _active.closed = true
}

@(private = "file")
_set_title :: proc(title: string) {
	js.set_document_title(title)
}

@(private = "file")
_set_window_user_ptr :: proc(state: rawptr, ptr: rawptr) {
	s := cast(^Web_State)(state)
	_active = s
	_remove_listeners(s)
	s.window = cast(^Window)(ptr)
	if s.window == nil do return

	// Pointer events cover mouse, pen, and touch while retaining browser button
	// numbering (left=0, middle=1, right=2), the same numbering GLFW uses.
	js.add_event_listener(s.canvas, .Pointer_Move, ptr, _pointer_callback)
	js.add_event_listener(s.canvas, .Pointer_Down, ptr, _pointer_callback)
	js.add_event_listener(s.canvas, .Pointer_Up, ptr, _pointer_callback)
	js.add_event_listener(s.canvas, .Wheel, ptr, _wheel_callback)
	js.add_window_event_listener(.Key_Down, ptr, _key_callback)
	js.add_window_event_listener(.Key_Up, ptr, _key_callback)
	js.add_window_event_listener(.Key_Press, ptr, _key_callback)
	js.add_window_event_listener(.Resize, ptr, _resize_callback)
	s.listening = true
}

@(private = "file")
_remove_listeners :: proc(s: ^Web_State) {
	if s == nil || !s.listening || s.window == nil do return
	ptr := cast(rawptr)(s.window)
	js.remove_event_listener(s.canvas, .Pointer_Move, ptr, _pointer_callback)
	js.remove_event_listener(s.canvas, .Pointer_Down, ptr, _pointer_callback)
	js.remove_event_listener(s.canvas, .Pointer_Up, ptr, _pointer_callback)
	js.remove_event_listener(s.canvas, .Wheel, ptr, _wheel_callback)
	js.remove_window_event_listener(.Key_Down, ptr, _key_callback)
	js.remove_window_event_listener(.Key_Up, ptr, _key_callback)
	js.remove_window_event_listener(.Key_Press, ptr, _key_callback)
	js.remove_window_event_listener(.Resize, ptr, _resize_callback)
	s.listening = false
	s.window = nil
}

@(private = "file")
_pointer_callback :: proc(e: js.Event) {
	w := cast(^Window)(e.user_data)
	if w == nil do return
	x, y := f32(e.mouse.offset.x), f32(e.mouse.offset.y)
	w.input.mouse_x, w.input.mouse_y = x, y
	#partial switch e.kind {
	case .Pointer_Move:
		_push_event(w, MOUSE_MOVED{x = x, y = y})
	case .Pointer_Down:
		_push_event(w, MOUSE_BUTTON{
			button = int(e.mouse.button),
			action = WEB_PRESS,
			mods   = _web_mods(e),
			x      = x,
			y      = y,
		})
	case .Pointer_Up:
		_push_event(w, MOUSE_BUTTON{
			button = int(e.mouse.button),
			action = WEB_RELEASE,
			mods   = _web_mods(e),
			x      = x,
			y      = y,
		})
	}
}

@(private = "file")
_wheel_callback :: proc(e: js.Event) {
	w := cast(^Window)(e.user_data)
	if w == nil do return
	dx := -f32(e.wheel.delta.x)
	dy := -f32(e.wheel.delta.y)
	#partial switch e.wheel.delta_mode {
	case .Pixel:
	case .Line:
		dx *= 100.0 / 3.0
		dy *= 100.0 / 3.0
	case .Page:
		scale := w.scale if w.scale > 0 else 1
		dx *= f32(w.width) / scale * 0.875
		dy *= f32(w.height) / scale * 0.875
	}
	_push_event(w, MOUSE_WHEEL{
		dx = dx,
		dy = dy,
		x  = w.input.mouse_x,
		y  = w.input.mouse_y,
	})
	js.event_prevent_default()
}

@(private = "file")
_key_callback :: proc(e: js.Event) {
	w := cast(^Window)(e.user_data)
	if w == nil do return
	if e.kind == .Key_Press {
		if e.key.char != 0 do _push_event(w, TYPED{codepoint = e.key.char})
		return
	}
	action := WEB_RELEASE
	if e.kind == .Key_Down {
		action = e.key.repeat ? WEB_REPEAT : WEB_PRESS
	}

	mods := _web_mods(e)
	code := _map_web_key(e.key.code)
	_push_event(w, KEY {
		code     = code,
		key      = _key_rune(e),
		scancode = 0,
		action   = action,
		mods     = mods,
	})

	// Stop the browser from scrolling (Space, arrows, paging keys) or moving
	// focus off the canvas (Tab), but leave Ctrl/Cmd shortcuts and F-keys to
	// the browser.
	#partial switch code {
	case .Tab, .Space, .Left, .Right, .Up, .Down, .Page_Up, .Page_Down,
	     .Home, .End, .Backspace, .Apostrophe, .Slash:
		if !e.key.ctrl && !e.key.meta do js.event_prevent_default()
	}
}

@(private="file")
_key_rune :: proc(e: js.Event) -> rune {
	buf := e.key._key_buf
	r, size := utf8.decode_rune(buf[:])
	if r == utf8.RUNE_ERROR do return 0
	if size < len(buf) && buf[size] != 0 do return 0 // multi-char key name
	return r
}

@(private = "file")
_resize_callback :: proc(e: js.Event) {
	w := cast(^Window)(e.user_data)
	if w != nil do refresh(w)
}

@(private = "file")
_web_mods :: proc(e: js.Event) -> events.Mods {
	mods: events.Mods
	#partial switch e.kind {
	case .Key_Down, .Key_Up, .Key_Press:
		if e.key.shift do mods += {.Shift}
		if e.key.ctrl  do mods += {.Ctrl}
		if e.key.alt   do mods += {.Alt}
		if e.key.meta  do mods += {.Super}
	case .Pointer_Down, .Pointer_Up, .Pointer_Move:
		if e.mouse.shift do mods += {.Shift}
		if e.mouse.ctrl  do mods += {.Ctrl}
		if e.mouse.alt   do mods += {.Alt}
		if e.mouse.meta  do mods += {.Super}
	}
	return mods
}

@(private = "file")
_map_web_key :: proc(code: string) -> events.Key {
	Key :: events.Key
	if len(code) == 4 && code[:3] == "Key" && code[3] >= 'A' && code[3] <= 'Z' {
		return Key.A + Key(code[3] - 'A')
	}
	if len(code) == 6 && code[:5] == "Digit" && code[5] >= '0' && code[5] <= '9' {
		return Key.N0 + Key(code[5] - '0')
	}
	switch code {
	case "Space":        return .Space
	case "Quote":        return .Apostrophe
	case "Comma":        return .Comma
	case "Minus":        return .Minus
	case "Period":       return .Period
	case "Slash":        return .Slash
	case "Semicolon":    return .Semicolon
	case "Equal":        return .Equal
	case "BracketLeft":  return .Left_Bracket
	case "Backslash":    return .Backslash
	case "BracketRight": return .Right_Bracket
	case "Backquote":    return .Grave
	case "Escape":       return .Escape
	case "Enter":        return .Enter
	case "Tab":          return .Tab
	case "Backspace":    return .Backspace
	case "Insert":       return .Insert
	case "Delete":       return .Delete
	case "ArrowRight":   return .Right
	case "ArrowLeft":    return .Left
	case "ArrowDown":    return .Down
	case "ArrowUp":      return .Up
	case "PageUp":       return .Page_Up
	case "PageDown":     return .Page_Down
	case "Home":         return .Home
	case "End":          return .End
	case "CapsLock":     return .Caps_Lock
	case "ScrollLock":   return .Scroll_Lock
	case "NumLock":      return .Num_Lock
	case "PrintScreen":  return .Print_Screen
	case "Pause":        return .Pause
	case "F1":           return .F1
	case "F2":           return .F2
	case "F3":           return .F3
	case "F4":           return .F4
	case "F5":           return .F5
	case "F6":           return .F6
	case "F7":           return .F7
	case "F8":           return .F8
	case "F9":           return .F9
	case "F10":          return .F10
	case "F11":          return .F11
	case "F12":          return .F12
	case "Numpad0":      return .KP_0
	case "Numpad1":      return .KP_1
	case "Numpad2":      return .KP_2
	case "Numpad3":      return .KP_3
	case "Numpad4":      return .KP_4
	case "Numpad5":      return .KP_5
	case "Numpad6":      return .KP_6
	case "Numpad7":      return .KP_7
	case "Numpad8":      return .KP_8
	case "Numpad9":      return .KP_9
	case "NumpadDecimal":  return .KP_Decimal
	case "NumpadDivide":   return .KP_Divide
	case "NumpadMultiply": return .KP_Multiply
	case "NumpadSubtract": return .KP_Subtract
	case "NumpadAdd":      return .KP_Add
	case "NumpadEnter":    return .KP_Enter
	case "NumpadEqual":    return .KP_Equal
	case "ShiftLeft":    return .Left_Shift
	case "ControlLeft":  return .Left_Ctrl
	case "AltLeft":      return .Left_Alt
	case "MetaLeft":     return .Left_Super
	case "ShiftRight":   return .Right_Shift
	case "ControlRight": return .Right_Ctrl
	case "AltRight":     return .Right_Alt
	case "MetaRight":    return .Right_Super
	case "ContextMenu":  return .Menu
	}
	return .Unknown
}

@(private = "file")
_clipboard_get :: proc(allocator: runtime.Allocator) -> string {
	// The browser Clipboard API is asynchronous while Platform_Interface is synchronous.
    // NOTE: bug later for sure
	if _active == nil do return ""
	return strings.clone(_active.clipboard, allocator)
}

@(private = "file")
_clipboard_set :: proc(text: string) {
	if _active == nil do return
	delete(_active.clipboard, _active.allocator)
	_active.clipboard = strings.clone(text, _active.allocator)
}

@(private = "file")
_make_context :: proc(state: rawptr, opts: render.Init_Options) -> bool {
	s := cast(^Web_State)(state)
	attrs := webgl.ContextAttributes{.stencil}
	if opts.msaa_samples <= 1 do attrs += {.disableAntialias}
	return webgl.CreateCurrentContextById(s.canvas, attrs)
}

@(private = "file")
_make_current :: proc(state: rawptr) {
	s := cast(^Web_State)(state)
	webgl.SetCurrentContextById(s.canvas)
}

@(private = "file")
_present :: proc(state: rawptr) {
	// WebGL presents when control returns to the browser.
}

@(private = "file")
_resize :: proc(state: rawptr, w, h: i32) {
	s := cast(^Web_State)(state)
	if i32(js.get_element_key_f64(s.canvas, "width")) != w {
		js.set_element_key_f64(s.canvas, "width", f64(w))
	}
	if i32(js.get_element_key_f64(s.canvas, "height")) != h {
		js.set_element_key_f64(s.canvas, "height", f64(h))
	}
}

@(private = "file")
_destroy :: proc(state: rawptr) {}

@(private = "file")
_get_proc_address :: proc(state: rawptr, name: cstring) -> rawptr {
	return nil
}

PLATFORM_WEB :: Platform_Interface {
	state_size          = _state_size,
	set_active_state    = _set_active_state,
	init                = _init,
	shutdown            = _shutdown,
	should_close        = _should_close,
	poll_events         = _poll_events,
	poll_size           = _poll_size,
	content_scale       = _content_scale,
	request_close       = _request_close,
	set_title           = _set_title,
	set_window_user_ptr = _set_window_user_ptr,
	clipboard_get       = _clipboard_get,
	clipboard_set       = _clipboard_set,
}
