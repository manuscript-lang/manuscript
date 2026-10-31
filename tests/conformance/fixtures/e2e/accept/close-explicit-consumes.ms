# conform: tags=scope-cleanup,testing,try-result,records,tier-stdlib,stdlib-testing
# conform: phase=test
import expect_equal from "@std/test.ms"
import Closeable, TextError from "@std/core.ms"

type Gate:
    closes: Int

impl Closeable for Gate:
    var fn close() Unit!:
        self.closes += 1
        return error(TextError("gate stuck"))

fn handled() Unit!:
    var g = Gate(0)
    let r = g.close()
    if let _ok = r:
        return error(TextError("close should have failed"))
    return ok(unit)

fn branchy(explicit: Bool) Unit!:
    var g = Gate(0)
    if explicit:
        let _ = g.close()
    return ok(unit)

fn relocked(second_fails: Bool) Unit!:
    var g = Gate(0)
    let _ = g.close()
    g = Gate(0)
    if second_fails:
        return ok(unit)
    let _ = g.close()
    return ok(unit)

fn ok_of(r: Unit!) Bool:
    if let _ok = r:
        return true
    return false

test "an explicit close consumes the binding":
    try expect_equal(ok_of(handled()), true)

test "a close on one path leaves the other path to the scope":
    try expect_equal(ok_of(branchy(true)), true)
    try expect_equal(ok_of(branchy(false)), false)

test "a binding given a new value is closed afresh":
    try expect_equal(ok_of(relocked(true)), false)
    try expect_equal(ok_of(relocked(false)), true)
