from "@std/test.ms" import expect_equal

def grown() -> Int:
    var o: Optional[List[String]] = some(["a"])

    if var l = o:
        l.append("q")
        return l.length()

    return 0

test "if var on an optional local changes its own value":
    try expect_equal(grown(), 2)
