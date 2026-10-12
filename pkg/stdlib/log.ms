# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import IoError from "@std/io.ms"
import Map from "@std/collections.ms"
import Result from "@std/result.ms"
import WriteStream from "@std/io.ms"

export type LogError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Io(cause: IoError)

export fn write(
    output: WriteStream,
    level: String,
    message: String,
    fields: Map[String, String],
    max_bytes: Optional[Int] = none
) -> Result[Unit, LogError]:

impl Error for LogError:
    fn message() -> String:
