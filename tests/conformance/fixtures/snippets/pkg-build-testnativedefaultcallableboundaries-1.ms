# conform: tags=diagnostics,generics,modules,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-process,stdlib-time,tier-io
# conform: phase=check
# conform: origin=pkg/build/native_defaults_test.go:11 TestNativeDefaultCallableBoundaries
from "@std/encoding.ms" import base64_encode, base64_decode
from "@std/csv.ms" import parse, CsvOptions
from "@std/process.ms" import commands, Commands, CommandOutput, CommandError
from "@std/bytes.ms" import Bytes
from "@std/time.ms" import Duration

def forward[T](item: T) -> T: item
