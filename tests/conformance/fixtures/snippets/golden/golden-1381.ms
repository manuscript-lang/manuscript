// conform: tags=diagnostics
// conform: phase=check
import stdout, stderr from "@std/io/io.ms"
import panic from "@std/faults.ms"

test "pass=a=b":
    _out := stdout().write(data: "PASS fake\nstdout=a=b\n")
    _err := stderr().write(data: "stderr=a=b\n")

test "fails":
    return panic(message: "distribution failure")

test "after":
    return unit
