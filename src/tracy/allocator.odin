#+build !js
package tracy

import "base:runtime"
import "core:c"
import "core:mem"

// Usage in a program entry point:
//
//	```odin
// prof: tracy.Profiled_Allocator
//	tracy.profiled_allocator_init(&prof, context.allocator)
//	context.allocator = tracy.profiled_allocator(&prof)
// ```
// The `name` field opts into Tracy's named memory pools, so the glyph atlas or
// a per-frame arena can be tracked as its own pool rather than being mixed into
// the global one. Leave it nil for the default pool.
Profiled_Allocator :: struct {
	backing: mem.Allocator,
	// Must outlive the allocator: Tracy stores the pointer, not a copy.
	name:    cstring,
	secure:  bool,
}

profiled_allocator_init :: proc(
	pa:      ^Profiled_Allocator,
	backing: mem.Allocator,
	name:    cstring = nil,
	secure:  bool = false,
) {
	pa^ = {backing = backing, name = name, secure = secure}
}

profiled_allocator :: proc(pa: ^Profiled_Allocator) -> mem.Allocator {
	when TRACY_ENABLE {
		return mem.Allocator{procedure = profiled_allocator_proc, data = pa}
	} else {
		return pa.backing
	}
}

@(private = "file")
_emit_alloc :: #force_inline proc(pa: ^Profiled_Allocator, ptr: rawptr, size: int) {
	if ptr == nil || size <= 0 do return
	if pa.name != nil {
		AllocN(ptr, c.size_t(size), pa.name)
	} else if pa.secure {
		SecureAlloc(ptr, c.size_t(size))
	} else {
		Alloc(ptr, c.size_t(size))
	}
}

@(private = "file")
_emit_free :: #force_inline proc(pa: ^Profiled_Allocator, ptr: rawptr) {
	if ptr == nil do return
	if pa.name != nil {
		FreeN(ptr, pa.name)
	} else if pa.secure {
		SecureFree(ptr)
	} else {
		Free(ptr)
	}
}

profiled_allocator_proc :: proc(
	allocator_data: rawptr,
	mode:           mem.Allocator_Mode,
	size:           int,
	alignment:      int,
	old_memory:     rawptr,
	old_size:       int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	pa := (^Profiled_Allocator)(allocator_data)

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		result, err := pa.backing.procedure(
			pa.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
		if err == nil do _emit_alloc(pa, raw_data(result), len(result))
		return result, err

	case .Free:
		// Reported before the call so a Tracy-side double-free shows the offending
		// pointer even when the backing allocator aborts on it.
		_emit_free(pa, old_memory)
		return pa.backing.procedure(
			pa.backing.data, mode, size, alignment, old_memory, old_size, location,
		)

	case .Free_All:
		// Tracy tracks individual pointers and has no bulk-release event, so an
		// arena reset would leave every block it owned marked as live forever.
		// Named pools sidestep this by keeping such an allocator out of the global
		// pool; unnamed ones are best left un-freed-all while profiling.
		return pa.backing.procedure(
			pa.backing.data, mode, size, alignment, old_memory, old_size, location,
		)

	case .Resize, .Resize_Non_Zeroed:
		// A resize is a free plus an alloc as far as Tracy is concerned. Emitting
		// the free first matters when the backing allocator grows in place and
		// hands back the same pointer -- the reverse order would look like an
		// alloc of an already-live address.
		_emit_free(pa, old_memory)
		result, err := pa.backing.procedure(
			pa.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
		if err == nil {
			_emit_alloc(pa, raw_data(result), len(result))
		} else {
			// The block survives a failed resize, so put it back on Tracy's books.
			_emit_alloc(pa, old_memory, old_size)
		}
		return result, err

	case .Query_Features, .Query_Info:
		return pa.backing.procedure(
			pa.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
	}

	return nil, .Mode_Not_Implemented
}
