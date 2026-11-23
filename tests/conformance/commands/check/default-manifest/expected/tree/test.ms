import panic from "@std/core.ms"

test "arithmetic":
	if not (2 + 3 == 5): return panic(message: "arithmetic failed")
