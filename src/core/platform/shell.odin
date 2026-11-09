package platform

import "base:runtime"
import "core:strings"

Tray :: struct {
    window:  ^Window,
    options: Tray_Options,
    native:  rawptr,
}

Tray_Item :: struct {
    id:        int,
    label:     string,
    separator: bool,
    checked:   bool,
    disabled:  bool,
}

Tray_Options :: struct {
    tooltip: string,
    icon:    string, // path to .ico file, leave empty to use the exe icon
    menu:    []Tray_Item,
}

Shell_Interface :: struct #all_or_none {
    set_taskbar_visible: proc(w: ^Window, visible: bool),
    tray_create:         proc(t: ^Tray) -> bool,
    tray_update:         proc(t: ^Tray),
    tray_destroy:        proc(t: ^Tray),
    forget_window:       proc(w: ^Window),
    minimize:            proc(w: ^Window) -> bool,
}

// without a button minimizing hides the window, pair it with a tray icon to bring it back
set_taskbar_visible :: proc(w: ^Window, visible: bool) {
    if w == nil do return
    SHELL.set_taskbar_visible(w, visible)
}

// return nil when the platform have no tray
tray_create :: proc(w: ^Window, options: Tray_Options) -> ^Tray {
    if w == nil do return nil
    t := new(Tray, w.allocator)
    t.window = w
    _tray_store(t, options)
    if !SHELL.tray_create(t) {
        _tray_release(t)
        return nil
    }
    return t
}

tray_update :: proc(t: ^Tray, options: Tray_Options) {
    if t == nil do return
    _tray_store(t, options)
    SHELL.tray_update(t)
}

tray_destroy :: proc(t: ^Tray) {
    if t == nil do return
    SHELL.tray_destroy(t)
    _tray_release(t)
}

@(private)
_tray_store :: proc(t: ^Tray, options: Tray_Options) {
    allocator := t.window.allocator
    _tray_free_options(t)
    t.options.tooltip = strings.clone(options.tooltip, allocator)
    t.options.icon = strings.clone(options.icon, allocator)
    t.options.menu = make([]Tray_Item, len(options.menu), allocator)
    for item, i in options.menu {
        t.options.menu[i] = item
        t.options.menu[i].label = strings.clone(item.label, allocator)
    }
}

@(private)
_tray_release :: proc(t: ^Tray) {
    allocator := t.window.allocator
    _tray_free_options(t)
    runtime.mem_free(t, allocator)
}

@(private = "file")
_tray_free_options :: proc(t: ^Tray) {
    allocator := t.window.allocator
    delete(t.options.tooltip, allocator)
    delete(t.options.icon, allocator)
    for item in t.options.menu do delete(item.label, allocator)
    delete(t.options.menu, allocator)
    t.options = {}
}
