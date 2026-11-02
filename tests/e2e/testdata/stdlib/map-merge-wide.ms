import expect_equal from "@std/test/test.ms"

type WideKey:
    a: Int
    b: Int
    c: Int
    d: Int
    e: Int
    f: Int
    g: Int
    h: Int
    i: Int
    j: Int

type WideValue:
    first: String
    second: String
    third: String
    fourth: String
    fifth: String

fn key(i: Int) WideKey: WideKey(i, i, i, i, i, i, i, i, i, i)

fn value(i: Int) WideValue:
    let text = "a long independently owned runtime value " + i.to_string()
    return WideValue(text.clone(), text.clone(), text.clone(), text.clone(), text)

fn merged_wide() Map[WideKey, WideValue]:
    var source = Map[WideKey, WideValue]()
    for i in 0..8:
        source.add(key(i), value(i))
    source.remove(key(3))
    source.remove(key(6))

    var target = Map[WideKey, WideValue]()
    target.add(key(2), value(99))
    target.add(key(-1), value(-1))
    target.merge(source.clone())
    target.merge(source)

    let empty = Map[WideKey, WideValue]()
    target.merge(empty)
    return target

test "wide Map merge preserves order and owns values after the source drops":
    let merged = merged_wide()
    try expect_equal(merged.keys().map(fn k: k.a), [2, -1, 0, 1, 4, 5, 7])

    for i in [2, -1, 0, 1, 4, 5, 7]:
        let found = merged.get(key(i)).get()
        let text = "a long independently owned runtime value " + i.to_string()
        try expect_equal(found.first, text)
        try expect_equal(found.second, text)
        try expect_equal(found.third, text)
        try expect_equal(found.fourth, text)
        try expect_equal(found.fifth, text)

test "primitive Map merge preserves overwrite and empty-source behavior":
    var target: Map[Int, Int] = {2: 99, -1: -1}
    let source: Map[Int, Int] = {0: 0, 1: 1, 2: 2}
    target.merge(source.clone())

    let empty = Map[Int, Int]()
    target.merge(empty)
    try expect_equal(target.keys(), [2, -1, 0, 1])
    try expect_equal(target.values(), [2, -1, 0, 1])
    try expect_equal(source.keys(), [0, 1, 2])
