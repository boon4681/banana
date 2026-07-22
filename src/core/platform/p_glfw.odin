#+build !js
package platform

import "base:runtime"
import "core:c"
import "core:strings"
import "src:core/render"
import "src:core/events"
import glfw "vendor:glfw"

@(private = "file")
GLFW_State :: struct {
    handle: glfw.WindowHandle,
    visible: bool
}

GLFW_RELEASE :: glfw.RELEASE
GLFW_PRESS   :: glfw.PRESS
GLFW_REPEAT  :: glfw.REPEAT

@(private = "file", thread_local)
_active: ^GLFW_State // active state for one thread multiple windows

@(private = "file")
_live_windows: int // counter for internal

@(private = "file")
_state_size :: proc() -> int {return size_of(GLFW_State)}

@(private = "file")
_set_active_state :: proc(state: rawptr) {
    _active = cast(^GLFW_State)(state)
}

@(private = "file")
_init :: proc(
	state: rawptr,
	opts: Init_Options,
	allocator: runtime.Allocator,
) -> render.Render_Interface {
    _active = cast(^GLFW_State)(state)
    _active^ = {}

    if !glfw.Init() do panic("window glfw: Init failed")
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1)
    glfw.WindowHint(glfw.SAMPLES, i32(opts.msaa_samples))
    _active.visible = false
    glfw.WindowHint(glfw.VISIBLE, 0)
    _active.handle = glfw.CreateWindow(i32(opts.width), i32(opts.height), opts.title, nil, nil)
    if _active.handle == nil do panic("window glfw: CreateWindow failed")
    _live_windows += 1

    return render.Render_Interface {
        state            = cast(rawptr)(_active.handle),
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
    if _active == nil || _active.handle == nil do return
    glfw.SetWindowUserPointer(_active.handle, nil)
    glfw.SetWindowRefreshCallback(_active.handle, nil)
    glfw.SetCursorPosCallback(_active.handle, nil)
    glfw.SetMouseButtonCallback(_active.handle, nil)
    glfw.SetScrollCallback(_active.handle, nil)
    glfw.SetKeyCallback(_active.handle, nil)
    glfw.SetCharCallback(_active.handle, nil)
    glfw.MakeContextCurrent(nil)
    glfw.DestroyWindow(_active.handle)
    _active.handle = nil
    _live_windows -= 1
    if _live_windows == 0 do glfw.Terminate()
}

@(private = "file")
_should_close :: proc() -> bool {
    if _active == nil || _active.handle == nil do panic("doesn have active glfw window")
    return cast(bool)(glfw.WindowShouldClose(_active.handle))
}

@(private = "file")
_poll_events :: proc() {
    glfw.PollEvents()
}

@(private = "file")
_poll_size :: proc() -> (int, int) {
    w, h := glfw.GetFramebufferSize(_active.handle)
    return int(w), int(h)
}

@(private = "file")
_content_scale :: proc() -> f32 {
    sx, _ := glfw.GetWindowContentScale(_active.handle)
    return sx > 0 ? sx : 1
}

@(private = "file")
_request_close :: proc() {
    glfw.SetWindowShouldClose(_active.handle, true)
}

@(private = "file")
_set_title :: proc(title: string) {
    cs := strings.clone_to_cstring(title, context.temp_allocator)
    glfw.SetWindowTitle(_active.handle, cs)
}

@(private = "file")
_set_window_user_ptr :: proc(state: rawptr, ptr: rawptr) {
    _active = cast(^GLFW_State)(state)
    glfw.SetWindowUserPointer(_active.handle, ptr)
    glfw.SetWindowRefreshCallback(_active.handle, _refresh_callback)
    glfw.SetCursorPosCallback(_active.handle, _cursor_pos_callback)
    glfw.SetMouseButtonCallback(_active.handle, _mouse_button_callback)
    glfw.SetScrollCallback(_active.handle, _scroll_callback)
    glfw.SetKeyCallback(_active.handle, _key_callback)
    glfw.SetCharCallback(_active.handle, _char_callback)
}

@(private="file")
_key_callback :: proc "c" (handle: glfw.WindowHandle, key, scancode, action, mods: c.int) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w == nil do return
    _push_event(w, KEY{
        code     = _map_key(key),
        key      = _key_char(key, scancode),
        scancode = int(scancode),
        action   = int(action),
        mods     = _map_mods(mods),
    })
}

@(private="file")
_key_char :: proc(key, scancode: c.int) -> rune {
    name := glfw.GetKeyName(key, scancode)
    if len(name) == 0 do return 0
    for r in name do return r
    return 0
}

@(private="file")
_map_mods :: proc "contextless" (mods: c.int) -> events.Mods {
    out: events.Mods
    if mods & glfw.MOD_SHIFT != 0     do out += {.Shift}
    if mods & glfw.MOD_CONTROL != 0   do out += {.Ctrl}
    if mods & glfw.MOD_ALT != 0       do out += {.Alt}
    if mods & glfw.MOD_SUPER != 0     do out += {.Super}
    if mods & glfw.MOD_CAPS_LOCK != 0 do out += {.Caps_Lock}
    if mods & glfw.MOD_NUM_LOCK != 0  do out += {.Num_Lock}
    return out
}

@(private="file")
_map_key :: proc "contextless" (key: c.int) -> events.Key {
    Key :: events.Key
    switch key {
    case glfw.KEY_A ..= glfw.KEY_Z:      return Key.A + Key(key - glfw.KEY_A)
    case glfw.KEY_0 ..= glfw.KEY_9:      return Key.N0 + Key(key - glfw.KEY_0)
    case glfw.KEY_F1 ..= glfw.KEY_F12:   return Key.F1 + Key(key - glfw.KEY_F1)
    case glfw.KEY_KP_0 ..= glfw.KEY_KP_9: return Key.KP_0 + Key(key - glfw.KEY_KP_0)
    case glfw.KEY_SPACE:         return .Space
    case glfw.KEY_APOSTROPHE:    return .Apostrophe
    case glfw.KEY_COMMA:         return .Comma
    case glfw.KEY_MINUS:         return .Minus
    case glfw.KEY_PERIOD:        return .Period
    case glfw.KEY_SLASH:         return .Slash
    case glfw.KEY_SEMICOLON:     return .Semicolon
    case glfw.KEY_EQUAL:         return .Equal
    case glfw.KEY_LEFT_BRACKET:  return .Left_Bracket
    case glfw.KEY_BACKSLASH:     return .Backslash
    case glfw.KEY_RIGHT_BRACKET: return .Right_Bracket
    case glfw.KEY_GRAVE_ACCENT:  return .Grave
    case glfw.KEY_ESCAPE:        return .Escape
    case glfw.KEY_ENTER:         return .Enter
    case glfw.KEY_TAB:           return .Tab
    case glfw.KEY_BACKSPACE:     return .Backspace
    case glfw.KEY_INSERT:        return .Insert
    case glfw.KEY_DELETE:        return .Delete
    case glfw.KEY_RIGHT:         return .Right
    case glfw.KEY_LEFT:          return .Left
    case glfw.KEY_DOWN:          return .Down
    case glfw.KEY_UP:            return .Up
    case glfw.KEY_PAGE_UP:       return .Page_Up
    case glfw.KEY_PAGE_DOWN:     return .Page_Down
    case glfw.KEY_HOME:          return .Home
    case glfw.KEY_END:           return .End
    case glfw.KEY_CAPS_LOCK:     return .Caps_Lock
    case glfw.KEY_SCROLL_LOCK:   return .Scroll_Lock
    case glfw.KEY_NUM_LOCK:      return .Num_Lock
    case glfw.KEY_PRINT_SCREEN:  return .Print_Screen
    case glfw.KEY_PAUSE:         return .Pause
    case glfw.KEY_KP_DECIMAL:    return .KP_Decimal
    case glfw.KEY_KP_DIVIDE:     return .KP_Divide
    case glfw.KEY_KP_MULTIPLY:   return .KP_Multiply
    case glfw.KEY_KP_SUBTRACT:   return .KP_Subtract
    case glfw.KEY_KP_ADD:        return .KP_Add
    case glfw.KEY_KP_ENTER:      return .KP_Enter
    case glfw.KEY_KP_EQUAL:      return .KP_Equal
    case glfw.KEY_LEFT_SHIFT:    return .Left_Shift
    case glfw.KEY_LEFT_CONTROL:  return .Left_Ctrl
    case glfw.KEY_LEFT_ALT:      return .Left_Alt
    case glfw.KEY_LEFT_SUPER:    return .Left_Super
    case glfw.KEY_RIGHT_SHIFT:   return .Right_Shift
    case glfw.KEY_RIGHT_CONTROL: return .Right_Ctrl
    case glfw.KEY_RIGHT_ALT:     return .Right_Alt
    case glfw.KEY_RIGHT_SUPER:   return .Right_Super
    case glfw.KEY_MENU:          return .Menu
    }
    return .Unknown
}

@(private="file")
_char_callback :: proc "c" (handle: glfw.WindowHandle, codepoint: rune) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w == nil do return
    _push_event(w, TYPED{codepoint = codepoint})
}

@(private="file")
_clipboard_get :: proc(allocator: runtime.Allocator) -> string {
    s := glfw.GetClipboardString(_active.handle)
    return strings.clone(string(s), allocator)
}

@(private="file")
_clipboard_set :: proc(text: string) {
    cs := strings.clone_to_cstring(text, context.temp_allocator)
    glfw.SetClipboardString(_active.handle, cs)
}

@(private="file")
_refresh_callback :: proc "c" (handle: glfw.WindowHandle) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w != nil do refresh(w)
}

@(private="file")
_cursor_pos_callback :: proc "c" (handle: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w == nil do return
    fb_w, fb_h := glfw.GetFramebufferSize(handle)
    win_w, win_h := glfw.GetWindowSize(handle)
    sx := win_w > 0 ? f32(fb_w) / f32(win_w) : 1.0
    sy := win_h > 0 ? f32(fb_h) / f32(win_h) : 1.0
    // Divide out the content scale so hit-testing matches node rects.
    cs, _ := glfw.GetWindowContentScale(handle)
    if cs <= 0 do cs = 1
    w.input.mouse_x = f32(xpos) * sx / cs
    w.input.mouse_y = f32(ypos) * sy / cs
    _push_event(w, MOUSE_MOVED {
        x = w.input.mouse_x,
        y = w.input.mouse_y
    })
}

@(private="file")
_mouse_button_callback :: proc "c" (handle: glfw.WindowHandle, button, action, mods: c.int) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w == nil do return
    _push_event(w, MOUSE_BUTTON {
        button = int(button),
        action = int(action),
        mods   = _map_mods(mods),
        x      = w.input.mouse_x,
        y      = w.input.mouse_y,
    })
}

@(private="file")
_scroll_callback :: proc "c" (handle: glfw.WindowHandle, dx, dy: f64) {
    context = runtime.default_context()
    w := cast(^Window)(glfw.GetWindowUserPointer(handle))
    if w == nil do return
    _push_event(w, MOUSE_WHEEL{
        dx = f32(dx),
        dy = f32(dy),
        x  = w.input.mouse_x,
        y  = w.input.mouse_y
    })
}

@(private="file")
_make_context :: proc(state: rawptr, opts: render.Init_Options) -> bool {
    glfw.MakeContextCurrent(cast(glfw.WindowHandle)(state))
    glfw.SwapInterval(opts.vsync ? 1 : 0)
    return true
}

@(private="file")
_make_current :: proc(state: rawptr) {
    glfw.MakeContextCurrent(cast(glfw.WindowHandle)(state))
}

@(private="file")
_present :: proc(state: rawptr) {
    glfw.SwapBuffers(cast(glfw.WindowHandle)(state))
    if _active.visible == false {
        glfw.ShowWindow(cast(glfw.WindowHandle)(state)) 
        _active.visible = true
    }
}

@(private="file")
_resize :: proc(state: rawptr, w, h: i32) {}

@(private="file")
_destroy :: proc(state: rawptr) {}

@(private="file")
_get_proc_address :: proc(state: rawptr, name: cstring) -> rawptr {
    return glfw.GetProcAddress(name)
}

PLATFORM_GLFW :: Platform_Interface{
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
