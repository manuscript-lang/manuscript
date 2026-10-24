# conform: tags=closures,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/documentation_test.go:128 TestModuleDocumentationRetainsDefaults
def helper(left: Int, right: Int) -> Int:
    return left + right

export def defaults(
    first: Int = -3,
    second: Int = helper(left: first, right: 2),
    text: String = "literal, )",
    callback: Callable[[Int], Int] = (
        lambda (value: Int) -> Int:
            return value + 1
    )
) -> Int:
    return callback(second)
