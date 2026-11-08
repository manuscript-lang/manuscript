fn half(text: String) Int!:
    if let n = text.parse_int():
        return ok(n / 2)

    return error(Error("not a number"))

export fn main() Int:
    print("{half("84").get(0)}")
    print(half("x").err().message)
    return 0
