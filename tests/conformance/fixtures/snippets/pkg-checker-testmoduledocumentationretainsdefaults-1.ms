# conform: tags=closures,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/documentation_test.go:128 TestModuleDocumentationRetainsDefaults
fn helper(left: Int, right: Int) Int:
    return left + right
export fn defaults(first: Int = -3, second: Int = helper(left: first, right: 2), text: String = "literal, )", callback: fn(value: Int) Int = (fn(value: Int) Int:
    return value + 1
)) Int:
    return callback(second)
