#+build js
package text

import "src:polyfill"
@(private)
_web_load_font :: proc(set: ^Font_Set, path: string, index := 0) -> ^Face {
    data := polyfill.load_asset(path, context.temp_allocator)
    if data == nil do return nil
    return set_register(set, data, index) // it clones the bytes it keeps
}
