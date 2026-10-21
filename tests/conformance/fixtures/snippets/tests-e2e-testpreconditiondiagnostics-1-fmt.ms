# conform: tags=formatter,modules,parser,stdlib-bigint,stdlib-bytes,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/precondition_diagnostics_test.go:45 TestPreconditionDiagnostics
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/collections.ms"
import from_int from "@std/math.ms"
fn compare(left: Int, right: Int) Int: left - right
