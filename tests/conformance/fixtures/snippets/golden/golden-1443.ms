// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

test "fault":
	missing: Int? := null
	impossible := missing or panic("called Optional.get() on null")
