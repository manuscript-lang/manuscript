// conform: tags=records,lists,closures,mutation,tier-io,testing
// conform: phase=test
import (
	FileHandle, OpenMode, open, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// Two or more `var` arguments that are different fields of one owned variable move out
// of it, change in the callee and move back, like a single `var` field. A native handle
// has one owner, so a copy of a field faults.
type Pair:
	front: List[FileHandle] = []
	back: List[FileHandle] = []

fn shift(var from: List[FileHandle], var to: List[FileHandle]) Unit:
	if value := from.pop():
		to.append(value)

fn var Pair.rebalance() Unit:
	shift(var self.front, var self.back)

type Words:
	a: List[String] = []
	b: List[String] = []
	count: Int = 0
	c: List[String] = []

fn move_word(var from: List[String], var to: List[String]) Unit:
	if value := from.pop():
		to.append(value)

fn tally(
	var from: List[String],
	var count: Int,
	var to: List[String],
	seen: List[String],
) Unit:
	count += seen.length()
	if value := from.pop():
		to.append(value)

fn var Words.step() Unit:
	move_word(var self.a, var self.b)
	tally(var self.a, var self.count, var self.c, self.b)

test "native handles move between two fields of self":
	root := temporary("manuscript-var-fields-") | expect_ok?
	path := "{root.path()}/f"
	_written := write_file(path, "x").wait() | expect_ok?
	var pair = Pair()
	pair.front.append(open(path, OpenMode.Read) | expect_ok?)
	pair.rebalance()
	(pair.front.length()) | expect_equal(0)?
	(pair.back.length()) | expect_equal(1)?

test "native handles move between two fields of a local":
	root := temporary("manuscript-var-fields-") | expect_ok?
	path := "{root.path()}/f"
	_written := write_file(path, "x").wait() | expect_ok?
	var pair = Pair()
	pair.front.append(open(path, OpenMode.Read) | expect_ok?)
	shift(var pair.front, var pair.back)
	shift(var pair.back, var pair.front)
	(pair.front.length()) | expect_equal(1)?
	(pair.back.length()) | expect_equal(0)?

test "three fields change together and a borrowed field argument reads the current value":
	var words = Words()
	words.a.append("x")
	words.a.append("y")
	words.a.append("z")
	words.step()
	(words.a) | expect_equal(["x"])?
	(words.b) | expect_equal(["z"])?
	(words.count) | expect_equal(1)?
	(words.c) | expect_equal(["y"])?
