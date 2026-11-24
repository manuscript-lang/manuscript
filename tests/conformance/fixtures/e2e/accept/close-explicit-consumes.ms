// conform: tags=scope-cleanup,testing,try-result,records,tier-stdlib,stdlib-testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import Closeable from "@std/core.ms"

type Gate:
    closes Int

fn move Gate.close() Void!:
    self.closes += 1
    return error(Error("gate stuck"))

fn handled() Void!:
    var g = Gate(0)
    r := g.close()
    if _ok := r:
        return error(Error("close should have failed"))

fn branchy(explicit Bool) Void!:
    var g = Gate(0)
    if explicit:
        void g.close()

fn relocked(second_fails Bool) Void!:
    var g = Gate(0)
    void g.close()
    g = Gate(0)
    if second_fails:
        return ok()

    void g.close()

fn ok_of(r Void!) Bool:
    if _ok := r:
        return true

    return false

test "an explicit close consumes the binding":
    expect_equal(ok_of(handled()), true)?

test "a close on one path leaves the other path to the scope":
    expect_equal(ok_of(branchy(true)), true)?
    expect_equal(ok_of(branchy(false)), false)?

test "a binding given a new value is closed afresh":
    expect_equal(ok_of(relocked(true)), false)?
    expect_equal(ok_of(relocked(false)), true)?
