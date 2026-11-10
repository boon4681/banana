#+build js
package platform

import "src:polyfill"

@(private = "file")
_prefers_dark :: proc() -> bool {
    return polyfill.prefers_dark()
}

COLOR_SCHEME :: Color_Scheme_Interface {
    prefers_dark = _prefers_dark,
}
