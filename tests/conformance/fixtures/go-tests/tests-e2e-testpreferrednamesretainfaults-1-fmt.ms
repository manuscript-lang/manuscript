# conform: tags=formatter,lists,parser,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/preferred_names_test.go:11 TestPreferredNamesRetainFaults
test "new set":
    [1].set(1, 2)
test "bound set":
    let set = [1].set
    set(-2, 2)
test "new remove":
    [1].remove(1)
test "bound remove":
    let remove = [1].remove
    remove(-2)
test "empty set":
    var items: List[Int] = []
    items.set(0, 2)
test "empty remove":
    var items: List[Int] = []
    items.remove(0)
test "old replace":
    "a".replace("a", "b", -1)
test "new replace":
    "a".replace_first("a", "b", -1)
test "bound replace":
    let first = "a".replace_first
    first("a", "b", -1)
test "continues":
    var result = [1]
    result.set(0, 2)
    result.remove(0)
