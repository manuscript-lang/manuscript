// conform: tags=diagnostics
// conform: phase=check
import stdout, stderr from "@std/io/io.ms"
import fail from "@std/test/test.ms"

test "first=pass":
    _out := stdout().write(data: "PASS fake test\nuser stdout\n")
    _err := stderr().write(data: "user stderr\n")

test "second=fails":
    return fail("expected failure")

test "third=after":
    return unit
