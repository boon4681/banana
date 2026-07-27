package platform

import "src:core/node"

Frame_Metrics :: struct {
    resize_border:   int,
    caption_node:    ^node.BaseNode,
    minimize_button: ^node.BaseNode,
    maximize_button: ^node.BaseNode,
    close_button:    ^node.BaseNode,
}

DEFAULT_FRAME_METRICS :: Frame_Metrics {
    resize_border = 8,
}
