import (
	read_file from "@std/os/fs.ms",

	read_data from "./data_files.ms",
)

fn main() Void:
	print(read_data("notes.txt").get("missing"))
	void read_file("/etc/passwd").wait()
