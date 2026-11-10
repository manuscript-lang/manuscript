// conform: tags=scope-cleanup,testing,try-result,records,tier-stdlib,stdlib-testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import Closeable from "@std/core.ms"

type Gate:
    closes: Int

impl Closeable for Gate:
    var fn close() Unit!:
        self.closes += 1
        return error(Error("gate stuck"))

fn handled() Unit!:
    var g = Gate(0)
    r := g.close()
    if _ok := r:
        return error(Error("close should have failed"))

fn branchy(explicit: Bool) Unit!:
    var g = Gate(0)
    if explicit:
        _ := g.close()

fn relocked(second_fails: Bool) Unit!:
    var g = Gate(0)
    _ := g.close()
    g = Gate(0)
    if second_fails:
        return ok(unit)

    _ := g.close()

fn ok_of(r: Unit!) Bool:
    if _ok := r:
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
