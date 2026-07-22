#+build !js
package text;

import "core:os"

@(private)
_native_load_font :: proc(set: ^Font_Set, path: string) {
    if data, err := os.read_entire_file_from_path(path, context.allocator); err == nil {
        set_register(set, data)
        delete(data)
    }
}
