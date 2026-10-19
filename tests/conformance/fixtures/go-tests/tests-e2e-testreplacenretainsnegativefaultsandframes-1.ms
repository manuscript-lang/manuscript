# conform: tags=testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/replace_n_test.go:29 TestReplaceNRetainsNegativeFaultsAndFrames
test "legacy negative":
    "a".replace("a", "b", -1)
test "required negative":
    "a".replace_n("a", "b", -1)
test "bound negative":
    let replace = "a".replace_n
    replace("a", "b", -1)
test "empty negative":
    "".replace_n("", "b", -1)
test "continues":
    let _unchanged = "a".replace_n("a", "b", 0)
