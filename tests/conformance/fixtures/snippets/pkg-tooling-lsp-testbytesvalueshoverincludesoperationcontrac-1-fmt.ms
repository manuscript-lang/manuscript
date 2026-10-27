# conform: tags=closures,formatter,lists,modules,parser,stdlib-bytes,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:242 TestBytesValuesHoverIncludesOperationContract
from "@std/bytes.ms" import Bytes

def extract(data: Bytes) -> List[Int]:
    let _bound: Callable[[], List[Int]] = data.values
    return data.values()
