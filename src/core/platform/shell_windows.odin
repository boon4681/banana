#+build windows
package platform

import "base:runtime"
import win32 "core:sys/windows"
import glfw "vendor:glfw"
import "src:core/events"

foreign import comctl32 "system:Comctl32.lib"

@(private = "file", default_calling_convention = "system")
foreign comctl32 {
    RemoveWindowSubclass :: proc(hwnd: win32.HWND, pfnSubclass: win32.SUBCLASSPROC, uIdSubclass: win32.UINT_PTR) -> win32.BOOL ---
}

@(private = "file")
TRAY_MESSAGE :: win32.WM_APP + 0xBA

@(private = "file")
Native_Tray :: struct {
    id:        win32.UINT,
    icon:      win32.HICON,
    owns_icon: bool,
}

@(private = "file", thread_local)
_shell_hwnd: win32.HWND

@(private = "file", thread_local)
_shell_context: runtime.Context

@(private = "file", thread_local)
_taskbar_created: win32.UINT

@(private = "file", thread_local)
_trays: [dynamic]^Tray

@(private = "file", thread_local)
_next_tray_id: win32.UINT

@(private = "file")
NO_BUTTON_SUBCLASS_ID :: win32.UINT_PTR(0xBA4B)

@(private = "file")
_shell_window :: proc() -> win32.HWND {
    if _shell_hwnd != nil do return _shell_hwnd
    _shell_context = context
    instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
    class_name: cstring16 = "banana_shell"
    class := win32.WNDCLASSEXW {
        cbSize        = size_of(win32.WNDCLASSEXW),
        lpfnWndProc   = _shell_proc,
        hInstance     = instance,
        lpszClassName = class_name,
    }
    win32.RegisterClassExW(&class)
    _shell_hwnd = win32.CreateWindowExW(win32.WS_EX_TOOLWINDOW, class_name, class_name, win32.WS_POPUP, 0, 0, 0, 0, nil, nil, instance, nil)
    // explorer send this after restart, all icons must be added again
    _taskbar_created = win32.RegisterWindowMessageW("TaskbarCreated")
    return _shell_hwnd
}

@(private = "file")
_window_hwnd :: proc(w: ^Window) -> win32.HWND {
    state := cast(^GLFW_STATE)w.platform_state
    if state == nil || state.handle == nil do return nil
    return glfw.GetWin32Window(state.handle)
}

@(private = "file")
_set_taskbar_visible :: proc(w: ^Window, visible: bool) {
    hwnd := _window_hwnd(w)
    if hwnd == nil do return
    owner: win32.HWND
    if !visible {
        // an owned window get no taskbar button
        owner = _shell_window()
        if owner == nil do return
    }
    ex := win32.UINT(win32.GetWindowLongPtrW(hwnd, win32.GWL_EXSTYLE))
    // glfw set WS_EX_APPWINDOW, it force a button even when owned
    if visible {
        ex |= win32.WS_EX_APPWINDOW
    } else {
        ex &~= win32.WS_EX_APPWINDOW
    }
    // taskbar only notice the change when the window show again
    shown := win32.IsWindowVisible(hwnd) != win32.FALSE
    begin_self_hide(w)
    defer end_self_hide(w)
    if shown do win32.ShowWindow(hwnd, win32.SW_HIDE)
    win32.SetWindowLongPtrW(hwnd, win32.GWLP_HWNDPARENT, win32.LONG_PTR(uintptr(owner)))
    win32.SetWindowLongPtrW(hwnd, win32.GWL_EXSTYLE, win32.LONG_PTR(ex))
    if visible {
        RemoveWindowSubclass(hwnd, _no_button_subclass, NO_BUTTON_SUBCLASS_ID)
    } else {
        win32.SetWindowSubclass(hwnd, _no_button_subclass, NO_BUTTON_SUBCLASS_ID, 0)
    }
    if shown do win32.ShowWindow(hwnd, win32.SW_SHOWNA)
}

@(private = "file")
_has_no_button :: proc(hwnd: win32.HWND) -> bool {
    return _shell_hwnd != nil && win32.HWND(uintptr(win32.GetWindowLongPtrW(hwnd, win32.GWLP_HWNDPARENT))) == _shell_hwnd
}

@(private = "file")
_minimize :: proc(w: ^Window) -> bool {
    hwnd := _window_hwnd(w)
    if hwnd == nil || !_has_no_button(hwnd) do return false
    win32.ShowWindow(hwnd, win32.SW_HIDE)
    return true
}

@(private = "file")
_no_button_subclass :: proc "system" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) -> win32.LRESULT {
    switch msg {
    case win32.WM_SYSCOMMAND:
        if win32.UINT(wparam) & 0xFFF0 == win32.SC_MINIMIZE {
            win32.ShowWindow(hwnd, win32.SW_HIDE)
            return 0
        }
    case win32.WM_SIZE:
        if wparam == win32.SIZE_MINIMIZED {
            result := win32.DefSubclassProc(hwnd, msg, wparam, lparam)
            win32.ShowWindow(hwnd, win32.SW_HIDE)
            return result
        }
    }
    return win32.DefSubclassProc(hwnd, msg, wparam, lparam)
}

@(private = "file")
_tray_create :: proc(t: ^Tray) -> bool {
    if _shell_window() == nil do return false
    _next_tray_id += 1
    native := new(Native_Tray, t.window.allocator)
    native.id = _next_tray_id
    t.native = native
    _load_icon(t)
    if !_notify(t, win32.NIM_ADD) {
        _drop_native(t)
        return false
    }
    append(&_trays, t)
    return true
}

@(private = "file")
_tray_update :: proc(t: ^Tray) {
    native := cast(^Native_Tray)t.native
    if native == nil do return
    old_icon, owned := native.icon, native.owns_icon
    _load_icon(t)
    _notify(t, win32.NIM_MODIFY)
    if owned do win32.DestroyIcon(old_icon)
}

@(private = "file")
_tray_destroy :: proc(t: ^Tray) {
    native := cast(^Native_Tray)t.native
    if native == nil do return
    data := win32.NOTIFYICONDATAW{cbSize = size_of(win32.NOTIFYICONDATAW), hWnd = _shell_hwnd, uID = native.id}
    win32.Shell_NotifyIconW(win32.NIM_DELETE, &data)
    for tray, i in _trays {
        if tray == t {
            ordered_remove(&_trays, i)
            break
        }
    }
    _drop_native(t)
}

@(private = "file")
_forget_window :: proc(w: ^Window) {
    #reverse for t in _trays {
        if t.window != w do continue
        _tray_destroy(t)
        _tray_release(t)
    }
}

@(private = "file")
_drop_native :: proc(t: ^Tray) {
    native := cast(^Native_Tray)t.native
    if native.owns_icon do win32.DestroyIcon(native.icon)
    runtime.mem_free(native, t.window.allocator)
    t.native = nil
}

@(private = "file")
_notify :: proc(t: ^Tray, message: win32.DWORD) -> bool {
    native := cast(^Native_Tray)t.native
    data := win32.NOTIFYICONDATAW {
        cbSize           = size_of(win32.NOTIFYICONDATAW),
        hWnd             = _shell_hwnd,
        uID              = native.id,
        uFlags           = win32.NIF_MESSAGE | win32.NIF_ICON | win32.NIF_TIP,
        uCallbackMessage = TRAY_MESSAGE,
        hIcon            = native.icon,
    }
    tip := win32.utf8_to_utf16(t.options.tooltip, context.temp_allocator)
    copy(data.szTip[:len(data.szTip) - 1], tip)
    return win32.Shell_NotifyIconW(message, &data) != win32.FALSE
}

@(private = "file")
_load_icon :: proc(t: ^Tray) {
    native := cast(^Native_Tray)t.native
    native.icon, native.owns_icon = nil, false
    if t.options.icon != "" {
        size_x := win32.GetSystemMetrics(win32.SM_CXSMICON)
        size_y := win32.GetSystemMetrics(win32.SM_CYSMICON)
        handle := win32.LoadImageW(nil, win32.utf8_to_wstring(t.options.icon), win32.IMAGE_ICON, size_x, size_y, win32.LR_LOADFROMFILE)
        if handle != nil {
            native.icon, native.owns_icon = win32.HICON(handle), true
            return
        }
    }
    path: [win32.MAX_PATH]u16
    if win32.GetModuleFileNameW(nil, &path[0], len(path)) > 0 {
        small: win32.HICON
        if win32.ExtractIconExW(cstring16(&path[0]), 0, nil, &small, 1) > 0 && small != nil {
            native.icon, native.owns_icon = small, true
            return
        }
    }
    native.icon = win32.LoadIconW(nil, cast(win32.LPCWSTR)win32._IDI_APPLICATION)
}

@(private = "file")
_find_tray :: proc(id: win32.UINT) -> ^Tray {
    for t in _trays {
        if (cast(^Native_Tray)t.native).id == id do return t
    }
    return nil
}

@(private = "file")
_push_tray :: proc(t: ^Tray, type: string, event: events.Tray_Event) {
    _push_event(t.window, TRAY{type = type, event = event})
}

@(private = "file")
_show_menu :: proc(t: ^Tray, hwnd: win32.HWND) {
    menu := win32.CreatePopupMenu()
    if menu == nil do return
    defer win32.DestroyMenu(menu)
    for item, i in t.options.menu {
        if item.separator {
            win32.AppendMenuW(menu, win32.MF_SEPARATOR, 0, nil)
            continue
        }
        flags := win32.UINT(win32.MF_STRING)
        if item.checked do flags |= win32.MF_CHECKED
        if item.disabled do flags |= win32.MF_GRAYED
        // 0 means dismissed
        win32.AppendMenuW(menu, flags, win32.UINT_PTR(i + 1), win32.utf8_to_wstring(item.label))
    }
    point: win32.POINT
    win32.GetCursorPos(&point)
    // without foreground the menu won't close on outside click
    win32.SetForegroundWindow(hwnd)
    chosen := win32.TrackPopupMenu(menu, win32.TPM_RETURNCMD | win32.TPM_RIGHTBUTTON | win32.TPM_NONOTIFY, point.x, point.y, 0, hwnd, nil)
    win32.PostMessageW(hwnd, win32.WM_NULL, 0, 0)
    if chosen > 0 && int(chosen) <= len(t.options.menu) {
        _push_tray(t, events.TRAY_MENU_EVENT, {item = t.options.menu[chosen - 1].id})
    }
}

@(private = "file")
_shell_proc :: proc "system" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
    context = _shell_context
    if msg == TRAY_MESSAGE {
        t := _find_tray(win32.UINT(wparam))
        if t == nil do return 0
        switch win32.UINT(lparam) & 0xFFFF {
        case win32.WM_LBUTTONUP:
            _push_tray(t, events.TRAY_CLICK_EVENT, {button = 0})
        case win32.WM_RBUTTONUP:
            if len(t.options.menu) > 0 {
                _show_menu(t, hwnd)
            } else {
                _push_tray(t, events.TRAY_CLICK_EVENT, {button = 1})
            }
        }
        return 0
    }
    if msg == _taskbar_created && msg != 0 {
        for t in _trays do _notify(t, win32.NIM_ADD)
        return 0
    }
    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

SHELL :: Shell_Interface {
    set_taskbar_visible = _set_taskbar_visible,
    tray_create         = _tray_create,
    tray_update         = _tray_update,
    tray_destroy        = _tray_destroy,
    forget_window       = _forget_window,
    minimize            = _minimize,
}
