package wasm_test

import "core:fmt"
import "core:os"
import yoga "src:yoga"

expect :: proc(ok: ^bool, what: string, got, want: f32) {
	if got != want {
		fmt.eprintfln("FAIL: %s: got %v, want %v", what, got, want)
		ok^ = false
	}
}

main :: proc() {
	root := yoga.NodeNew()
	defer yoga.NodeFreeRecursive(root)

	yoga.NodeStyleSetWidth(root, 100)
	yoga.NodeStyleSetHeight(root, 100)
	yoga.NodeStyleSetFlexDirection(root, .Row)

	child0 := yoga.NodeNew()
	yoga.NodeStyleSetFlexGrow(child0, 1)
	yoga.NodeInsertChild(root, child0, 0)

	child1 := yoga.NodeNew()
	yoga.NodeStyleSetFlexGrow(child1, 1)
	yoga.NodeInsertChild(root, child1, 1)

	yoga.NodeCalculateLayout(root, 100, 100, .LTR)

	ok := true
	expect(&ok, "root width", yoga.NodeLayoutGetWidth(root), 100)
	expect(&ok, "root height", yoga.NodeLayoutGetHeight(root), 100)
	expect(&ok, "child0 left", yoga.NodeLayoutGetLeft(child0), 0)
	expect(&ok, "child0 width", yoga.NodeLayoutGetWidth(child0), 50)
	expect(&ok, "child1 left", yoga.NodeLayoutGetLeft(child1), 50)
	expect(&ok, "child1 width", yoga.NodeLayoutGetWidth(child1), 50)

	if !ok {
		os.exit(1)
	}
	fmt.println("wasm test passed")
}
