import {expect_true} from "@std/testing.ms"

test "primitive list loops":
    let ints = List[Int]()
    let floats = List[Float]()
    let bools = List[Bool]()
    let words = List[String]()
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

    (sum == 10) | try expect_true
    (ints.length() == 6) | try expect_true
    var total = 0.0
    for f in floats:
        total = total + f
    (total == 2.5) | try expect_true
    var trues = 0
    for b in bools:
        if b:
            trues = trues + 1
    (trues == 3) | try expect_true
    var joined = ""
    for w in words:
        joined = joined + w
    (joined == "w0w1w2w3w4") | try expect_true
    let unique = Set[Int]()
    unique.add(value: 4)
    unique.add(value: 7)
    var seen = 0
    for n in unique:
        seen = seen + n
    (seen == 11) | try expect_true
