# conform: tags=closures,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/native_defaults_test.go:22 TestNativeDefaultCallableBoundaries
let f: fn(data: Bytes, url_safe: Bool) String = base64_encode
    f(Bytes([]))
