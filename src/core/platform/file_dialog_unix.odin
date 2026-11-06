#+build linux, darwin, freebsd, openbsd, netbsd
package platform

import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:strings"

@(private = "file")
_file_dialog :: proc(w: ^Window, opts: File_Dialog_Options, callback: File_Dialog_Callback, user: rawptr) {
    paths := _unix_file_dialog(opts)
    files := make([]Dialog_File, len(paths), context.temp_allocator)
    for path, i in paths do files[i] = {path = path, name = filepath.base(path)}
    callback(w, files, user)
}

@(private = "file")
_unix_file_dialog :: proc(opts: File_Dialog_Options) -> []string {
    when ODIN_OS == .Darwin {
        out, ok := _run({"osascript", "-e", _applescript(opts)})
    } else {
        out, ok := _run(_zenity_command(opts))
        if !ok do out, ok = _run(_kdialog_command(opts))
    }
    if !ok do return nil
    paths := make([dynamic]string, context.temp_allocator)
    for line in strings.split_lines_iterator(&out) {
        if line != "" do append(&paths, line)
    }
    return paths[:]
}

@(private = "file")
_run :: proc(command: []string) -> (string, bool) {
    state, stdout, _, err := os.process_exec({command = command}, context.temp_allocator)
    if err != nil || !state.success || state.exit_code != 0 do return "", false
    return string(stdout), true
}

@(private = "file")
_zenity_command :: proc(opts: File_Dialog_Options) -> []string {
    args := make([dynamic]string, context.temp_allocator)
    append(&args, "zenity", "--file-selection", "--separator=\n")
    switch opts.mode {
    case .Open:
    case .Open_Folder: append(&args, "--directory")
    case .Save:        append(&args, "--save", "--confirm-overwrite")
    }
    if opts.multiple && opts.mode != .Save do append(&args, "--multiple")
    if opts.title != "" do append(&args, fmt.tprintf("--title=%s", opts.title))
    start := _start_path(opts)
    if start != "" do append(&args, fmt.tprintf("--filename=%s", start))
    if opts.mode != .Open_Folder {
        for filter in opts.filters {
            append(&args, fmt.tprintf("--file-filter=%s | %s", filter.name, _patterns(filter, " ")))
        }
    }
    return args[:]
}

@(private = "file")
_kdialog_command :: proc(opts: File_Dialog_Options) -> []string {
    args := make([dynamic]string, context.temp_allocator)
    append(&args, "kdialog")
    if opts.title != "" do append(&args, "--title", opts.title)
    switch opts.mode {
    case .Open:        append(&args, "--getopenfilename")
    case .Open_Folder: append(&args, "--getexistingdirectory")
    case .Save:        append(&args, "--getsavefilename")
    }
    start := _start_path(opts)
    append(&args, start if start != "" else ".")
    if opts.mode != .Open_Folder && len(opts.filters) > 0 {
        filters := make([]string, len(opts.filters), context.temp_allocator)
        for filter, i in opts.filters do filters[i] = fmt.tprintf("%s (%s)", filter.name, _patterns(filter, " "))
        append(&args, strings.join(filters, "|", context.temp_allocator))
    }
    if opts.multiple && opts.mode == .Open do append(&args, "--multiple", "--separate-output")
    return args[:]
}

@(private = "file")
_applescript :: proc(opts: File_Dialog_Options) -> string {
    b := strings.builder_make(context.temp_allocator)
    switch opts.mode {
    case .Open:        strings.write_string(&b, "set picked to choose file")
    case .Open_Folder: strings.write_string(&b, "set picked to choose folder")
    case .Save:        strings.write_string(&b, "set picked to choose file name")
    }
    if opts.title != "" do fmt.sbprintf(&b, " with prompt %s", _quote_applescript(opts.title))
    if opts.folder != "" do fmt.sbprintf(&b, " default location POSIX file %s", _quote_applescript(opts.folder))
    if opts.mode == .Save && opts.file_name != "" do fmt.sbprintf(&b, " default name %s", _quote_applescript(opts.file_name))
    if opts.mode == .Open && len(opts.filters) > 0 {
        strings.write_string(&b, " of type {")
        first := true
        for filter in opts.filters {
            for ext in filter.extensions {
                if !first do strings.write_string(&b, ", ")
                strings.write_string(&b, _quote_applescript(ext))
                first = false
            }
        }
        strings.write_string(&b, "}")
    }
    if opts.multiple && opts.mode != .Save do strings.write_string(&b, " with multiple selections allowed")
    strings.write_string(&b, "\nif class of picked is list then\n")
    strings.write_string(&b, "set out to \"\"\nrepeat with p in picked\nset out to out & POSIX path of p & linefeed\nend repeat\nreturn out\n")
    strings.write_string(&b, "end if\nreturn POSIX path of picked")
    return strings.to_string(b)
}

@(private = "file")
_quote_applescript :: proc(s: string) -> string {
    escaped, _ := strings.replace_all(s, "\\", "\\\\", context.temp_allocator)
    escaped, _ = strings.replace_all(escaped, "\"", "\\\"", context.temp_allocator)
    return fmt.tprintf("\"%s\"", escaped)
}

@(private = "file")
_start_path :: proc(opts: File_Dialog_Options) -> string {
    if opts.folder == "" do return opts.file_name
    folder := opts.folder if strings.has_suffix(opts.folder, "/") else strings.concatenate({opts.folder, "/"}, context.temp_allocator)
    return strings.concatenate({folder, opts.file_name}, context.temp_allocator)
}

@(private = "file")
_patterns :: proc(filter: File_Filter, sep: string) -> string {
    if len(filter.extensions) == 0 do return "*"
    patterns := make([]string, len(filter.extensions), context.temp_allocator)
    for ext, i in filter.extensions do patterns[i] = strings.concatenate({"*.", ext}, context.temp_allocator)
    return strings.join(patterns, sep, context.temp_allocator)
}

FILE_DIALOG :: File_Dialog_Interface {
    file_dialog = _file_dialog
}
