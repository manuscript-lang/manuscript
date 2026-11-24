import (
	read_file, remove, temporary_directory, temporary_root from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	exercise from "./outer.ms",
	exercise_shared from "./shared.ms",
)

test "same display names keep nested resource cleanup":
	path := f"{ temporary_root()?}/ms-nominal-cycle-identity.txt"
	_gone := remove(path, false)
	exercise(path.clone())

	seen := read_file(path.clone(), null).wait()?
	_cleaned := remove(path, false)
	seen.length() | expect_equal(1)?

fn expect_closed(path String) Void!:
	seen := read_file(path.clone(), null).wait()?
	_cleaned := remove(path, false)
	expect_equal(seen.length(), 1)?

test "shared generic field types keep cleanup for each value":
	root := temporary_directory("ms-shared-classification")?
	first := f"{root}/ms-shared-first.txt"
	second := f"{root}/ms-shared-second.txt"
	third := f"{root}/ms-shared-third.txt"
	fourth := f"{root}/ms-shared-fourth.txt"
	exercise_shared(first.clone(), second.clone(), third.clone(), fourth.clone())
	expect_closed(first)?
	expect_closed(second)?
	expect_closed(third)?
	expect_closed(fourth)?
	remove(root, false)?
