#+build !js
package inspector

import "base:intrinsics"
import "core:sync"
import "core:thread"
import "core:time"
import "src:core/events"
import "src:core/hit_test"
import "src:core/node"
import "src:core/platform"

Options :: struct {
    width:      int,
    height:     int,
    title:      cstring,
    font_paths: []string,
    overlay_font: ^node.Font,
    refresh: f32,
}

WINDOWS_FONTS :: []string {
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/consola.ttf",
    "C:/Windows/Fonts/arial.ttf",
}

MAC_FONTS :: []string {
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Menlo.ttc",
}

LINUX_FONTS :: []string {
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
}

when ODIN_OS == .Windows {
    DEFAULT_FONTS :: WINDOWS_FONTS
} else when ODIN_OS == .Darwin {
    DEFAULT_FONTS :: MAC_FONTS
} else {
    DEFAULT_FONTS :: LINUX_FONTS
}

@(private) SWALLOW_UP :: u32(2)
@(private) SWALLOW_CLICK :: u32(1)

Inspector :: struct {
    app:  ^platform.Window,
    opts: Options,

    mu:        sync.Mutex,
    write:     ^Snapshot,
    ready:     ^Snapshot,
    read:      ^Snapshot,
    has_ready: bool,

    want_snapshot: u32,
    pick_mode:     u32,
    swallow:       u32,
    hover_id:      Node_Id,
    selected_id:   Node_Id,
    select_epoch:  u64,
    fps_bits:      u32,
    node_count:    i32,
    quit:          u32,
    panel_alive:   u32,
    close_app:     u32,

    // App thread only.
    overlay:          Overlay,
    last_frame:       time.Tick,
    pending_app_shot: int,
    captured_pointer: bool,
    overlay_shown:    bool,

    booted: sync.Sema,
    worker: ^thread.Thread,
}

@(private)
_app: ^Inspector

New :: proc(app: ^platform.Window, opts: Options = {}) -> ^Inspector {
    if app == nil || _app != nil do return nil

    insp := new(Inspector)
    insp.app = app
    insp.opts = opts
    if insp.opts.width <= 0 do insp.opts.width = 1040
    if insp.opts.height <= 0 do insp.opts.height = 680
    if insp.opts.title == nil do insp.opts.title = "Banana Inspector"
    if len(insp.opts.font_paths) == 0 do insp.opts.font_paths = DEFAULT_FONTS
    if insp.opts.refresh <= 0 do insp.opts.refresh = 0.12
    if insp.opts.overlay_font == nil {
        insp.opts.overlay_font = app.root->style()->get_font()
    }

    insp.write = new(Snapshot)
    insp.ready = new(Snapshot)
    insp.read = new(Snapshot)

    overlay_build(&insp.overlay, insp.opts.overlay_font)
    app.root->add(insp.overlay.root)
    insp.overlay_shown = true

    _app = insp
    _install_guards(app)

    insp.worker = thread.create_and_start_with_data(rawptr(insp), _panel_thread)
    if !sync.sema_wait_with_timeout(&insp.booted, 10 * time.Second) {
        intrinsics.atomic_store(&insp.quit, 1)
    }
    return insp
}

destroy :: proc(insp: ^Inspector) {
    if insp == nil do return
    if insp.captured_pointer {
        insp.captured_pointer = false
        platform.set_pointer_capture(false)
    }
    intrinsics.atomic_store(&insp.quit, 1)
    if insp.worker != nil {
        thread.join(insp.worker)
        thread.destroy(insp.worker)
        insp.worker = nil
    }
    snapshot_destroy(insp.write)
    snapshot_destroy(insp.ready)
    snapshot_destroy(insp.read)
    free(insp.write)
    free(insp.ready)
    free(insp.read)
    _app = nil
    free(insp)
}

open :: proc(insp: ^Inspector) -> bool {
    return insp != nil && intrinsics.atomic_load(&insp.panel_alive) == 1
}

update :: proc(insp: ^Inspector) {
    if insp == nil || insp.app == nil do return
    app := insp.app
    scale := app.scale if app.scale > 0 else 1
    viewport := [2]f32{f32(app.width) / scale, f32(app.height) / scale}

    now := time.tick_now()
    if insp.last_frame != {} {
        dt := f32(time.duration_seconds(time.tick_diff(insp.last_frame, now)))
        if dt > 0 {
            prev := transmute(f32)intrinsics.atomic_load(&insp.fps_bits)
            next := prev * 0.9 + (1 / dt) * 0.1 if prev > 0 else 1 / dt
            intrinsics.atomic_store(&insp.fps_bits, transmute(u32)next)
        }
    }
    insp.last_frame = now

    picking := intrinsics.atomic_load(&insp.pick_mode) == 1
    if picking != insp.captured_pointer {
        insp.captured_pointer = picking
        platform.set_pointer_capture(picking)
    }

    if intrinsics.atomic_load(&insp.panel_alive) == 0 && insp.pending_app_shot == 0 {
        if insp.overlay_shown {
            insp.overlay_shown = false
            insp.overlay.paint.hover = {}
            overlay_set_tip(&insp.overlay, "", {}, viewport)
            insp.overlay.root->style()->set_display(.None)
        }
        return
    }

    if picking {
        mx, my := app.input.mouse_x, app.input.mouse_y
        id := Node_Id(0)
        if mx >= 0 && my >= 0 && mx < viewport.x && my < viewport.y {
            probe := hit_test.Hit_Options {
                ignore_pointer_events = true,
                skip                  = auto_cast(insp.overlay.root),
            }
            if hit := hit_test.hit_test(app.root, mx, my, probe); hit != nil {
                id = Node_Id(uintptr(hit))
            }
        }
        intrinsics.atomic_store(&insp.hover_id, id)
    }

    hover_id := intrinsics.atomic_load(&insp.hover_id)
    hover_node := _resolve(app.root, insp.overlay.root, hover_id)
    if hover_id != 0 && hover_node == nil do intrinsics.atomic_store(&insp.hover_id, Node_Id(0))

    insp.overlay.paint.hover = metrics_of(hover_node)
    if hover_node != nil {
        overlay_set_tip(&insp.overlay, _label(hover_node), metrics_of(hover_node), viewport)
    } else {
        overlay_set_tip(&insp.overlay, "", {}, viewport)
    }

    if intrinsics.atomic_exchange(&insp.want_snapshot, 0) == 1 {
        capture(insp.write, app.root, insp.overlay.root)
        insp.write.viewport = viewport
        insp.write.scale = scale
        intrinsics.atomic_store(&insp.node_count, i32(len(insp.write.nodes)))

        sync.mutex_lock(&insp.mu)
        insp.write, insp.ready = insp.ready, insp.write
        insp.has_ready = true
        sync.mutex_unlock(&insp.mu)
    }
}

acquire :: proc(insp: ^Inspector) -> (snap: ^Snapshot, fresh: bool) {
    sync.mutex_lock(&insp.mu)
    defer sync.mutex_unlock(&insp.mu)
    if insp.has_ready {
        insp.read, insp.ready = insp.ready, insp.read
        insp.has_ready = false
        fresh = true
    }
    return insp.read, fresh
}

@(private)
_label :: proc(n: ^node.BaseNode) -> string {
    if n == nil do return ""
    if n.key == "" do return type_name(n)
    return _join(type_name(n), "#", n.key)
}

@(private = "file")
_join :: proc(a, b, c: string) -> string {
    out := make([]u8, len(a) + len(b) + len(c), context.temp_allocator)
    copy(out, a)
    copy(out[len(a):], b)
    copy(out[len(a) + len(b):], c)
    return string(out)
}

@(private = "file")
_resolve :: proc(n: ^node.BaseNode, skip: ^node.BaseNode, want: Node_Id) -> ^node.BaseNode {
    if n == nil || n.freed || n == skip || want == 0 do return nil
    if Node_Id(uintptr(n)) == want do return n
    for c in n.children {
        if hit := _resolve(c, skip, want); hit != nil do return hit
    }
    return nil
}

@(private = "file")
_install_guards :: proc(app: ^platform.Window) {
    app->on(events.MOUSE_DOWN_EVENT, _pointer_guard, true)
    app->on(events.MOUSE_UP_EVENT, _pointer_guard, true)
    app->on(events.MOUSE_CLICK_EVENT, _pointer_guard, true)
    app->on(events.MOUSE_MOVE_EVENT, _pointer_guard, true)
    app->on(events.MOUSE_WHEEL_EVENT, _pointer_guard, true)
    app->on(events.KEY_DOWN_EVENT, _key_guard, true)
}

@(private = "file")
_pointer_guard :: proc(s: ^events.Event_Signal) {
    insp := _app
    if insp == nil do return
    picking := intrinsics.atomic_load(&insp.pick_mode) == 1
    if !picking && intrinsics.atomic_load(&insp.swallow) == 0 do return

    if picking && s.type == events.MOUSE_DOWN_EVENT {
        intrinsics.atomic_store(&insp.selected_id, intrinsics.atomic_load(&insp.hover_id))
        intrinsics.atomic_add(&insp.select_epoch, 1)
        intrinsics.atomic_store(&insp.pick_mode, 0)
        intrinsics.atomic_store(&insp.swallow, SWALLOW_UP)
    }
    switch s.type {
    case events.MOUSE_UP_EVENT:    intrinsics.atomic_store(&insp.swallow, SWALLOW_CLICK)
    case events.MOUSE_CLICK_EVENT: intrinsics.atomic_store(&insp.swallow, 0)
    case events.MOUSE_MOVE_EVENT:
        if !picking && intrinsics.atomic_load(&insp.swallow) == SWALLOW_CLICK {
            intrinsics.atomic_store(&insp.swallow, 0)
        }
    }
    events.stop_propagation(s)
    events.prevent_default(s)
}

@(private = "file")
_key_guard :: proc(s: ^events.Event_Signal) {
    insp := _app
    if insp == nil || intrinsics.atomic_load(&insp.pick_mode) == 0 do return
    e := cast(^events.Key_Event)s.data
    if e == nil || e.code != .Escape do return
    intrinsics.atomic_store(&insp.pick_mode, 0)
    intrinsics.atomic_store(&insp.hover_id, Node_Id(0))
    events.stop_propagation(s)
    events.prevent_default(s)
}
