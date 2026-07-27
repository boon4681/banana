#+build !windows
package platform

import "core:fmt"
// Native-frame chrome is Windows-only; elsewhere this is a no-op.

enable_native_frame :: proc(w: ^Window, metrics: Frame_Metrics = DEFAULT_FRAME_METRICS) {
    fmt.println("warning: enable_native_frame is unsupported on this platform and has no-op")
}
