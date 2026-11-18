import (
	panic from "@std/core.ms",
	arguments, working_directory from "@std/os/env.ms",
	canonicalize,
	create_directory,
	exists,
	list,
	read_file,
	remove,
	rename,
	stat,
	write_atomic,
	write_file from "@std/os/fs.ms",
)

fn deep(root: String) String:
	return f"{root}/{"d".repeat(120)}/{"e".repeat(120)}"

fn run() Void!:
	root := arguments().get_or(0, "")
	if root == "": return run_in(working_directory()?)

	return run_in(root)

fn run_in(root: String) Void!:
	dir := deep(root)
	create_directory(dir, recursive: true)?

	file := f"{dir}/data.txt"
	write_file(file, "hello").wait()?

	bytes := read_file(file).wait()?
	print(bytes.length())
	write_atomic(file, "again").wait()?

	info := stat(file)?
	print(info.size)

	moved := f"{dir}/moved.txt"
	rename(file, moved)?
	print(exists(file)?)

	entries := list(dir)?
	print(entries.length())

	real := canonicalize(moved)?
	print(real.length() > 260)
	remove(f"{root}/{"d".repeat(120)}", recursive: true)?
	print(exists(dir)?)

fn main() Void:
	match run():
		ok(_): print("done")
		error(e): print(f"failed: {e}")

test "long path":
	match run():
		ok(_): print("ok")
		error(e): panic(message: f"{e}")
