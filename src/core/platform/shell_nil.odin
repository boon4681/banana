#+build !windows
package platform

import "core:fmt"

SHELL :: Shell_Interface {
    set_taskbar_visible = proc(w: ^Window, visible: bool) {
        if !visible do fmt.println("warning: set_taskbar_visible is unsupported on this platform and has no effect")
    },
    tray_create = proc(t: ^Tray) -> bool {
        fmt.println("warning: tray_create is unsupported on this platform")
        return false
    },
    tray_update   = proc(t: ^Tray) {},
    tray_destroy  = proc(t: ^Tray) {},
    forget_window = proc(w: ^Window) {},
    minimize      = proc(w: ^Window) -> bool { return false },
}
