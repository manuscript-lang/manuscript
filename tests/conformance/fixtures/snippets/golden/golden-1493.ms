// conform: tags=diagnostics
// conform: phase=check
import fail from "@std/test/test.ms"
export fn other() Int: return 4
test "unimported":
    if other() != 4: return fail("bad other")
