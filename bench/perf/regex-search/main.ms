import (
	read_file from "@std/os/fs.ms",
	compile from "@std/regex.ms",
)

fn main() Void!:
	data := (read_file("/tmp/regex-search-input.txt").wait()?).decode_utf8().get_or("")
	re := compile("func\\s+\\w+\\(")?
	all := re.find_all(data, none)?
	spans := re.find_all_spans(data, none)?
	rep := re.replace_all(data, "fn(", none)?
	word := compile("[A-Za-z_]+[0-9]+")?
	w := word.find_all(data, none)?
	print(f"{all.length()} {spans.length()} {rep.length()} {w.length()}")
