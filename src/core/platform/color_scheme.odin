package platform

// true when the user picked a dark theme for their system or browser
// cheap enough to ask every frame, the platforms that read a setting cache it
prefers_dark :: proc() -> bool {
    return COLOR_SCHEME.prefers_dark()
}
