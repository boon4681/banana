#+build windows
package platform

// Native-frame chrome for borderless windows on Windows.

import "base:runtime"
import win32 "core:sys/windows"
import glfw "vendor:glfw"
import "src:core/common"
import "src:core/node"
import "src:core/events"
import "src:core/input"

@(private = "file")
Frame_State :: struct {
    hwnd:     win32.HWND,
    previous: win32.WNDPROC,
    window:   ^Window,
    metrics:  Frame_Metrics,
    active:   bool,
}

@(private = "file", thread_local)
_frame: Frame_State

enable_native_frame :: proc(w: ^Window, metrics: Frame_Metrics = DEFAULT_FRAME_METRICS) {
    if w == nil || _frame.active do return
    PLATFORM.set_active_state(&w.platform_state[0])

    hwnd := _glfw_hwnd()
    if hwnd == nil do return

    _frame.hwnd = hwnd
    _frame.window = w
    _frame.metrics = metrics
    _frame.active = true

    previous := win32.SetWindowLongPtrW(
        hwnd,
        win32.GWLP_WNDPROC,
        win32.LONG_PTR(uintptr(rawptr(_frame_proc))),
    )
    _frame.previous = transmute(win32.WNDPROC)uintptr(previous)

    margins := win32.MARGINS{1, 1, 1, 1}
    win32.DwmExtendFrameIntoClientArea(hwnd, &margins)
    win32.SetWindowPos(
        hwnd,
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
        if wparam != 0 {
            _constrain_maximized_client(hwnd, lparam)
            return 0
        }
    case win32.WM_ERASEBKGND:
        return 1
    case win32.WM_NCHITTEST:
        context = runtime.default_context()
        return _hit_test(hwnd, lparam)
    }
    return win32.CallWindowProcW(_frame.previous, hwnd, msg, wparam, lparam)
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
    border := max(i32(f32(_frame.metrics.resize_border) * scale), 1)
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

    point := win32.POINT{x, y}
    if win32.ScreenToClient(hwnd, &point) == win32.FALSE do return win32.HTCLIENT
    client_x := f32(point.x) / scale
    client_y := f32(point.y) / scale

    if _node_contains(_frame.metrics.minimize_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.metrics.maximize_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.metrics.close_button, client_x, client_y) do return win32.HTCLIENT
    if _node_contains(_frame.metrics.caption_node, client_x, client_y) {
        if _active_window.input.hovered != nil {
            ev := events.Mouse_Event{x = auto_cast x, y = auto_cast y, mods = _active_window.input.mods}
            input.dispatch(_active_window.input.hovered, events.MOUSE_LEAVE_EVENT, &ev)
        }
        return win32.HTCAPTION
    }
    return win32.HTCLIENT
}

@(private = "file")
_node_contains :: proc(n: ^node.BaseNode, x, y: f32) -> bool {
    return n != nil && !n.freed && common.rect_intersect(n.rect, x, y)
}

@(private = "file")
_glfw_hwnd :: proc() -> win32.HWND {
    handle := _active_glfw_handle()
    if handle == nil do return nil
    return glfw.GetWin32Window(handle)
}
