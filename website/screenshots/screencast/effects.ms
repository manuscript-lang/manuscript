import write_file from "@std/os/fs.ms"

// ms: effect db.write
// ms: allow_effect std.fs.write
fn save(order String) Void! {
	return write_file("orders.log", order).wait()
}

fn audit(total Int) Void! {
	return save(f"audit {total}")
}
