# conform: tags=formatter,lists,modules,parser,stdlib-bytes,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/lower_length_test.go:12 TestLengthLowersToGoLen
from "@std/bytes.ms" import Bytes

def count(items: List[Int], data: Bytes) -> Int:
    return items.length() + data.length()
