# conform: tags=diagnostics,modules,stdlib-bigint,stdlib-bytes,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/precondition_diagnostics_test.go:45 TestPreconditionDiagnostics
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import from_int from "@std/bigint.ms"
fn compare(left: Int, right: Int) Int: left - right
