# conform: tags=formatter,modules,parser,stdlib-bytes,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:266 TestBytesConstructorRetainsValuesSignature
from "@std/bytes.ms" import Bytes

def make() -> Bytes:
    return
