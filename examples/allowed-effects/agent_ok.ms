import read_data from "./data_files.ms"

fn main() Void:
	print(read_data("notes.txt").get("missing"))
