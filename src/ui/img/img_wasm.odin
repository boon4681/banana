#+build js
package img

import "src:polyfill"

@(private)
_read_source :: proc(path: string) -> ([]u8, bool) {
    data := polyfill.load_asset(path, context.allocator)
    if data == nil do return nil, false
    return data, true
}
