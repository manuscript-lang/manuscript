# conform: tags=faults,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:29 TestClosedLocalIntMapLowering
let size = match some(1):
        some(n):
            values.add(n, n)
            values.get(n).get()
        none: values.length()
