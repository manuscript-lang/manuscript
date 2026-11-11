// conform: tags=diagnostics
// conform: phase=check
test "new set":
    [1].set(1, 2)
test "bound set":
    set := [1].set
    set(-2, 2)
test "new remove":
    [1].remove(1)
test "bound remove":
    remove := [1].remove
    remove(-2)
test "empty set":
    items: List[Int] := []
    items.set(0, 2)
test "empty remove":
    items: List[Int] := []
    items.remove(0)
test "old replace":
    "a".replace("a", "b", -1)
test "new replace":
    "a".replace_first("a", "b", -1)
test "bound replace":
    first := "a".replace_first
    first("a", "b", -1)
test "continues":
    result := [1].set(0, 2).remove(0)
