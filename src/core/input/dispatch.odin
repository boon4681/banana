package input

import "src:core/events"
import "src:core/hit_test"

dispatch :: proc(target: ^Node, type: string, data: rawptr = nil) -> events.Event_Signal {
	s := events.Event_Signal {
		type   = type,
		target = target,
		data   = data,
	}
	if target == nil do return s

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
	return s
}
