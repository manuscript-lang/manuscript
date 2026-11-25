// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

test "fault" {
	missing Int? := null
	impossible := missing or panic("called Optional.get() on null")
}
// expect-error: MS3000 7:5 local binding impossible is never read; remove it, use it, or name it with a leading '_' to ignore it
