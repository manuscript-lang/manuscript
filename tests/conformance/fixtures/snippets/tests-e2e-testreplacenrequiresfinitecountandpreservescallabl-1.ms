# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/replace_n_test.go:18 TestReplaceNRequiresFiniteCountAndPreservesCallableShape
let replace = "a".replace_n
    replace("a", "b")
