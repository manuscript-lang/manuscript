// conform: tags=diagnostics
// conform: phase=check
import expect_contains, expect_fault from "@std/test/test.ms"
import panic from "@std/faults.ms"
test "expect_fault reports the injected fault":
    expect_contains(expect_fault(fn: panic("boom"))?, "boom")?
