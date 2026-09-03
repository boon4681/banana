#+build !js
package inspector

import "base:intrinsics"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"
import "src:core/common"
import "src:core/events"
import "src:core/layout"
import "src:core/node"
import "src:core/paint"
import "src:core/painter"
import "src:core/platform"
import "src:core/text"
import "src:ui/box"
import "src:ui/button"

MAX_CRUMBS :: 10

CUSTOM_TITLE_BAR :: ODIN_OS == .Windows

TITLE_BAR_H  :: f32(32)
BAR_BG       :: Color{32, 32, 32, 255}
BAR_TEXT     :: Color{248, 250, 252, 255}
BTN_IDLE     :: Color{0, 0, 0, 1}
BTN_HOT      :: Color{60, 60, 60, 255}
BTN_DOWN     :: Color{50, 50, 50, 255}
CLOSE_HOT    :: Color{196, 43, 28, 255}
CLOSE_DOWN   :: Color{176, 38, 25, 255}

Panel :: struct {
    insp: ^Inspector,
    win:  ^platform.Window,
    font: ^text.Font_Set,

    caption:   ^box.Box,
    btn_min:   ^button.Button,
    btn_max:   ^button.Button,
    btn_close: ^button.Button,

    pick_button: ^box.Box,
    pick_icon:   ^Icon,
    title:       Label,
    stats:       Label,
    crumb_bar:   ^box.Box,
    crumbs:      [MAX_CRUMBS]Label,

    tree:   Tree_View,
    styles: Style_View,

    snap:          ^Snapshot,
    frame_index:   int,
    selected:      Node_Id,
    last_epoch:    u64,
    refresh_timer: f32,
    last_tick:     time.Tick,
}

@(private, thread_local)
_panel: ^Panel

select_node :: proc(p: ^Panel, id: Node_Id) {
    p.selected = id
    intrinsics.atomic_store(&p.insp.selected_id, id)
    if p.snap != nil {
        tree_reveal(&p.tree, p.snap, id)
        tree_flatten(&p.tree, p.snap)
        styles_update(&p.styles, p.snap, id)
        _sync_crumbs(p)
    }
}

@(private)
_panel_thread :: proc(data: rawptr) {
    insp := cast(^Inspector)data
    layout.scheduler_setup()
    defer layout.scheduler_shutdown()

    p := new(Panel)
    defer free(p)
    _panel = p
    defer _panel = nil
    p.insp = insp

    p.font = text.set_create()
    defer text.set_destroy(p.font)
    for path in insp.opts.font_paths do text.load_font(p.font, path)
    if len(p.font.faces) == 0 {
        fmt.eprintln("inspector: no font found; pass Options.font_paths to get readable text")
    }

    p.win = platform.New({
        width        = insp.opts.width,
        height       = insp.opts.height,
        title        = insp.opts.title,
        vsync        = true,
        msaa_samples = 1,
    })
    _build(p)
    when CUSTOM_TITLE_BAR {
        platform.enable_native_frame(p.win)->
            set_title_bar({
                caption_node    = auto_cast(p.caption),
                minimize_button = auto_cast(p.btn_min),
                maximize_button = auto_cast(p.btn_max),
                close_button    = auto_cast(p.btn_close),
            })->
            set_resize_border(8)->
            set_clamp_maximized(true)->
            set_background_erase(false)
    }
    layout.awake_window(p.win)
    p.win.state = p
    p.win.on_refresh = _refresh

    intrinsics.atomic_store(&insp.panel_alive, 1)
    sync.sema_post(&insp.booted)

    for intrinsics.atomic_load(&insp.quit) == 0 {
        if !platform.update(p.win) do break
        _frame(p)
    }

    intrinsics.atomic_store(&insp.pick_mode, 0)
    intrinsics.atomic_store(&insp.panel_alive, 0)
    platform.free(p.win)
    delete(p.tree.rows)
    delete(p.tree.order)
    delete(p.tree.folded)
}

@(private = "file")
_refresh :: proc(w: ^platform.Window) {
    p := cast(^Panel)w.state
    if p != nil do _frame(p)
}

@(private = "file")
_build :: proc(p: ^Panel) {
    root := p.win.root
    root->style()->
        set_flex_direction(.Column)->
        set_align_items(.Stretch)->
        set_font(p.font)->
        set_font_size(FONT_SIZE)->
        set_color(TEXT)

    when CUSTOM_TITLE_BAR do root->add(_build_title_bar(p, string(p.insp.opts.title)))

    bar := row_box("toolbar")
    bar->style()->
        set_width(100, node.percent)->
        set_height(30)->
        set_padding_x(6)->
        set_gap_all(6)->
        set_align_items(.Center)
    bar->style().background = PANEL

    p.pick_button = box.New({radius = 4}, "pick")
    p.pick_button->style()->
        set_width(22)->
        set_height(22)->
        set_flex_shrink(0)->
        set_align_items(.Center)->
        set_justify_content(.Center)
    p.pick_icon = icon(.Picker, 14, TEXT_DIM)
    p.pick_button->add(p.pick_icon)
    p.pick_button->on(events.MOUSE_DOWN_EVENT, _pick_down)

    p.title = label("Elements", TEXT, FONT_SIZE)
    p.stats = label("", TEXT_FAINT, FONT_SIZE)
    bar->add(p.pick_button, divider(true), p.title.root, spacer(), p.stats.root)

    body := row_box("body")
    body->style()->
        set_width(100, node.percent)->
        set_flex_grow(1)->
        set_flex_shrink(1)->
        set_align_items(.Stretch)

    side := box.New({background = PANEL}, "styles-side")
    side->style()->
        set_width(300)->
        set_flex_shrink(0)->
        set_flex_direction(.Column)->
        set_align_items(.Stretch)->
        set_height(100, node.percent)
    side->add(styles_build(&p.styles))

    edge := box.New({background = LINE}, "split")
    edge->style()->set_width(1)->set_flex_shrink(0)->set_height(100, node.percent)

    body->add(tree_build(&p.tree), edge, side)

    p.crumb_bar = row_box("breadcrumbs")
    p.crumb_bar->style()->
        set_width(100, node.percent)->
        set_height(22)->
        set_padding_x(8)->
        set_gap_all(4)->
        set_align_items(.Center)
    p.crumb_bar->style().background = PANEL
    for i in 0 ..< MAX_CRUMBS {
        p.crumbs[i] = label("", TEXT_DIM, FONT_SIZE_SM)
        p.crumbs[i].root->style()->set_display(.None)
        p.crumb_bar->add(p.crumbs[i].root)
    }

    root->add(bar, divider(false), body, divider(false), p.crumb_bar)
}

@(private = "file")
_build_title_bar :: proc(p: ^Panel, title: string) -> ^box.Box {
    p.caption = row_box("titlebar")
    p.caption->style()->set_width(100, node.percent)->set_height(TITLE_BAR_H)
    p.caption->style().background = BAR_BG

    name := row_box("caption")
    name->style()->
        set_height(TITLE_BAR_H)->
        set_flex_grow(1)->
        set_padding_x(12)->
        set_align_items(.Center)
    name->add(label(title, BAR_TEXT, 12).root)

    controls := row_box("window-controls")
    controls->style()->set_width(138)->set_height(TITLE_BAR_H)->set_flex_shrink(0)

    p.btn_min = _bar_button("─", BTN_HOT, BTN_DOWN, _on_minimize)
    p.btn_max = _bar_button("☐", BTN_HOT, BTN_DOWN, _on_maximize)
    p.btn_close = _bar_button("✕", CLOSE_HOT, CLOSE_DOWN, _on_close)
    controls->add(p.btn_min, p.btn_max, p.btn_close)

    p.caption->add(name, controls)
    return p.caption
}

@(private = "file")
_bar_button :: proc(glyph: string, hot, down: Color, click: proc(self: ^button.Button)) -> ^button.Button {
    b := button.New(glyph, {background = BTN_IDLE, hover = hot, pressed = down, radius = 0})
    b->style()->set_width(46)->set_height(TITLE_BAR_H)->set_font_size(10)->set_color(BAR_TEXT)
    b.onclick = click
    return b
}

@(private = "file")
_on_minimize :: proc(self: ^button.Button) {
    if _panel != nil do platform.minimize(_panel.win)
}

@(private = "file")
_on_maximize :: proc(self: ^button.Button) {
    if _panel != nil do platform.toggle_maximize(_panel.win)
}

@(private = "file")
_on_close :: proc(self: ^button.Button) {
    if _panel != nil do platform.close(_panel.win)
}

@(private = "file")
_frame :: proc(p: ^Panel) {
    insp := p.insp
    w := p.win
    scale := w.scale if w.scale > 0 else 1

    now := time.tick_now()
    dt := f32(0.016)
    if p.last_tick != {} do dt = f32(time.duration_seconds(time.tick_diff(p.last_tick, now)))
    p.last_tick = now

    p.refresh_timer -= dt
    if p.refresh_timer <= 0 {
        intrinsics.atomic_store(&insp.want_snapshot, 1)
        p.refresh_timer = insp.opts.refresh
    }

    if snap, fresh := acquire(insp); fresh {
        p.snap = snap
        tree_flatten(&p.tree, snap)
        styles_update(&p.styles, snap, p.selected)
        _sync_crumbs(p)
    }

    if epoch := intrinsics.atomic_load(&insp.select_epoch); epoch != p.last_epoch {
        p.last_epoch = epoch
        select_node(p, intrinsics.atomic_load(&insp.selected_id))
    }

    _sync_toolbar(p)
    styles_hover(&p.styles, w.input.mouse_x, w.input.mouse_y)
    if p.snap != nil do tree_sync(p)

    layout.update(w.root, f32(w.width) / scale, f32(w.height) / scale)

    painter.begin_frame(w.painter, BG)
    dpi := common.IDENTITY_TRANSFORM
    dpi.scale = {scale, scale}
    painter.push_transform(w.painter, dpi, {0, 0})
    paint.draw(w.painter, w.root)
    painter.pop_transform(w.painter)
    painter.end_frame(w.painter)

    p.frame_index += 1
    free_all(context.temp_allocator)
}

@(private = "file")
_sync_toolbar :: proc(p: ^Panel) {
    insp := p.insp
    picking := intrinsics.atomic_load(&insp.pick_mode) == 1
    hover := common.rect_intersect(p.pick_button.rect, p.win.input.mouse_x, p.win.input.mouse_y)

    bg := Color{0, 0, 0, 0}
    if picking {
        bg = BTN_ON
    } else if hover {
        bg = BTN_HOVER
    }
    p.pick_button->style().background = bg
    p.pick_icon.color = TEXT if picking else (TEXT_DIM if !hover else TEXT)

    fps := transmute(f32)intrinsics.atomic_load(&insp.fps_bits)
    count := intrinsics.atomic_load(&insp.node_count)
    label_set(p.stats, fmt.tprintf("%d nodes  |  app %.0f fps", count, fps))
    label_set(p.title, "Elements (picking)" if picking else "Elements")
    label_color(p.title, ACCENT if picking else TEXT)
}

@(private = "file")
_sync_crumbs :: proc(p: ^Panel) {
    for i in 0 ..< MAX_CRUMBS do p.crumbs[i].root->style()->set_display(.None)
    if p.snap == nil do return
    index := find_index(p.snap, p.selected)
    if index < 0 do return

    chain: [MAX_CRUMBS]int
    depth := 0
    for at := index; at >= 0 && depth < MAX_CRUMBS; at = int(p.snap.nodes[at].parent) {
        chain[depth] = at
        depth += 1
    }

    for slot in 0 ..< depth {
        entry := p.snap.nodes[chain[depth - 1 - slot]]
        name := str(p.snap, entry.name)
        key := str(p.snap, entry.key)
        text := name if key == "" else strings.concatenate({name, "#", key}, context.temp_allocator)
        if slot > 0 do text = strings.concatenate({"> ", text}, context.temp_allocator)
        label_set(p.crumbs[slot], text)
        label_color(p.crumbs[slot], TEXT if slot == depth - 1 else TEXT_DIM)
        p.crumbs[slot].root->style()->set_display(.Flex)
    }
}

@(private = "file")
_pick_down :: proc(s: ^events.Event_Signal) {
    p := _panel
    if p == nil do return
    now := intrinsics.atomic_load(&p.insp.pick_mode)
    intrinsics.atomic_store(&p.insp.pick_mode, 0 if now == 1 else 1)
    if now == 1 do intrinsics.atomic_store(&p.insp.hover_id, Node_Id(0))
    events.stop_propagation(s)
}
