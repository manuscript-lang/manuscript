// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// String equality of inline, heap, literal, built and non-ASCII text agrees on every backend.
fn same(a: String, b: String) Bool:
    return a == b

export fn main() Int:
    short := "ab" + "c"
    long1 := "a rather long string, longer than fifteen bytes"
    long2 := "a rather long string, " + "longer than fifteen bytes"
    wide := "h\u{e9}llo"
    mut := "x".repeat(20).get()
    print(short == "abc")
    print(short == "abd")
    print("abc" == short)
    print(long1 == long2)
    print(long1 == "short")
    print(wide == "h\u{e9}llo")
    print(wide == "hello")
    print(same(long1, long2))
    print(same(short, "abc"))
    print(same("", ""))
    print(same(mut, "x".repeat(20).get()))
    print(same("eight888", "eight888"))
    print(same(long1 + "!", long2 + "!"))
    print(long2 == "")
    print("" == "")
    return 0
