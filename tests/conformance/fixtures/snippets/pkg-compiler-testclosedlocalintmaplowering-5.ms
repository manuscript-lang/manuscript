# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:22 TestClosedLocalIntMapLowering
let callback = fn(value: Int = values.length()) Int: value
    let size = callback()
