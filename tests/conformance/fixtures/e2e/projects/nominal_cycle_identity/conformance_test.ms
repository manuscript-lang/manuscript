import (
	read_file, remove, temporary_directory, temporary_root from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	exercise from "./outer.ms",
	exercise_shared from "./shared.ms",
)

test "same display names keep nested resource cleanup":
	path := "{ temporary_root()?}/ms-nominal-cycle-identity.txt"
	_gone := remove(path, false)
	exercise(path.clone())

	seen := read_file(path.clone(), none).wait()?
	_cleaned := remove(path, false)
	seen.length() | expect_equal(1)?

fn expect_closed(path: String) Unit!:
	seen := read_file(path.clone(), none).wait()?
	_cleaned := remove(path, false)
	expect_equal(seen.length(), 1)?

test "shared generic field types keep cleanup for each value":
	root := temporary_directory("ms-shared-classification")?
	first := "{root}/ms-shared-first.txt"
	second := "{root}/ms-shared-second.txt"
	third := "{root}/ms-shared-third.txt"
	fourth := "{root}/ms-shared-fourth.txt"
	exercise_shared(first.clone(), second.clone(), third.clone(), fourth.clone())
	expect_closed(first)?
	expect_closed(second)?
	expect_closed(third)?
	expect_closed(fourth)?
	remove(root, false)?
