import (
	Bytes from "@std/bytes.ms",
	read_file from "@std/os/fs.ms",
)

type Challenge {
	dir String
}

fn Challenge.spec() Bytes {
	return read_file(f"{self.dir}/spec.md").wait().get()
}

fn load(c Challenge) Int {
	return c.spec().length()
}

fn main() Void {
	print(load(Challenge(dir: "x")))
}
