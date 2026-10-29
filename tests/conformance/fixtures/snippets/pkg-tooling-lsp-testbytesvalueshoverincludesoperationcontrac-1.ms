# conform: tags=closures,diagnostics,lists,modules,stdlib-bytes,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:242 TestBytesValuesHoverIncludesOperationContract
import Bytes from "@std/bytes.ms"

fn extract(data: Bytes) List[UInt8]:
    let _bound: fn() List[UInt8] = data.values
    return data.values()
