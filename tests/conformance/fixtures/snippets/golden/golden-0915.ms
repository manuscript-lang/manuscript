// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "bad" {
    if not ("\u{D800}" == "") {
        return panic(message: "check failed")
    }
}
// expect-error: MS1001 6:21 invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)
// expect-error: MS1000 9:1-9:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
