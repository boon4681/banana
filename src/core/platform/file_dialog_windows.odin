#+build windows
package platform

import "core:path/filepath"
import "core:strings"
import win32 "core:sys/windows"

@(private = "file")
_file_dialog :: proc(w: ^Window, opts: File_Dialog_Options, callback: File_Dialog_Callback, user: rawptr) {
    paths := _win32_file_dialog(opts)
    files := make([]Dialog_File, len(paths), context.temp_allocator)
    for path, i in paths do files[i] = {path = path, name = filepath.base(path)}
    callback(w, files, user)
}

@(private = "file")
_win32_file_dialog :: proc(opts: File_Dialog_Options) -> []string {
    initialized := win32.SUCCEEDED(win32.CoInitializeEx(nil, .APARTMENTTHREADED))
    defer if initialized do win32.CoUninitialize()

    save := opts.mode == .Save
    clsid := win32.CLSID_FileSaveDialog if save else win32.CLSID_FileOpenDialog
    iid := win32.IID_IFileSaveDialog if save else win32.IID_IFileOpenDialog
    dialog: ^win32.IFileDialog
    if win32.FAILED(win32.CoCreateInstance(clsid, nil, win32.CLSCTX_INPROC_SERVER, iid, cast(^rawptr)&dialog)) {
        return nil
    }
    defer dialog->Release()

    fos: win32.FILEOPENDIALOGOPTIONS
    dialog->GetOptions(&fos)
    fos |= win32.FOS_FORCEFILESYSTEM
    switch opts.mode {
    case .Open:        fos |= win32.FOS_FILEMUSTEXIST
    case .Open_Folder: fos |= win32.FOS_PICKFOLDERS
    case .Save:        fos |= win32.FOS_OVERWRITEPROMPT
    }
    if opts.multiple && !save do fos |= win32.FOS_ALLOWMULTISELECT
    dialog->SetOptions(fos)

    if opts.title != "" do dialog->SetTitle(win32.utf8_to_wstring(opts.title))
    if save && opts.file_name != "" do dialog->SetFileName(win32.utf8_to_wstring(opts.file_name))
    if opts.folder != "" {
        folder: ^win32.IShellItem
        if win32.SUCCEEDED(win32.SHCreateItemFromParsingName(win32.utf8_to_wstring(opts.folder), nil, win32.IID_IShellItem, cast(^rawptr)&folder)) {
            dialog->SetFolder(folder)
            folder->Release()
        }
    }
    if len(opts.filters) > 0 && opts.mode != .Open_Folder {
        specs := make([]win32.COMDLG_FILTERSPEC, len(opts.filters), context.temp_allocator)
        for filter, i in opts.filters {
            patterns := make([]string, len(filter.extensions), context.temp_allocator)
            for ext, j in filter.extensions do patterns[j] = strings.concatenate({"*.", ext}, context.temp_allocator)
            spec := strings.join(patterns, ";", context.temp_allocator) if len(patterns) > 0 else "*.*"
            specs[i] = {win32.utf8_to_wstring(filter.name), win32.utf8_to_wstring(spec)}
        }
        dialog->SetFileTypes(u32(len(specs)), raw_data(specs))
        if save && len(opts.filters[0].extensions) > 0 {
            dialog->SetDefaultExtension(win32.utf8_to_wstring(opts.filters[0].extensions[0]))
        }
    }

    if win32.FAILED(dialog->Show(win32.GetActiveWindow())) do return nil

    if save {
        item: ^win32.IShellItem
        if win32.FAILED(dialog->GetResult(&item)) do return nil
        defer item->Release()
        path, ok := _shell_item_path(item)
        if !ok do return nil
        paths := make([]string, 1, context.temp_allocator)
        paths[0] = path
        return paths
    }

    items: ^win32.IShellItemArray
    if win32.FAILED((cast(^win32.IFileOpenDialog)dialog)->GetResults(&items)) do return nil
    defer items->Release()
    count: win32.DWORD
    items->GetCount(&count)
    paths := make([dynamic]string, 0, count, context.temp_allocator)
    for i in 0 ..< count {
        item: ^win32.IShellItem
        if win32.FAILED(items->GetItemAt(i, &item)) do continue
        if path, ok := _shell_item_path(item); ok do append(&paths, path)
        item->Release()
    }
    return paths[:]
}

@(private = "file")
_shell_item_path :: proc(item: ^win32.IShellItem) -> (string, bool) {
    name: win32.LPWSTR
    if win32.FAILED(item->GetDisplayName(.FILESYSPATH, &name)) do return "", false
    defer win32.CoTaskMemFree(name)
    path, err := win32.wstring_to_utf8(win32.wstring(name), -1, context.temp_allocator)
    return path, err == nil
}

FILE_DIALOG :: File_Dialog_Interface {
    file_dialog = _file_dialog
}
