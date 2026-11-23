import arguments from "@std/os/env.ms"

fn main() Void:
	print(f"Arguments: {arguments().length()}")
