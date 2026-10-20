# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/native_defaults_test.go:24 TestNativeDefaultCallableBoundaries
let f = forward(base64_encode)
    f(Bytes([]))
