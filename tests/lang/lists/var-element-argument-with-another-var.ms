// conform: tags=records,lists,mutation,tier-io,testing
// conform: phase=test
import (
	FileHandle, OpenMode, open, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// A list element passed as a `var` argument moves out of its place, changes in the
// callee and moves back, also when another `var` argument is a different local. A
// native handle has one owner, so a copy of the element faults; a large element copied
// on every call is the same mistake as a cost (a JPEG decode was quadratic in the image
// size).
type Holder {
	handles List[FileHandle] = []
	label String = ""
}

fn adopt(var holder Holder, var count Int, move handle FileHandle) Void {
	holder.handles.append(handle)
	count += 1
}

test "an element and a local are both passed as var" {
	root := temporary("manuscript-var-element-") | expect_ok?
	path := f"{root.path()}/f"
	_written := write_file(path, "x").wait() | expect_ok?
	var holders = [Holder(), Holder()]
	var count = 0
	adopt(holders[1], count, open(path, OpenMode.Read) | expect_ok?)
	(holders[0].handles.length()) | expect_equal(0)?
	(holders[1].handles.length()) | expect_equal(1)?
	count | expect_equal(1)?
}

type Plane {
	cells List[Int]
	steps Int
}

fn advance(var plane Plane, var total Int, at Int) Void {
	plane.cells[at] += 1
	plane.steps += 1
	total += plane.cells[at]
}

test "a large element changes in place with another var argument" {
	var planes = [Plane([0].repeated(1000), 0), Plane([0].repeated(1000), 0)]
	var total = 0
	for i in 0..2000 {
		advance(planes[i % 2], total, i % 1000)
	}
	planes[0].steps | expect_equal(1000)?
	planes[1].steps | expect_equal(1000)?
	total | expect_equal(3000)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
