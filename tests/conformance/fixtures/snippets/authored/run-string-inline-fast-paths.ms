// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// parse_int, a one-byte contains and scalar_at give the same answers for inline, heap, ASCII and
// non-ASCII text on every backend.
fn show(text: String) Unit:
    if v := text.parse_int():
        print("{v}")
    else:
        print("none")

export fn main() Int:
    show("0")
    show("42")
    show("-7")
    show("+7")
    show("")
    show("-")
    show("+")
    show("4x2")
    show(" 1")
    show("123456789012345678")
    show("-123456789012345678")
    show("1234567890123456789")
    show("9223372036854775807")
    show("9223372036854775808")
    show("0000000000000000000042")
    show("é")
    a := "key=value;other"
    b := "this text is longer than thirty two bytes, with a comma, and more"
    print(a.contains("="))
    print(a.contains("#"))
    print(b.contains(","))
    print(b.contains("#"))
    print("é!".contains("!"))
    print("".contains("x"))
    c := "héllo"
    d := "hello"
    print(d.scalar_at(0))
    print(d.scalar_at(4))
    print(d.scalar_at(5, -1))
    print(d.scalar_at(-1))
    print(d.scalar_at(-6, -2))
    print(c.scalar_at(1))
    print(c.scalar_at(2))
    print(b.scalar_at(3))
    return 0
