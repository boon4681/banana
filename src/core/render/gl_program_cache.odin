#+build !js
package render

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:sync"
import gl "vendor:OpenGL"

GL_PROGRAM_CACHE :: #config(BANANA_GL_PROGRAM_CACHE, true)

@(private="file")
_MAGIC :: u32(0x314c4742)

@(private="file")
_Header :: struct #packed {
    magic:  u32,
    format: u32,
    key:    u64,
}

@(private)
_gl_load_program :: proc(name: string, vs, fs: string) -> (program: u32, ok: bool) {
    path, key, usable := _entry(name, vs, fs)
    if usable {
        if program, ok = _read(path, key); ok do return
    }
    program, ok = gl.load_shaders_source(vs, fs, usable)
    if ok && usable do _write(path, key, program)
    return
}

@(private="file")
_entry :: proc(name: string, vs, fs: string) -> (path: string, key: u64, usable: bool) {
    when !GL_PROGRAM_CACHE {
        return
    } else {
        if gl.impl_ProgramBinary == nil || gl.impl_GetProgramBinary == nil || gl.impl_ProgramParameteri == nil do return
        formats: i32
        gl.GetIntegerv(gl.NUM_PROGRAM_BINARY_FORMATS, &formats)
        if formats <= 0 do return

        base, err := os.user_cache_dir(context.temp_allocator)
        if err != nil || len(os.args) == 0 do return
        dir, dir_err := filepath.join({base, "banana", "gl-programs", filepath.stem(os.args[0])}, context.temp_allocator)
        if dir_err != nil do return
        if os.make_directory_all(dir) != nil && !os.is_dir(dir) do return

        gpu := hash.fnv32a(transmute([]u8)string(gl.GetString(gl.VENDOR)))
        gpu = hash.fnv32a(transmute([]u8)string(gl.GetString(gl.RENDERER)), gpu)

        key = hash.fnv64a(transmute([]u8)string(gl.GetString(gl.VERSION)))
        key = hash.fnv64a(transmute([]u8)vs, key)
        key = hash.fnv64a(transmute([]u8)fs, key)

        path_err: runtime.Allocator_Error
        path, path_err = filepath.join({dir, fmt.tprintf("%s-%08x.bin", name, gpu)}, context.temp_allocator)
        return path, key, path_err == nil
    }
}

@(private="file")
_read :: proc(path: string, key: u64) -> (program: u32, ok: bool) {
    blob, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err != nil || len(blob) <= size_of(_Header) do return
    header := (cast(^_Header)raw_data(blob))^
    if header.magic != _MAGIC || header.key != key do return

    binary := blob[size_of(_Header):]
    program = gl.CreateProgram()
    gl.ProgramBinary(program, header.format, raw_data(binary), i32(len(binary)))
    status: i32
    gl.GetProgramiv(program, gl.LINK_STATUS, &status)
    if status == 0 {
        gl.DeleteProgram(program)
        return 0, false
    }
    return program, true
}

@(private="file")
_write :: proc(path: string, key: u64, program: u32) {
    length: i32
    gl.GetProgramiv(program, gl.PROGRAM_BINARY_LENGTH, &length)
    if length <= 0 do return

    blob := make([]u8, size_of(_Header) + int(length), context.temp_allocator)
    header := cast(^_Header)raw_data(blob)
    header.magic = _MAGIC
    header.key = key
    written: i32
    gl.GetProgramBinary(program, length, &written, &header.format, raw_data(blob[size_of(_Header):]))
    if written <= 0 do return

    staging := fmt.tprintf("%s.%d.tmp", path, sync.current_thread_id())
    if os.write_entire_file(staging, blob[:size_of(_Header) + int(written)]) != nil do return
    if os.rename(staging, path) != nil do os.remove(staging)
}
