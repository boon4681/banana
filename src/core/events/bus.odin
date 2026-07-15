package events

// Bus
Listener :: struct {
	callback: proc(s: ^Signal),
	capture:  bool, // fires in capture phase rather than bubble
	once:     bool,
}

Bus :: struct {
	listeners: map[string][dynamic]Listener,
}

bus_init :: proc(b: ^Bus) {
	b.listeners = make(map[string][dynamic]Listener)
}

bus_destroy :: proc(b: ^Bus) {
	for _, list in b.listeners do delete(list)
	delete(b.listeners)
}

on :: proc(
	b: ^Bus,
	type: string,
	callback: proc(s: ^Signal),
	capture := false,
	once := false,
) -> uint {
	list, ok := &b.listeners[type]
	if !ok {
		b.listeners[type] = make([dynamic]Listener)
		list = &b.listeners[type]
	}
	append(list, Listener{callback = callback, capture = capture, once = once})
	return len(list)
}

off :: proc(b: ^Bus, type: string, callback: proc(s: ^Signal)) {
	list, ok := &b.listeners[type]
	if !ok do return
	for i := len(list) - 1; i >= 0; i -= 1 {
		if list[i].callback == callback do ordered_remove(list, i)
	}
}

// Fire listeners registered on THIS bus for the current phase. Returns false if
// immediate propagation was stopped (caller should halt the walk).
emit_local :: proc(b: ^Bus, s: ^Signal) -> (continue_walk: bool) {
	list, ok := &b.listeners[s.type]
	if !ok do return true

	want_capture := s.phase == .Capture
	i := 0
	for i < len(list) {
		l := list[i]
		matches := l.capture == want_capture || s.phase == .Target
		if matches {
			l.callback(s)
			if l.once {
				ordered_remove(list, i)
				if s.immediate_propagation_stopped do return false
				continue
			}
		}
		if s.immediate_propagation_stopped do return false
		i += 1
	}
	return true
}
