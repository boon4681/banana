#+build windows
package platform

import "core:fmt"
import "base:runtime"
import win32 "core:sys/windows"
import glfw "vendor:glfw"
import "src:core/common"
import "src:core/node"
import "src:core/events"
import "src:core/input"

Frame :: struct {
    hwnd:     win32.HWND,
    previous: win32.WNDPROC,
    window:   ^Window,
    active:   bool,

    title_bar:            Title_Bar,
    no_title_bar:         bool,
    resize_border:        int,
    no_shadow:            bool,
    clamp_maximized:      bool,
    no_erase:             bool,
    top_most:             bool,
    always_top_most:      bool,
    click_through:        bool,
    click_through_active: bool,

    using _internal_vt: ^Frame_VTable,
}

@(private = "file", thread_local)
_frame: Frame

@(private = "file")
TOP_MOST_TIMER_ID :: win32.UINT_PTR(0xBA4A)

@(private = "file")
MA_NOACTIVATE :: win32.LRESULT(3)

@(private = "file")
TOP_MOST_TIMER_MS :: win32.UINT(100)

@(private = "file", thread_local)
_asserting_top_most: bool

@(private = "file", thread_local)
_reassert_pending: bool

enable_native_frame :: proc(w: ^Window) -> ^Frame {
    if w == nil do return nil
    PLATFORM.set_active_state(w.platform_state)

    if _frame.active do return &_frame if _frame.window == w else nil

    hwnd := _glfw_hwnd()
    if hwnd == nil do return nil

    frame := Frame {
        hwnd          = hwnd,
        window        = w,
        active        = true,
        resize_border = DEFAULT_RESIZE_BORDER,
        _internal_vt  = &frame_vtable,
    }
    _frame = frame
    w.frame = &_frame

    previous := win32.SetWindowLongPtrW(
        hwnd,
        win32.GWLP_WNDPROC,
        win32.LONG_PTR(uintptr(rawptr(_frame_proc))),
    )
    _frame.previous = transmute(win32.WNDPROC)uintptr(previous)
    _apply_shadow(&_frame)
    return &_frame
}

@(private = "file")
frame_vtable := Frame_VTable {
    set_title_bar = proc(self: ^Frame, bar: Title_Bar) -> ^Frame {
        self.title_bar = bar
        self.no_title_bar = true
        _apply_frame_change(self)
        return self
    },
    clear_title_bar = proc(self: ^Frame) -> ^Frame {
        self.title_bar = {}
        self.no_title_bar = false
        _apply_frame_change(self)
        return self
    },
    set_resize_border = proc(self: ^Frame, width: int) -> ^Frame {
        self.resize_border = width
        return self
    },
    set_click_through = proc(self: ^Frame, enabled: bool) -> ^Frame {
        self.click_through = enabled

        if enabled {
            ex := win32.UINT(win32.GetWindowLongPtrW(self.hwnd, win32.GWL_EXSTYLE))
            win32.SetWindowLongPtrW(
                self.hwnd,
                win32.GWL_EXSTYLE,
                win32.LONG_PTR(ex | win32.WS_EX_LAYERED),
            )
            win32.SetLayeredWindowAttributes(self.hwnd, 0, 255, win32.LWA_ALPHA)
        }
        self.click_through_active = false
        return self
    },
    set_shadow = proc(self: ^Frame, enabled: bool) -> ^Frame {
        self.no_shadow = !enabled
        _apply_shadow(self)
        return self
    },
    set_clamp_maximized = proc(self: ^Frame, enabled: bool) -> ^Frame {
        self.clamp_maximized = enabled
        _apply_frame_change(self)
        return self
    },
    set_background_erase = proc(self: ^Frame, enabled: bool) -> ^Frame {
        self.no_erase = !enabled
        return self
    },
    set_top_most = proc(self: ^Frame, enabled: bool) -> ^Frame {
        self.top_most = enabled
        win32.SetWindowPos(
            self.hwnd,
            win32.HWND_TOPMOST if enabled else win32.HWND_NOTOPMOST,
            0, 0, 0, 0,
            win32.SWP_NOMOVE | win32.SWP_NOSIZE,
        )
        return self
    },
    set_resize = proc(self: ^Frame, enabled: bool) -> ^Frame {
        state: ^GLFW_STATE = auto_cast(PLATFORM.get_active_state())
        handle := state.handle
        if handle != nil do glfw.SetWindowAttrib(handle, glfw.RESIZABLE, enabled ? 1 : 0)
        return self
    },
    set_always_top_most = proc(self: ^Frame, enabled: bool) -> ^Frame {
        if self.always_top_most == enabled do return self
        self.always_top_most = enabled

        _apply_overlay_styles(self, enabled)
        if enabled {
            self.top_most = true
            _assert_top_most(self.hwnd)
            win32.SetTimer(self.hwnd, TOP_MOST_TIMER_ID, TOP_MOST_TIMER_MS, nil)
        } else {
            win32.KillTimer(self.hwnd, TOP_MOST_TIMER_ID)
        }
        return self
    },
}

sync_click_through :: proc(w: ^Window) {
    if !_frame.active || !_frame.click_through || _frame.window != w do return

    point: win32.POINT
    if win32.GetCursorPos(&point) == win32.FALSE do return
    if win32.ScreenToClient(_frame.hwnd, &point) == win32.FALSE do return

    scale := w.scale if w.scale > 0 else 1
    transparent := !_any_node_claims(w.root, f32(point.x) / scale, f32(point.y) / scale)

    if transparent == _frame.click_through_active do return
    _frame.click_through_active = transparent

    ex := win32.UINT(win32.GetWindowLongPtrW(_frame.hwnd, win32.GWL_EXSTYLE))
    if transparent {
        ex |= win32.WS_EX_TRANSPARENT
    } else {
        ex &~= win32.WS_EX_TRANSPARENT
    }
    win32.SetWindowLongPtrW(_frame.hwnd, win32.GWL_EXSTYLE, win32.LONG_PTR(ex))
}

@(private = "file")
_assert_top_most :: proc "contextless" (hwnd: win32.HWND) {
    _asserting_top_most = true
    defer _asserting_top_most = false

    flags := win32.UINT(win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE)
    win32.SetWindowPos(hwnd, win32.HWND_TOPMOST, 0, 0, 0, 0, flags)
    win32.SetWindowPos(hwnd, win32.HWND_TOP, 0, 0, 0, 0, flags)
}

@(private = "file")
_apply_overlay_styles :: proc(self: ^Frame, enabled: bool) {
    ex := win32.UINT(win32.GetWindowLongPtrW(self.hwnd, win32.GWL_EXSTYLE))
    overlay := win32.WS_EX_TOOLWINDOW | win32.WS_EX_NOACTIVATE
    if enabled {
        ex |= overlay
    } else {
        ex &~= overlay
    }
    win32.SetWindowLongPtrW(self.hwnd, win32.GWL_EXSTYLE, win32.LONG_PTR(ex))
    _apply_frame_change(self)
}

@(private = "file")
_apply_shadow :: proc(self: ^Frame) {
    margins := win32.MARGINS{1, 1, 1, 1}
    if self.no_shadow do margins = {}
    win32.DwmExtendFrameIntoClientArea(self.hwnd, &margins)
    _apply_frame_change(self)
}

@(private = "file")
_apply_frame_change :: proc(self: ^Frame) {
    win32.SetWindowPos(
        self.hwnd,
        nil,
        0,
        0,
        0,
        0,
        win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED,
    )
}

@(private = "file")
_frame_proc :: proc "system" (
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) -> win32.LRESULT {
    switch msg {
    case win32.WM_NCCALCSIZE:
        if wparam != 0 && _frame.no_title_bar {
            if _frame.clamp_maximized do _constrain_maximized_client(hwnd, lparam)
            return 0
        }
    case win32.WM_ERASEBKGND:
        if _frame.no_erase do return 1
    case win32.WM_NCHITTEST:
        if _frame.no_title_bar || _frame.resize_border > 0 {
            context = runtime.default_context()
            return _hit_test(hwnd, lparam)
        }
    case win32.WM_MOUSEACTIVATE:
        if _frame.always_top_most do return MA_NOACTIVATE
    case win32.WM_TIMER:
        if _frame.always_top_most && wparam == win32.WPARAM(TOP_MOST_TIMER_ID) {
            _assert_top_most(hwnd)
            return 0
        }
    case win32.WM_ACTIVATEAPP, win32.WM_SETTINGCHANGE:
        if _frame.always_top_most do _assert_top_most(hwnd)
    case win32.WM_WINDOWPOSCHANGING:
        if _frame.always_top_most && !_asserting_top_most {
            pos := cast(^win32.WINDOWPOS)(rawptr(uintptr(lparam)))
            if pos.flags & win32.SWP_NOZORDER == 0 {
                pos.flags |= win32.SWP_NOZORDER
                _reassert_pending = true
            }
        }
    }

    result := win32.CallWindowProcW(_frame.previous, hwnd, msg, wparam, lparam)
    if msg == win32.WM_WINDOWPOSCHANGED && _reassert_pending {
        _reassert_pending = false
        if _frame.always_top_most do _assert_top_most(hwnd)
    }
    return result
}

@(private = "file")
_constrain_maximized_client :: proc "contextless" (hwnd: win32.HWND, lparam: win32.LPARAM) {
    if win32.IsZoomed(hwnd) == win32.FALSE do return

    monitor := win32.MonitorFromWindow(hwnd, .MONITOR_DEFAULTTONEAREST)
    if monitor == nil do return

    info := win32.MONITORINFO{cbSize = win32.DWORD(size_of(win32.MONITORINFO))}
    if win32.GetMonitorInfoW(monitor, &info) == win32.FALSE do return

    params := cast(^win32.NCCALCSIZE_PARAMS)(rawptr(uintptr(lparam)))
    params.rgrc[0] = info.rcWork
}

@(private = "file")
_hit_test :: proc(hwnd: win32.HWND, lparam: win32.LPARAM) -> win32.LRESULT {
    x := i32(cast(i16)(u32(lparam) & 0xffff))
    y := i32(cast(i16)((u32(lparam) >> 16) & 0xffff))

    rect: win32.RECT
    win32.GetWindowRect(hwnd, &rect)

    scale := _frame.window.scale if _frame.window != nil && _frame.window.scale > 0 else 1

    if _frame.resize_border > 0 {
        border := max(i32(f32(_frame.resize_border) * scale), 1)
        left := x < rect.left + border
        right := x >= rect.right - border
        top := y < rect.top + border
        bottom := y >= rect.bottom - border
        if top && left do return win32.HTTOPLEFT
        if top && right do return win32.HTTOPRIGHT
        if bottom && left do return win32.HTBOTTOMLEFT
        if bottom && right do return win32.HTBOTTOMRIGHT
        if left do return win32.HTLEFT
        if right do return win32.HTRIGHT
        if top do return win32.HTTOP
        if bottom do return win32.HTBOTTOM
    }

    if !_frame.no_title_bar do return win32.HTCLIENT

    point := win32.POINT{x, y}
    if win32.ScreenToClient(hwnd, &point) == win32.FALSE do return win32.HTCLIENT
    client_x := f32(point.x) / scale
    client_y := f32(point.y) / scale

    if _node_contains(_frame.title_bar.minimize_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.title_bar.maximize_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.title_bar.close_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.title_bar.caption_node, client_x, client_y) {
        if _secondary_button_down() do return win32.HTCLIENT
        if _active_window.input.hovered != nil {
            ev := events.Mouse_Event{x = auto_cast x, y = auto_cast y, mods = _active_window.input.mods}
            input.dispatch(_active_window.input.hovered, events.MOUSE_LEAVE_EVENT, &ev)
        }
        return win32.HTCAPTION
    }

    if _frame.click_through && _active_window != nil {
        if !_any_node_claims(_active_window.root, client_x, client_y) {
            return win32.HTTRANSPARENT
        }
    }
    return win32.HTCLIENT
}

@(private = "file")
_secondary_button_down :: proc "contextless" () -> bool {
    vk := i32(win32.VK_RBUTTON)
    if win32.GetSystemMetrics(win32.SM_SWAPBUTTON) != 0 do vk = i32(win32.VK_LBUTTON)
    return win32.GetAsyncKeyState(vk) < 0
}

@(private = "file")
_node_contains :: proc(n: ^node.BaseNode, x, y: f32) -> bool {
    return n != nil && !n.freed && common.rect_intersect(n.rect, x, y)
}

@(private = "file")
_any_node_claims :: proc(n: ^node.BaseNode, x, y: f32) -> bool {
    if n == nil || n.freed do return false
    for c in n.children {
        if _any_node_claims(c, x, y) do return true
    }
    if node.Resolve_Pointer_Events(n) == .None do return false
    return common.rect_intersect(n.rect, x, y)
}

@(private = "file")
_glfw_hwnd :: proc() -> win32.HWND {
    state: ^GLFW_STATE = auto_cast(PLATFORM.get_active_state())
    handle := state.handle
    if handle == nil do return nil
    return glfw.GetWin32Window(handle)
}
