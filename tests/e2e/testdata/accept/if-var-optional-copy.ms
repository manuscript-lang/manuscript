import expect_equal from "@std/test.ms"

fn grown() Int:
    var o: List[String]? = ["a"]

    if var l = o:
        l.append("q")
        return l.length()

    return 0

test "if var on an optional local changes its own value":
    try expect_equal(grown(), 2)
