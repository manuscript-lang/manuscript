# conform: tags=control-flow,interpolation,lists,modules,mutation,numbers,sets,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/primitive-list-append-and-range-keep-semantics.ms
import {expect_true} from "@std/testing.ms"

test "primitive list loops":
    var ints = List[Int]()
    var floats = List[Float]()
    var bools = List[Bool]()
    var words = List[String]()
    var i = 0

    while i < 5:
        ints.append(value: i)
        floats.append(value: 0.5)
        bools.append(value: i % 2 == 0)
        words.append(value: "w{i}")
        i = i + 1

    var sum = 0

    for v in ints:
        sum = sum + v
        if v == 2:
            ints.append(value: 100)

    try expect_true((sum == 10))
    try expect_true((ints.length() == 6))
    var total = 0.0
    for f in floats:
        total = total + f
    try expect_true((total == 2.5))
    var trues = 0
    for b in bools:
        if b:
            trues = trues + 1
    try expect_true((trues == 3))
    var joined = ""
    for w in words:
        joined = joined + w
    try expect_true((joined == "w0w1w2w3w4"))
    var unique = Set[Int]()
    unique.add(value: 4)
    unique.add(value: 7)
    var seen = 0
    for n in unique:
        seen = seen + n
    try expect_true((seen == 11))
