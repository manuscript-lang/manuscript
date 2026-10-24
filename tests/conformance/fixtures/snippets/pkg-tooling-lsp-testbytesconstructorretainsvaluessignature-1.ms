# conform: tags=diagnostics,modules,stdlib-bytes,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:266 TestBytesConstructorRetainsValuesSignature
from "@std/bytes.ms" import Bytes

def make() -> Bytes:
    return
