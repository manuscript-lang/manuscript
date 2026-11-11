// conform: tags=testing,tier-io
// conform: phase=check
import (
	Data from "@std/core.ms",
	stringify from "@std/data/json.ms",
	FileHandle from "@std/os/fs.ms",
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
