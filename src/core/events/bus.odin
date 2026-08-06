package events

// Bus
@(private = "file")
_Listener_Id :: distinct u64

Callback     :: proc(s: ^Event_Signal)

Listener :: struct {
    id:       _Listener_Id,
    callback: Callback,
    capture:  bool, // fires in capture phase rather than bubble
    once:     bool,
}

Bus :: struct {
    listeners:        map[string][dynamic]Listener,
    next_listener_id: u64,
}

bus_init :: proc(b: ^Bus) {
    if b == nil do return
    b.listeners = make(map[string][dynamic]Listener)
    b.next_listener_id = 0
}

bus_destroy :: proc(b: ^Bus) {
    if b == nil || b.listeners == nil do return
    for _, list in b.listeners do delete(list)
    delete(b.listeners)
    b^ = {}
}

// reserve for odin component
// library level api; Do not use if you dont know what are you doing
// if you using banana, calling this on windows.bus can by pass and make event ordering a mess
on :: proc(
	b: ^Bus,
	type: string,
	callback: Callback,
	capture := false,
	once := false,
) -> uint {
    if callback == nil do return 0
    return _add_listener(b, type, callback, capture, once)
}

@(private = "file")
_add_listener :: proc(
	b: ^Bus,
	type: string,
	callback: Callback,
	capture: bool,
	once: bool,
) -> uint {
    if b == nil do return 0
    if b.listeners == nil do b.listeners = make(map[string][dynamic]Listener)

    b.next_listener_id += 1
    if b.next_listener_id == 0 do b.next_listener_id = 1
    id := _Listener_Id(b.next_listener_id)

    list, ok := &b.listeners[type]
    if !ok {
        b.listeners[type] = make([dynamic]Listener)
        list = &b.listeners[type]
    }
    append(list, Listener {
        id       = id,
        callback = callback,
        capture  = capture,
        once     = once,
    })
    return uint(len(list^))
}

// Same as events.on
// Removes every registration of callback for this event type.
off :: proc(b: ^Bus, type: string, callback: Callback) {
    if b == nil || b.listeners == nil || callback == nil do return
    list, ok := &b.listeners[type]
    if !ok do return
    for i := len(list^) - 1; i >= 0; i -= 1 {
        if list[i].callback == callback do ordered_remove(list, i)
    }
    if len(list^) == 0 {
        delete(list^)
        delete_key(&b.listeners, type)
    }
}

@(private = "file")
_off_id :: proc(b: ^Bus, type: string, id: _Listener_Id) {
    if b == nil || b.listeners == nil do return
    list, ok := &b.listeners[type]
    if !ok do return
    for listener, i in list^ {
        if listener.id != id do continue
        ordered_remove(list, i)
        if len(list^) == 0 {
            delete(list^)
            delete_key(&b.listeners, type)
        }
        return
    }
}

@(private = "file")
_listener :: proc(b: ^Bus, type: string, id: _Listener_Id) -> (Listener, bool) {
    list, ok := b.listeners[type]
    if !ok do return {}, false
    for listener in list {
        if listener.id == id do return listener, true
    }
    return {}, false
}

// Fire listeners registered on THIS bus for the current phase. Returns false if
// immediate propagation was stopped (caller should halt the walk).
emit_local :: proc(b: ^Bus, s: ^Event_Signal) -> (continue_walk: bool) {
    if b == nil || b.listeners == nil do return true
    list, ok := &b.listeners[s.type]
    if !ok do return true

    want_capture := s.phase == .Capture
    ids := make([dynamic]_Listener_Id, 0, len(list), context.temp_allocator)
    for listener in list {
        if listener.capture == want_capture || s.phase == .Target {
            append(&ids, listener.id)
        }
    }

    for id in ids {
        l, still_registered := _listener(b, s.type, id)
        if !still_registered do continue
        if l.once do _off_id(b, s.type, id)
        l.callback(s)
        if s.immediate_propagation_stopped do return false
    }
    return true
}
