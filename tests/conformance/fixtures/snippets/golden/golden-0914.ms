// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "bad" {
    if not ("\q" == "") {
        return panic(message: "check failed")
    }
}
// expect-error: MS1001 6:14 unknown text escape \\q; valid escapes are \\n \\t \\r \\\\ \\" and \\u{H}
// expect-error: MS1000 9:1-9:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
