#+build !js
package img

import "core:os"

@(private)
_read_source :: proc(path: string) -> ([]u8, bool) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return nil, false
    return data, true
}
