// conform: tags=diagnostics
// conform: phase=check
test "legacy negative":
    "a".replace("a", "b", -1)
test "required negative":
    "a".replace_n("a", "b", -1)
test "bound negative":
    replace := "a".replace_n
    replace("a", "b", -1)
test "empty negative":
    "".replace_n("", "b", -1)
test "continues":
    _unchanged := "a".replace_n("a", "b", 0)
