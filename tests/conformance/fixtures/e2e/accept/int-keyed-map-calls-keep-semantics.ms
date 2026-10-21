# conform: tags=control-flow,faults,maps,match,modules,mutation,optional,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/int-keyed-map-calls-keep-semantics.ms
import {expect_true} from "@std/testing.ms"

fn lookup(m: Map[Int, String], key: Int) String:
    match m.get(key: key):
        some(v):
            return v
        none:
            return "missing"

test "int map":
    var m = Map[Int, String]()
    m.add(key: 1, value: "a")
    m.add(key: 2, value: "b")
    m.add(key: 1, value: "c")
    try expect_true((m.length() == 2))
    try expect_true((lookup(m: m, key: 1) == "c"))
    try expect_true((lookup(m: m, key: 2) == "b"))
    try expect_true((lookup(m: m, key: 3) == "missing"))
    var total = 0

    for entry in m.clone():
        m.add(key: 10 + total, value: "x")
        total = total + 1

    try expect_true((total == 2 and m.length() == 4))
    try expect_true((lookup(m: Map[Int, String](), key: 0) == "missing"))
