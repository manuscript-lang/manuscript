import (
	read_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
)

// Reads one file under ./data. Callers see only the `data.read` capability.
// ms: effect data.read
// ms: allow_effect std.fs.read
export fn read_data(name: String) String!:
	if name.contains("/") or name.contains("\\") or name == "..":
		return error(Error(f"data.read: {name} is outside data/", kind: "EACCES"))

	bytes := read_file(join(["data", name])).wait()?
	return ok(bytes.decode_utf8().get(""))
