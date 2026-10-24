# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/string_basics_test.go:17 TestStringBasicsRejectInvalidContracts
def wrong() -> Int:
    let compare = "a".compare
    return compare(value: "b")
