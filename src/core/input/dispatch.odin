package input

import "src:core/events"
import "src:core/hit_test"

dispatch :: proc(target: ^Node, type: string, data: rawptr = nil) -> events.Event_Signal {
	state := _active_input_state
	window_bus: ^events.Bus
	window_target: rawptr
	if state != nil {
		window_bus = state.window_bus
		window_target = state.window_target
	}

	s := events.Event_Signal {
		type   = type,
		target = target if target != nil else window_target,
		data   = data,
	}

	// With no node hit/focused, the Window itself is the target.
	if target == nil {
		if window_bus == nil || window_target == nil do return s
		s.phase = .Target
		s.current_target = window_target
		events.emit_local(window_bus, &s)
		return s
	}

	// The Window is the outermost capture/bubble boundary around the node tree.
	if window_bus != nil && window_target != nil {
		s.phase = .Capture
		s.current_target = window_target
		if !events.emit_local(window_bus, &s) do return s
		if s.propagation_stopped do return s
	}

	chain := hit_test.ancestor_chain(target)

	// Capture: root -> target's parent.
	s.phase = .Capture
	for i in 0 ..< len(chain) - 1 {
		n := chain[i]
		s.current_target = n
		if !events.emit_local(&n.bus, &s) do return s
		if s.propagation_stopped do return s
	}

	// Target.
	s.phase = .Target
	s.current_target = target
	if !events.emit_local(&target.bus, &s) do return s
	if s.propagation_stopped do return s

	// Bubble: target's parent -> root.
	s.phase = .Bubble
	for i := len(chain) - 2; i >= 0; i -= 1 {
		n := chain[i]
		s.current_target = n
		if !events.emit_local(&n.bus, &s) do return s
		if s.propagation_stopped do return s
	}

	if window_bus != nil && window_target != nil {
		s.phase = .Bubble
		s.current_target = window_target
		events.emit_local(window_bus, &s)
	}
	return s
}
