#+build js
package inspector

import "src:core/node"
import "src:core/platform"

// TODO off thread windows management for the web

Options :: struct {
    width:        int,
    height:       int,
    title:        cstring,
    font_paths:   []string,
    overlay_font: ^node.Font,
    refresh:      f32,
}

Inspector :: struct {}

New :: proc(app: ^platform.Window, opts: Options = {}) -> ^Inspector { return nil }
destroy  :: proc(insp: ^Inspector) {}
update  :: proc(insp: ^Inspector) {}
open  :: proc(insp: ^Inspector) -> bool { return false }
