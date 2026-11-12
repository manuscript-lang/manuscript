// conform: tags=testing,tier-io
// conform: phase=test
import (
	FileHandle, OpenMode, open, temporary, append_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Lanes:
	left: List[FileHandle] = []
	right: List[FileHandle] = []
	counts: List[Int] = []

// Moves the last handle of one list onto another, changing both lists and a third.
fn hand_over(var from: List[FileHandle], var to: List[FileHandle], var counts: List[Int]) Unit:
	if handle := from.pop():
		to.append(handle)
		counts.append(to.length())

fn var Lanes.shift() Unit:
	hand_over(var self.left, var self.right, var self.counts)

fn var Lanes.shift_back() Unit:
	hand_over(var self.right, var self.left, var self.counts)

test "changed fields of one record keep their owners without copying":
	tmp := temporary("var-fields-")?
	path := "{tmp.path()}/data"
	append_file(path, "x").wait()?

	var lanes = Lanes()
	for unused in 0..3:
		lanes.left.append(open(path, OpenMode.Read)?)

	lanes.shift()
	lanes.shift()
	lanes.shift_back()
	expect_equal(lanes.left.length(), 2)?
	expect_equal(lanes.right.length(), 1)?
	expect_equal(lanes.counts, [1, 2, 2])?
