import write_file from "@std/os/fs.ms"

// ms: effect db.write
// ms: allow_effect std.fs.write
fn save(order: String) Unit!:
	return write_file("orders.log", order).wait()

fn audit(total: Int) Unit!:
	return save("audit {total}")
