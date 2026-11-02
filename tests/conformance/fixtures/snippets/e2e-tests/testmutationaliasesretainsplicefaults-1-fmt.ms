# conform: tags=formatter,parser,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/mutation_aliases_test.go:11 TestMutationAliasesRetainSpliceFaults
test "new start":
    [1].splice(-1, 0, [])

test "new count":
    [1].splice(0, 2, [])

test "bound start":
    let splice = [1].splice
    splice(2, 0, [])

test "bound count":
    let splice = [1].splice
    splice(0, -1, [])

test "continues":
    var values = [1]
    values.splice(0, 1, [])
    values.append(2)
