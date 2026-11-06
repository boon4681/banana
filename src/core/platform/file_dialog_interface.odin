package platform

File_Dialog_Mode :: enum {
    Open,
    Open_Folder,
    Save,
}

File_Filter :: struct {
    name:       string,
    extensions: []string,
}

File_Dialog_Options :: struct {
    mode:      File_Dialog_Mode,
    title:     string,
    multiple:  bool,
    filters:   []File_Filter,
    folder:    string,
    file_name: string,
}

Dialog_File :: struct {
    path: string,
    name: string,
    data: []byte,
}

File_Dialog_Callback :: proc(w: ^Window, files: []Dialog_File, user: rawptr)

File_Dialog_Interface :: struct {
    file_dialog: proc(w: ^Window, opts: File_Dialog_Options, callback: File_Dialog_Callback, user: rawptr = nil)
}
