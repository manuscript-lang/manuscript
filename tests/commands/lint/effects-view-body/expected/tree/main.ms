import (
	Bytes from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
	collect from "@std/io/streams.ms",
)

fn gather(move input ReadStream[Bytes]) List[String]! {
	return collect(lines(input, null), null)
}

fn main() Int {
	return 0
}
