// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

fn write_line(text String) Result[Void, Error] {
	stdout().write(data: f"{text}\n")?
}

fn exercise() Result[Int, Error] {
	args := arguments()
	var index = 0

	while index < args.length() {
		write_line(args[index])?
		index += 1
	}

	return ok(0)
}

export fn main() Int {
	match exercise() {
		ok(status) => return status
		error(cause) => {
			written := stderr().write(f"{cause.message()}\n")
			return 1
		}
	}
}

test "selected=a=b" {
	write_line("selected")?
}

test "unselected" {
	write_line("unselected")
}
