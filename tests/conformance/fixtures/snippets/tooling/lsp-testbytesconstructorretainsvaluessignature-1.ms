# conform: tags=diagnostics,modules,stdlib-bytes,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:266 TestBytesConstructorRetainsValuesSignature
import Bytes from "@std/bytes.ms"

fn make() Bytes:
    return
