package platform

import "base:runtime"
import "src:core/common"
import "src:core/eventloop"
import "src:core/node"
import "src:core/painter"
import "src:core/input"
import "src:core/hit_test"
import "src:core/events"
import "src:core/render"

Window_On_Proc :: proc(
    w: ^Window,
    type: string,
    callback: events.Callback,
    capture := false,
    once := false,
) -> uint

Window_Off_Proc :: proc(w: ^Window, type: string, callback: events.Callback)

// Context holder for platform; similar to application context
Window :: struct {
    platform_state: rawptr,
    renderer_state: rawptr,
    painter_state:  rawptr,
    painter:        painter.Painter,
    images:         [dynamic]^render.Image,
    allocator:      runtime.Allocator,
    root:           ^node.Node,
    bus:            events.Bus,
    loop:           ^eventloop.Loop,
    frame:          rawptr, // native frame, use rawptr cuz cyclic import
    width:          int,
    height:         int,
    scale:          f32,
    awaken:         bool,
    // Application-owned callback context. Window never frees this pointer.
    state:      rawptr,
    on_refresh: proc(w: ^Window),
    on:         Window_On_Proc,
    off:        Window_Off_Proc,
    input:      input.Input_State,
    queue:      [dynamic]EVENT,
}

@(private, thread_local)
_active_window: ^Window

New :: proc(opts: Init_Options = DEFAULT_OPTIONS) -> ^Window {
    w := new(Window)
    w.allocator = context.allocator
    w.width = opts.width
    w.height = opts.height
    w.scale = 1
    w.queue = make([dynamic]EVENT)
    w.images = make([dynamic]^render.Image, w.allocator)
    events.bus_init(&w.bus)
    w.loop = eventloop.create(w.allocator)
    w.on = _window_on
    w.off = _window_off

    w.platform_state = PLATFORM.create_state(context.allocator)
    PLATFORM.set_active_state(w.platform_state)
    glue := PLATFORM.init(w.platform_state, opts, context.allocator)

    w.renderer_state = render.RENDERER.create_state(context.allocator)
    render.RENDERER.set_active_state(w.renderer_state)
    render.RENDERER.init(
        w.renderer_state,
        glue,
        opts.width,
        opts.height,
        {vsync = opts.vsync, msaa_samples = max(opts.msaa_samples, 1)},
        context.allocator,
    )

    w.painter_state = painter.create_state(context.allocator)
    w.painter = painter.Painter{state = w.painter_state}
    painter.init(w.painter, context.allocator)

    w.scale = PLATFORM.content_scale()

    w.root = node.New()
    input.init(&w.input, w.root, &w.bus, w)
    input.set_clipboard_procs({get = PLATFORM.clipboard_get, set = PLATFORM.clipboard_set})
    PLATFORM.set_window_user_ptr(w.platform_state, cast(rawptr)(w))
    return w
}

@(private)
_push_event :: proc(w: ^Window, ev: EVENT) {
    if w != nil do append(&w.queue, ev)
}

handle :: proc(w: ^Window, ev: EVENT) {
    #partial switch e in ev {
    case MOUSE_MOVED:
        input.on_mouse_move(&w.input, e.x, e.y)
    case MOUSE_LEFT:
        input.on_mouse_leave(&w.input)
    case MOUSE_BUTTON:
        if e.action == PRESS {
            input.on_mouse_down(&w.input, e.button, e.mods)
        } else if e.action == RELEASE {
            input.on_mouse_up(&w.input, e.button)
        }
    case MOUSE_WHEEL:
        input.on_wheel(&w.input, e.dx, e.dy)
    case KEY:
        if e.action == PRESS || e.action == REPEAT {
            input.on_key_down(&w.input, e.code, e.key, e.mods, e.action == REPEAT)
        } else if e.action == RELEASE {
            input.on_key_up(&w.input, e.code, e.key, e.mods)
        }
    case TYPED:
        input.on_text(&w.input, e.codepoint)
    case FOCUS_CHANGED:
        event_type := events.WINDOW_FOCUS_EVENT if e.focused else events.WINDOW_BLUR_EVENT
        _emit_window(w, event_type)
    }
}

update :: proc(w: ^Window) -> bool {
    make_current(w)
    if !_continue_after_close_request(w) do return false
    poll_start := common.profile_begin(.Poll)
    PLATFORM.poll_events()
    common.profile_end(.Poll, poll_start)

    if !_continue_after_close_request(w) do return false
    sync_size(w)
    input.set_context(&w.input)

    hit_test.invalidate()
    dispatch_start := common.profile_begin(.Dispatch)
    for ev, i in w.queue {
        if _, is_move := ev.(MOUSE_MOVED); is_move && i + 1 < len(w.queue) {
            if _, next_is_move := w.queue[i + 1].(MOUSE_MOVED); next_is_move do continue
        }
        handle(w, ev)
    }
    clear(&w.queue)
    sync_click_through(w)
    common.profile_end(.Dispatch, dispatch_start)
    return true
}

// block window from closing if the app refuse to close
// this got report from application layer via event bubble
@(private = "file")
_continue_after_close_request :: proc(w: ^Window) -> bool {
    if !PLATFORM.should_close() do return true
    close_request := _emit_window(w, events.WINDOW_CLOSE_REQUEST_EVENT)
    if !close_request.cancelled do return false
    PLATFORM.cancel_close()
    return true
}

make_current :: proc(w: ^Window) {
    _active_window = w
    input.set_context(&w.input)
    PLATFORM.set_active_state(w.platform_state)
    render.RENDERER.set_active_state(w.renderer_state)
    render.RENDERER.make_current()
}

@(private)
scoped_current :: proc(w: ^Window) -> (prev: ^Window) {
    prev = _active_window
    make_current(w)
    return
}

@(private)
restore_current :: proc(prev: ^Window) {
    if prev != nil && prev != _active_window do make_current(prev)
}

@(private="file")
sync_size :: proc(w: ^Window) {
    nw, nh := PLATFORM.poll_size()
    next_scale := PLATFORM.content_scale()
    if nw != w.width || nh != w.height || next_scale != w.scale {
        w.width = nw
        w.height = nh
        w.scale = next_scale
        render.RENDERER.resize(nw, nh)
        resize_event := events.Window_Resize_Event {
            width  = nw,
            height = nh,
            scale  = next_scale,
        }
        _emit_window(w, events.WINDOW_RESIZE_EVENT, &resize_event)
    }
}

// Called by the platform during window resize
refresh :: proc(w: ^Window) {
    prev := scoped_current(w)
    defer restore_current(prev)
    sync_size(w)
    _emit_window(w, events.WINDOW_REFRESH_EVENT)
    if w.on_refresh != nil do w.on_refresh(w)
}

close :: proc(w: ^Window) {
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.request_close()
}

@(private = "file")
_window_on :: proc(
    w: ^Window,
    type: string,
    callback: events.Callback,
    capture := false,
    once := false,
) -> uint {
    if w == nil do return 0
    return events.on(&w.bus, type, callback, capture, once)
}

@(private = "file")
_window_off :: proc(w: ^Window, type: string, callback: events.Callback) {
    if w == nil do return
    events.off(&w.bus, type, callback)
}

@(private = "file")
_emit_window :: proc(w: ^Window, type: string, data: rawptr = nil) -> events.Event_Signal {
    signal := events.Event_Signal {
        type           = type,
        target         = w,
        current_target = w,
        phase          = .Target,
        data           = data,
    }
    if w != nil do events.emit_local(&w.bus, &signal)
    return signal
}

set_title :: proc(w: ^Window, title: string) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.set_title(title)
}

// Screen-space position of the window's top-left corner.
get_position :: proc(w: ^Window) -> (x, y: int) {
    if w == nil do return 0, 0
    PLATFORM.set_active_state(w.platform_state)
    return PLATFORM.get_position()
}

// Moves the window. Dragging a custom title bar is this plus the cursor delta.
set_position :: proc(w: ^Window, x, y: int) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.set_position(x, y)
}

set_size :: proc(w: ^Window, width, height: int) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.set_size(width, height)
}

// Constrains interactive resizing. Logical pixels, as with set_size.
set_size_limits :: proc(w: ^Window, min_width, min_height, max_width, max_height: int) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.set_size_limits(min_width, min_height, max_width, max_height)
}

set_min_size :: proc(w: ^Window, width, height: int) {
    set_size_limits(w, width, height, 0, 0)
}

set_cursor :: proc(w: ^Window, shape: Cursor) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.set_cursor(shape)
}

minimize :: proc(w: ^Window) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    begin_self_hide(w)
    PLATFORM.minimize()
    end_self_hide(w)
}

is_maximized :: proc(w: ^Window) -> bool {
    if w == nil do return false
    PLATFORM.set_active_state(w.platform_state)
    return PLATFORM.is_maximized()
}

toggle_maximize :: proc(w: ^Window) {
    if w == nil do return
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.toggle_maximize()
}

free :: proc(w: ^Window) {
    if w == nil do return
    prev := scoped_current(w)
    disable_native_frame(w)
    if w.root != nil do w.root->free()
    painter.shutdown(w.painter)
    for image in w.images do _free_image(image, w.allocator)
    clear(&w.images)
    render.RENDERER.shutdown()
    PLATFORM.set_active_state(w.platform_state)
    PLATFORM.shutdown()
    delete(w.queue)
    delete(w.images)
    PLATFORM.free_state(w.platform_state, w.allocator)
    render.RENDERER.free_state(w.renderer_state, w.allocator)
    painter.free_state(w.painter_state, w.allocator)
    events.bus_destroy(&w.bus)
    eventloop.destroy(w.loop)
    runtime.mem_free(w)

    if prev != w {
        restore_current(prev)
    } else {
        _active_window = nil
        input.set_context(nil)
    }
}
