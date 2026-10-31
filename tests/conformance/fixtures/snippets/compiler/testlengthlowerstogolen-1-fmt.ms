# conform: tags=formatter,lists,modules,parser,stdlib-bytes,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/lower_length_test.go:12 TestLengthLowersToGoLen
import Bytes from "@std/bytes.ms"

fn count(items: List[Int], data: Bytes) Int:
    return items.length() + data.length()
