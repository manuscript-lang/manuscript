// conform: tags=diagnostics
// conform: phase=check
test "new start":
    [1].splice(-1, 0, [])
test "new count":
    [1].splice(0, 2, [])
test "bound start":
    splice := [1].splice
    splice(2, 0, [])
test "bound count":
    splice := [1].splice
    splice(0, -1, [])
test "continues":
    values := [1].splice(0, 1, [])
    values.append(2)
