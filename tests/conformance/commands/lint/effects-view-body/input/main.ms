import ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import lines from "@std/io/steps.ms"
import collect from "@std/io/streams.ms"

fn gather(move input: ReadStream[Bytes]) List[String]!:
	return collect(lines(input, none), none)

fn main() Int:
	return 0
