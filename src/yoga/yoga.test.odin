#+build !wasm32
package yoga

import "core:testing"

@(test)
yoga_test :: proc(t: ^testing.T) {
	root := NodeNew()
	defer NodeFreeRecursive(root)

	NodeStyleSetWidth(root, 100)
	NodeStyleSetHeight(root, 100)
	NodeStyleSetFlexDirection(root, .Row)

	child0 := NodeNew()
	NodeStyleSetFlexGrow(child0, 1)
	NodeInsertChild(root, child0, 0)

	child1 := NodeNew()
	NodeStyleSetFlexGrow(child1, 1)
	NodeInsertChild(root, child1, 1)

	NodeCalculateLayout(root, 100, 100, .LTR)

	testing.expect_value(t, NodeLayoutGetWidth(root), 100)
	testing.expect_value(t, NodeLayoutGetHeight(root), 100)

	testing.expect_value(t, NodeLayoutGetLeft(child0), 0)
	testing.expect_value(t, NodeLayoutGetWidth(child0), 50)

	testing.expect_value(t, NodeLayoutGetLeft(child1), 50)
	testing.expect_value(t, NodeLayoutGetWidth(child1), 50)
}
