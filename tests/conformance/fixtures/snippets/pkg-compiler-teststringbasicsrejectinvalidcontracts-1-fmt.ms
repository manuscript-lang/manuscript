# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/string_basics_test.go:17 TestStringBasicsRejectInvalidContracts
def wrong() -> Int:
    let compare = "a".compare
    return compare(value: "b")
