# conform: tags=match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:34 TestScalarIntBoundsLowering
let x = match some(0):
            some(n):
                sum = start
                n
            none: 0
        sum += i
        i += 1
