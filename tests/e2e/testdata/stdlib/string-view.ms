import expect_equal from "@std/test/test.ms"

test "view borrows a range of scalars without copying":
    text := "banana héllo wörld, a long string that is not inline"
    try expect_equal(text.view(2, 6), "nana")
    try expect_equal(text.view(7, 12), "héllo")
    try expect_equal(text.view(-6, text.length()), "inline")
    try expect_equal(text.view(0, text.length()), text)
    try expect_equal(text.view(3, 3).length(), 0)

test "view agrees with slice":
    text := "aé🙂z héllo wörld and a longer tail of ascii text"
    var a = -text.length()

    while a <= text.length():
        var b = a

        while b <= text.length():
            want := text.slice(a, b)
            if want.is_ok():
                try expect_equal(text.view(a, b).clone(), want.get())
            b += 7

        a += 5

test "a kept view is a copy made with clone":
    text := "hello world, a string long enough to live on the heap"
    var words = List[String]()
    words.append(text.view(6, 11).clone())
    words.append(text.view(0, 5).clone())
    try expect_equal(words, ["world", "hello"])

test "view of a temporary is owned":
    tail := "hello".upper().view(1, 5)
    try expect_equal(tail, "ELLO")
