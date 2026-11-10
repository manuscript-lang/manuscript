import (
	Data from "@std/core.ms",
	FileHandle from "@std/os/fs.ms",
	stringify from "@std/data/json.ms",
)

fn show[T: Data](value: T) String:
	return stringify(value).get("")

type Report:
	title: String
	log: FileHandle

fn send(report: Report) Int:
	return show(report).length()

export fn main() Int:
	return 0
