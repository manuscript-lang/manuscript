import read_file from "@std/os/fs.ms"

// ms: allow_effect std.fs.read
export fn load_name() String!:
	bytes := read_file("name.txt").wait()?
	return ok(bytes.decode_utf8().get("").trim())
