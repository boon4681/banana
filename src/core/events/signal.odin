package events;

Phase :: enum {
	None,
	Capture, // root -> target
	Target,
	Bubble, // target -> root
}

Signal :: struct {
	type:                          string,
	target:                        rawptr, // ^Node
	current_target:                rawptr, // ^Node
	phase:                         Phase,
	cancelled:                     bool, // preventDefault
	propagation_stopped:           bool, // stopPropagation
	immediate_propagation_stopped: bool, // stopImmediatePropagation
	data:                          rawptr,
}

stop_propagation :: proc(s: ^Signal) {
	s.propagation_stopped = true
}

stop_immediate_propagation :: proc(s: ^Signal) {
	s.propagation_stopped = true
	s.immediate_propagation_stopped = true
}

prevent_default :: proc(s: ^Signal) {
	s.cancelled = true
}
