# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:21 TestClosedLocalIntMapLowering
let callback = fn() Int: values.length()
    let size = callback()
