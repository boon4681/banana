package common

Rect :: struct {
	x, y, w, h: f32,
}

rect_intersect :: proc {
	rect_point_intersect,
	rect_rect_intersect,
}

rect_point_intersect :: proc(r: Rect, px, py: f32) -> bool {
	return px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h
}

rect_rect_intersect :: proc(a: Rect, b: Rect) -> bool {
	return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}
