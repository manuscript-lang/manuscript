# conform: tags=control-flow,faults,interpolation,maps,match,modules,mutation,optional,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/string-keyed-map-calls-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn lookup(m: Map[String, Int], key: String) Int:
    match m.get(key: key):
        v:
            return v
        none:
            return -1

test "string map":
    var m = Map[String, Int]()
    m.add(key: "a", value: 1)
    m.add(key: "b", value: 2)
    m.add(key: "a", value: 3)
    try expect_true((m.length() == 2))
    try expect_true((lookup(m: m, key: "a") == 3 and lookup(m: m, key: "b") == 2))
    try expect_true((lookup(m: m, key: "c") == -1))
    try expect_true((lookup(m: Map[String, Int](), key: "a") == -1))
    m.add(key: "", value: 9)
    try expect_true((lookup(m: m, key: "") == 9))

    var seen = 0

    for entry in m.clone():
        m.add(key: "x{seen}", value: seen)
        seen = seen + 1

    try expect_true((seen == 3 and m.length() == 6))
