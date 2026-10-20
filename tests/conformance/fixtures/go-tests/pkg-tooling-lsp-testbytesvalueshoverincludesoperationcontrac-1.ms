# conform: tags=closures,diagnostics,lists,modules,stdlib-bytes,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:242 TestBytesValuesHoverIncludesOperationContract
import Bytes from "@std/bytes.ms"
fn extract(data: Bytes) List[Int]:
    let bound: fn() List[Int] = data.values
    return data.values()
