import expect_equal from "@std/test/test.ms"

fn first(words: List[String]) String:
    return words[0]

type Text:
    value: String

impl Text:
    fn read() String:
        return self.value

fn fresh() String:
    return "aé😀"

fn dynamic_text() String:
    var text = ""
    for part in ["allocated prefix ", "a", "é", "😀", " allocated suffix"]:
        text += part
    return text

fn initial(words: List[String]) String:
    for c in first(words).chars():
        return c
    return ""

fn failed_scan(words: List[String]) Unit!:
    for c in first(words).chars():
        try expect_equal(c, "not the first character")
    return ok(unit)

test "helper and receiver strings support character and scalar scans":
    let words = ["aé😀"]
    var chars = List[String]()
    chars.extend(first(words).chars())
    try expect_equal(chars, ["a", "é", "😀"])

    var sum = first(words).scalar_values().sum()
    try expect_equal(sum, 128842)
    try expect_equal(words[0], "aé😀")

    let text = Text("aé😀")
    sum = 0
    for c in text.read().scalar_values():
        sum += c
    try expect_equal(sum, 128842)
    try expect_equal(text.value, "aé😀")

test "helper scans match materialized snapshots while the source changes":
    var words = [dynamic_text()]
    let expected = first(words).chars()
    var actual = List[String]()

    for c in first(words).chars():
        words[0] = ""
        actual.append(c)

    try expect_equal(actual, expected)
    try expect_equal(words[0], "")
    words = ["aé😀"]

    let scalars = first(words).scalar_values()
    var actual_scalars = List[Int]()

    for c in first(words).scalar_values():
        words = ["replacement text longer than the source"]
        actual_scalars.append(c)

    try expect_equal(actual_scalars, scalars)
    try expect_equal(words[0], "replacement text longer than the source")

test "direct scans snapshot a changed source and retain unchanged fast paths":
    var text = "aé😀"
    var output = ""

    for c in text.chars():
        text = ""
        output += c

    try expect_equal(output, "aé😀")
    try expect_equal(text, "")

    let words = ["aé😀"]
    let bound = first(words)
    var sum = bound.scalar_values().sum()
    try expect_equal(sum, 128842)
    sum = 0
    for c in words[0].scalar_values():
        sum += c
    try expect_equal(sum, 128842)

test "owned temporary and empty helper strings remain valid":
    var output = ""
    for c in first(["aé😀"]).chars():
        output += c
    try expect_equal(output, "aé😀")

    var sum = fresh().scalar_values().sum()
    try expect_equal(sum, 128842)
    for c in first([""]).scalar_values():
        sum += 1
    try expect_equal(sum, 128842)

test "borrowed string scans support break continue return and try":
    let words = ["aé😀b"]
    var output = ""

    for c in first(words).chars():
        if c == "é":
            continue
        if c == "b":
            break

        output += c

    try expect_equal(output, "a😀")
    try expect_equal(initial(words), "a")
    try expect_equal(failed_scan(words).is_error(), true)
    try expect_equal(words[0], "aé😀b")
