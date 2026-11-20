// Literal matches and `if` expressions the C body checker claims.
name_of(n: Int) String {
    return match n {
        0: "zero",
        -1: "minus one",
        0x10: "sixteen",
        _: "many"
    }
}

flag(b: Bool) Int {
    return match b {
        true: 1,
        false: 0
    }
}

word(s: String) Bool {
    return match s {
        "yes": true,
        _: false
    }
}

pick(c: Bool, a: Int, b: Int) Int {
    return if c: a + 1 else: if a > b: a else: b
}

shout(n: Int) String {
    label := match n + 1 {
        1: "one",
        2: "two",
        _: "other"
    }
    return label
}
