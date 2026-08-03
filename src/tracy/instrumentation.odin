#+build !js
package tracy

import "base:runtime"

// Blanket profiling: with -define:TRACY_AUTO=true the Odin compiler emits a call
// to the enter/exit hooks below at the top and bottom of every procedure in the
// program, opening a Tracy zone for each.
//
// This method is a steal from https://github.com/laytan/back
// for odin backtraces.
//
// Build requirements inherited from that mechanism:
//   -o:minimal or higher   (#force_inline must actually inline)
//   -use-single-module     (instrumentation across modules miscompiles)
//
// Odin permits only ONE @(instrumentation_enter) procedure per program. If
// something else in the build needs to own that attribute, set
// 
//   -define:TRACY_CUSTOM_INSTRUMENTATION=true
//
// and call auto_zone_enter/exit from your own hook instead (it must be #force_inline).
TRACY_AUTO :: #config(TRACY_AUTO, false)

TRACY_CUSTOM_INSTRUMENTATION :: #config(TRACY_CUSTOM_INSTRUMENTATION, false)

// Zones deeper than this are dropped rather than overflowing the stack buffer.
// Layout and paint recurse over the node tree, so this needs headroom.
TRACY_AUTO_MAX_DEPTH :: #config(TRACY_AUTO_MAX_DEPTH, 1024)

when TRACY_AUTO {

when !TRACY_ENABLE {
	#panic("-define:TRACY_AUTO=true requires -define:TRACY_ENABLE=true")
}

when ODIN_OPTIMIZATION_MODE == .None {
	#panic("tracy auto-instrumentation requires at least -o:minimal (it requires `#force_inline` to actually be applied)")
}

when ODIN_USE_SEPARATE_MODULES {
	#panic("tracy auto-instrumentation requires -use-single-module")
}

// Tracy's zone end takes the context returned by zone begin, so unlike `back`'s
// intrusive linked list of stack frames this has to be indexed storage.
@(thread_local, private="file")
zones: [TRACY_AUTO_MAX_DEPTH]ZoneCtx

// Counts every entered procedure, including those past the buffer. Exit
// decrements symmetrically, so an overflow drops zones instead of mispairing the
// ones below it.
@(thread_local, private="file")
depth: int

// Emitting a zone runs code that is itself reachable from instrumented
// procedures -- the Tracy client's lazy first-touch initialisation, and Odin's
// own thread-local setup helpers on Windows -- which re-enters these hooks and
// overflows the stack before the first frame is ever drawn. This flag is read
// before anything else so the re-entrant path returns immediately.
@(thread_local, private="file")
emitting: bool

// Tracy allows at most 32K source locations for the whole session, and
// ___tracy_alloc_srcloc mints a fresh one on every call -- under blanket
// instrumentation that ceiling is reached within a couple of seconds and the
// server drops the connection ("Too many source locations").
//
// A call site always passes the *same* string literals, so the address of
// loc.file_path plus the line number identifies it uniquely and cheaply. Each
// site therefore allocates one persistent SourceLocationData, reused for every
// subsequent hit, which keeps the total at "number of instrumented call sites"
// rather than "number of calls".
@(private="file")
SRCLOC_CACHE_SIZE :: 1 << 16

@(private="file")
Srcloc_Slot :: struct {
	key:    uintptr,
	line:   i32,
	data:   ^SourceLocationData,
}

// Open-addressed and shared across threads. Two threads racing on the same call
// site can each build a SourceLocationData; both describe the same location, so
// the loser simply leaks one slot-sized allocation rather than corrupting state.
@(private="file")
srcloc_cache: [SRCLOC_CACHE_SIZE]Srcloc_Slot

// Backing store for the cached location data. Fixed and never freed: these must
// outlive every zone that references them, i.e. the whole process.
@(private="file")
srcloc_pool: [SRCLOC_CACHE_SIZE]SourceLocationData

@(private="file")
srcloc_pool_used: int

// Zone tint, derived from the call site's file path and procedure name.
//
// Keyed on the string *contents* rather than the pointers `srcloc_for` caches
// on: literal addresses shift between builds, and a colour that changes every
// run is worse than no colour at all. Only runs on a cache miss, i.e. once per
// call site, so the per-byte cost never appears on a hot path.
//
// Both strings feed one hash so every procedure gets its own hue while procs
// sharing a file stay in adjacent territory.
@(no_instrumentation, private="file")
srcloc_color :: proc "contextless" (file, procedure: string) -> u32 {
	hash: u64 = 0xCBF29CE484222325
	for i in 0 ..< len(file) {
		hash ~= u64(file[i])
		hash *= 0x100000001B3
	}
	for i in 0 ..< len(procedure) {
		hash ~= u64(procedure[i])
		hash *= 0x100000001B3
	}

	hash ~= hash >> 33
	hash *= 0xFF51AFD7ED558CCD
	hash ~= hash >> 33

	HUE_SLOTS :: 24
	GOLDEN_ANGLE :: f32(137.507764)
	hue := f32(hash % HUE_SLOTS) * GOLDEN_ANGLE
	for hue >= 360 do hue -= 360
	sat :: f32(0.45)
	val :: f32(0.85)

	c := val * sat
	h := hue / 60
	x := c * (1 - abs(h - f32(2 * int(h / 2)) - 1))
	m := val - c

	r, g, b: f32
	switch int(h) {
	case 0: r, g, b = c, x, 0
	case 1: r, g, b = x, c, 0
	case 2: r, g, b = 0, c, x
	case 3: r, g, b = 0, x, c
	case 4: r, g, b = x, 0, c
	case:   r, g, b = c, 0, x
	}

	return u32((r + m) * 255) << 16 | u32((g + m) * 255) << 8 | u32((b + m) * 255)
}

@(no_instrumentation, private="file")
srcloc_for :: #force_inline proc "contextless" (loc: runtime.Source_Code_Location) -> ^SourceLocationData {
	key := uintptr(raw_data(loc.file_path))

	hash := u64(key) ~ (u64(loc.line) * 0x9E3779B97F4A7C15)
	hash ~= hash >> 29
	hash *= 0xBF58476D1CE4E5B9
	hash ~= hash >> 32
	idx := int(hash & u64(SRCLOC_CACHE_SIZE - 1))

	// Linear probe; the cache is sized well above the number of call sites in a
	// program this size, so a full table is not a realistic case.
	for _ in 0 ..< 64 {
		slot := &srcloc_cache[idx]
		if slot.data != nil {
			if slot.key == key && slot.line == loc.line {
				return slot.data
			}
			idx = (idx + 1) & (SRCLOC_CACHE_SIZE - 1)
			continue
		}

		if srcloc_pool_used >= SRCLOC_CACHE_SIZE {
			return nil
		}
		data := &srcloc_pool[srcloc_pool_used]
		srcloc_pool_used += 1

		// Odin string literals are not NUL-terminated in general,
        // but those in a Source_Code_Location are emitted as C-compatible constants,
        // so handing the pointer straight to Tracy is safe and avoids copying per site.
		data.name = nil
		data.function = cstring(raw_data(loc.procedure))
		data.file = cstring(raw_data(loc.file_path))
		data.line = u32(loc.line)
		data.color = srcloc_color(loc.file_path, loc.procedure)

		slot.key = key
		slot.line = loc.line
		slot.data = data
		return data
	}
	return nil
}

@(no_instrumentation)
auto_zone_enter :: #force_inline proc "contextless" (loc: runtime.Source_Code_Location) {
	if emitting {
		return
	}
	emitting = true
	if depth >= 0 && depth < TRACY_AUTO_MAX_DEPTH {
		if data := srcloc_for(loc); data != nil {
			// Bypasses the ZoneBegin wrapper: it is a plain `proc` and this hook is `contextless`,
            // so calling it would mean materialising a context on every procedure entry in the program.
			zones[depth] = ___tracy_emit_zone_begin(data, true)
		} else {
			zones[depth] = {}
		}
	}
	depth += 1
	emitting = false
}

@(no_instrumentation)
auto_zone_exit :: #force_inline proc "contextless" (loc: runtime.Source_Code_Location) {
	if emitting {
		return
	}
	emitting = true
	depth -= 1
	if depth >= 0 && depth < TRACY_AUTO_MAX_DEPTH {
		// A zeroed context is what enter leaves behind when the srcloc cache is exhausted; no zone was opened, so none may be closed.
		if zones[depth].active {
			___tracy_emit_zone_end(zones[depth])
		}
	}
	emitting = false
}

when !TRACY_CUSTOM_INSTRUMENTATION {
	@(instrumentation_enter, no_instrumentation, private="file")
	_auto_enter :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		auto_zone_enter(loc)
	}

	@(instrumentation_exit, no_instrumentation, private="file")
	_auto_exit :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		auto_zone_exit(loc)
	}
}

}
