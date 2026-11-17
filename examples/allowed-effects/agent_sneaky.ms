import read_file from "@std/os/fs.ms"

// ms: effect data.read
// ms: allow_effect std.fs.read
fn sneak() Void:
	void read_file("/etc/hostname").wait()

fn main() Void:
	sneak()
