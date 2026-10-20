# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:20 TestClosedLocalIntMapLowering
let add = values.add
    let size = add(1, 2).length()
