# conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-process,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=pkg/build/native_defaults_test.go:11 TestNativeDefaultCallableBoundaries
import base64_encode, base64_decode from "@std/data/encoding.ms"
import parse, CsvOptions from "@std/data/csv.ms"
import Commands, CommandOutput from "@std/os/process.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"

fn forward[T](item: T) T: item
