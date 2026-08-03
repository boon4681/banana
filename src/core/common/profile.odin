package common

import "core:fmt"
import "core:time"

// -define:BANANA_FRAME_PROFILE=true to report where frame time goes.
FRAME_PROFILE :: #config(BANANA_FRAME_PROFILE, false)

Profile_Zone :: enum {
	Poll,
	Dispatch,
	Hit_Test,
	Layout,
	Paint,
	Build_Ctx,
	Node_Draw,
	Text_Draw,
	Submit,
	GPU_Wait,
	Swap,
	Color_Bitmap,
	MSDF_Glyph,
	MSDF_Generate,
	Glyph_Outline,
	Ensure_Shaped,
	Ensure_Lines,
	Auto_Min_Size,
	Yoga_Calculate,
	Cache_Rects,
	Notify_Layout,
	Node_Process,
}

// Counters, not timings: profile_count bumps these and the report prints
// hits/frame so a cache that silently misses every frame is visible.
Profile_Counter :: enum {
	Cache_Hit,
	Miss_Valid,
	Miss_Rect_W,
	Miss_Rect_H,
	Miss_Font,
	Miss_Size,
	Miss_Weight,
	Miss_Line_H,
	Miss_Scale,
	Reline_Invalid,
	Reline_Width,
	Outline_Hit,
	Outline_Miss,
}

@(private = "file", thread_local)
_counters: [Profile_Counter]int

profile_count :: proc(c: Profile_Counter) {
	when FRAME_PROFILE do _counters[c] += 1
}

// One-shot printf for narrowing down why a cache key keeps changing.
@(private = "file", thread_local)
_notes: int

profile_note :: proc(label: string, old, new: f64) {
	when FRAME_PROFILE {
		if _notes >= 8 do return
		_notes += 1
		fmt.printf("  [note] %s: %.6f -> %.6f (delta %.9f)\n", label, old, new, new - old)
	}
}

// -define:BANANA_GPU_SYNC=true inserts a glFinish() before the swap, draining the GPU into the GPU_Wait zone.
GPU_SYNC :: #config(BANANA_GPU_SYNC, false)

@(private = "file")
Zone_Stats :: struct {
	accum:  time.Duration,
	peak:   time.Duration,
	frames: int,
}

@(private = "file", thread_local)
_zones: [Profile_Zone]Zone_Stats

@(private = "file", thread_local)
_span_start: time.Tick

@(private = "file", thread_local)
_report_start: time.Tick

@(private = "file")
REPORT_INTERVAL :: 1.0

profile_begin :: proc(
	zone: Profile_Zone = .Paint,
	loc := #caller_location,
) -> (tick: time.Tick) {
	when FRAME_PROFILE do tick = time.tick_now()
	return
}

@(private = "file")
_ZONE_NAMES := [Profile_Zone]string {
	.Poll      = "Poll",
	.Dispatch  = "Dispatch",
	.Hit_Test  = "Hit_Test",
	.Layout    = "Layout",
	.Paint     = "Paint",
	.Build_Ctx = "Build_Ctx",
	.Node_Draw = "Node_Draw",
	.Text_Draw = "Text_Draw",
	.Submit    = "Submit",
	.GPU_Wait  = "GPU_Wait",
	.Swap      = "Swap",
	.Color_Bitmap  = "Color_Bitmap",
	.MSDF_Glyph    = "MSDF_Glyph",
	.MSDF_Generate = "MSDF_Generate",
	.Glyph_Outline = "Glyph_Outline",
	.Ensure_Shaped = "Ensure_Shaped",
	.Ensure_Lines  = "Ensure_Lines",
	.Auto_Min_Size  = "Auto_Min_Size",
	.Yoga_Calculate = "Yoga_Calculate",
	.Cache_Rects    = "Cache_Rects",
	.Notify_Layout  = "Notify_Layout",
	.Node_Process   = "Node_Process",
}

profile_end :: proc(zone: Profile_Zone, start: time.Tick) {
	when FRAME_PROFILE {
		elapsed := time.tick_since(start)
		z := &_zones[zone]
		z.accum += elapsed
		z.peak = max(z.peak, elapsed)
		z.frames += 1
	}
}

// fmt's numeric width verb zero-pads floats rather than space-padding, which
// makes the columns read as 000.034; right-align by hand instead.
@(private = "file")
_pad :: proc(s: string, width: int) -> string {
	if len(s) >= width do return s
	buf := make([]byte, width, context.temp_allocator)
	pad := width - len(s)
	for i in 0 ..< pad do buf[i] = ' '
	copy(buf[pad:], s)
	return string(buf)
}

// Call once per frame after presenting. Prints a breakdown every second.
profile_frame_end :: proc() {
	when FRAME_PROFILE {
		now := time.tick_now()
		if _report_start == {} {
			_report_start = now
			return
		}
		span := time.duration_seconds(time.tick_diff(_report_start, now))
		if span < REPORT_INTERVAL do return

		frames := _zones[.Paint].frames
		if frames == 0 do frames = 1

		fmt.printf("[frame] %.0f fps  %.3f ms/frame\n", f64(frames) / span, span * 1000 / f64(frames))
		// Submit and Swap both run nested inside Paint, so only the outer zones count toward the total;
        // adding the inner ones would exceed 100%.
		total_measured := 0.0
		for stats, zone in _zones {
			if stats.frames == 0 do continue
			// Per *frame*, not per call: zones like Hit_Test fire several times
			// a frame and a per-call average would understate them.
			avg := time.duration_seconds(stats.accum) / f64(frames)
			top_level := zone == .Poll || zone == .Dispatch || zone == .Layout || zone == .Paint
			// Text_Draw runs inside Node_Draw; indent it one level deeper.
			depth := "    " if zone == .Text_Draw else ""
			if top_level do total_measured += avg
			nested := "" if top_level else "  "
			if depth != "" do nested = depth
			fmt.printf(
				"  %s%-*v %s ms avg  %s ms peak  %s%%  %sx/frame\n",
				nested,
				9 - len(nested),
				zone,
				_pad(fmt.tprintf("%.3f", avg * 1000), 7),
				_pad(fmt.tprintf("%.3f", time.duration_seconds(stats.peak) * 1000), 7),
				_pad(fmt.tprintf("%.1f", (time.duration_seconds(stats.accum) / span) * 100), 5),
				_pad(fmt.tprintf("%.1f", f64(stats.frames) / f64(frames)), 5),
			)
		}
		frame_avg := span / f64(frames)
		fmt.printf(
			"  %-7s %s ms avg  (unmeasured frame time)\n",
			"other",
			_pad(fmt.tprintf("%.3f", (frame_avg - total_measured) * 1000), 7),
		)

		for count, c in _counters {
			if count == 0 do continue
			fmt.printf("  [%v] %s x/frame\n", c, _pad(fmt.tprintf("%.1f", f64(count) / f64(frames)), 6))
		}

		_zones = {}
		_counters = {}
		_report_start = now
	}
}
