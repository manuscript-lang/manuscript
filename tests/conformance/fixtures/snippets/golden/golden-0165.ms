// conform: tags=diagnostics
// conform: phase=check
import base64_encode, base64_decode from "@std/data/encoding.ms"
import parse, CsvOptions from "@std/data/csv.ms"
import commands, Commands, CommandOutput, CommandError from "@std/os/process.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
fn forward[T](item: T) T: item
