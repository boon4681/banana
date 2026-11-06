#+build windows
package platform

import "base:runtime"
import "core:time"
import win32 "core:sys/windows"
import "src:core/input/mouse"

@(private = "file")
RIM_TYPEMOUSE :: 0

@(private = "file")
MOUSE_MOVE_ABSOLUTE :: 0x01

@(private = "file")
MOUSE_VIRTUAL_DESKTOP :: 0x02

// Raw input goes to a message-only window of this thread, not to the GLFW
// window: GLFW drops WM_INPUT unless its own cursor is disabled, and the
// queue is shared, so its pump still hands these messages to us.
@(private = "file", thread_local)
_raw: struct {
    hwnd:       win32.HWND,
    registered: bool,
    absolute:   bool,
    last_x:     i32,
    last_y:     i32,
}

// No RIDEV_INPUTSINK: input arrives only while one of our windows has focus.
@(private)
_raw_mouse_sync :: proc() {
    want := mouse.wanted()
    if want == _raw.registered do return
    if want && _raw.hwnd == nil do _raw.hwnd = _raw_window()
    if _raw.hwnd == nil do return
    device := win32.RAWINPUTDEVICE {
        usUsagePage = win32.HID_USAGE_PAGE_GENERIC,
        usUsage     = win32.HID_USAGE_GENERIC_MOUSE,
        dwFlags     = 0 if want else win32.RIDEV_REMOVE,
        hwndTarget  = _raw.hwnd if want else nil,
    }
    if win32.RegisterRawInputDevices(&device, 1, size_of(device)) == win32.FALSE do return
    _raw.registered = want
    _raw.absolute = false
}

// Takes what queued since the last pump in one batch, so the pump that
// follows has no WM_INPUT left to dispatch one by one.
@(private)
_raw_mouse_read :: proc() {
    if !_raw.registered do return
    buffer: [64]win32.RAWINPUT
    now := time.tick_now()
    for {
        size := win32.UINT(size_of(buffer))
        count := win32.GetRawInputBuffer(&buffer[0], &size, size_of(win32.RAWINPUTHEADER))
        if count == 0 || count == ~win32.UINT(0) do break
        block := &buffer[0]
        for _ in 0 ..< count {
            _raw_mouse_push(block, now)
            block = win32.NEXTRAWINPUTBLOCK(block)
        }
    }
}

@(private = "file")
_raw_mouse_push :: proc(input: ^win32.RAWINPUT, at: time.Tick) {
    if input.header.dwType != RIM_TYPEMOUSE do return
    m := &input.data.mouse
    if m.usFlags & MOUSE_MOVE_ABSOLUTE == 0 {
        if m.lLastX != 0 || m.lLastY != 0 do mouse.push(f64(m.lLastX), f64(m.lLastY), at)
        return
    }
    // Remote desktop, tablets and VMs report a position in 0..65535 instead.
    virtual := m.usFlags & MOUSE_VIRTUAL_DESKTOP != 0
    w := win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN if virtual else win32.SM_CXSCREEN)
    h := win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN if virtual else win32.SM_CYSCREEN)
    x := i32(f64(m.lLastX) / 65535 * f64(w))
    y := i32(f64(m.lLastY) / 65535 * f64(h))
    if _raw.absolute && (x != _raw.last_x || y != _raw.last_y) {
        mouse.push(f64(x - _raw.last_x), f64(y - _raw.last_y), at)
    }
    _raw.absolute = true
    _raw.last_x, _raw.last_y = x, y
}

@(private = "file")
_raw_window :: proc() -> win32.HWND {
    instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
    class: cstring16 = "banana_raw_mouse"
    info: win32.WNDCLASSEXW
    if win32.GetClassInfoExW(instance, class, &info) == win32.FALSE {
        info = win32.WNDCLASSEXW {
            cbSize        = size_of(win32.WNDCLASSEXW),
            lpfnWndProc   = _raw_proc,
            hInstance     = instance,
            lpszClassName = class,
        }
        if win32.RegisterClassExW(&info) == 0 do return nil
    }
    return win32.CreateWindowExW(0, class, nil, 0, 0, 0, 0, 0, win32.HWND_MESSAGE, nil, instance, nil)
}

@(private = "file")
_raw_proc :: proc "system" (
    hwnd:   win32.HWND,
    msg:    win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) -> win32.LRESULT {
    if msg == win32.WM_INPUT {
        context = runtime.default_context()
        input: win32.RAWINPUT
        size := win32.UINT(size_of(input))
        read := win32.GetRawInputData(win32.HRAWINPUT(lparam), win32.RID_INPUT, &input, &size, size_of(win32.RAWINPUTHEADER))
        if read != ~win32.UINT(0) && read > 0 do _raw_mouse_push(&input, time.tick_now())
    }
    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

