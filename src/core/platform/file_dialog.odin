package platform

file_dialog :: proc(w: ^Window, opts: File_Dialog_Options, callback: File_Dialog_Callback, user: rawptr = nil) {
    if w == nil || callback == nil do return
    FILE_DIALOG.file_dialog(w, opts, callback, user)
}
