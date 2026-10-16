import {category, ErrorCategory} from "@std/errors.ms"
import {FileSystemError} from "@std/fs.ms"
import {SystemError} from "@std/system.ms"
import {ProcessError, CommandError} from "@std/process.ms"
import {ExecutionError, StartError} from "@std/tasks.ms"
import {NetworkError} from "@std/net.ms"
import {HttpError} from "@std/http.ms"
import {IoError} from "@std/io.ms"
import {JsonError} from "@std/json.ms"
import {NumberError} from "@std/numbers.ms"
import {LogError} from "@std/log.ms"
import {CryptoError} from "@std/crypto.ms"
import {YamlError} from "@std/yaml.ms"
import {TomlError} from "@std/toml.ms"
import {SseError} from "@std/sse.ms"
import {range} from "@std/collections.ms"
import panic from "@std/faults.ms"

type CustomError:
    calls: Int
    message: String

type PathError:
    case InvalidInput

impl Error for PathError:
    fn message() -> String:
        return "path: invalid input"

impl Error for CustomError:
    fn message() -> String:
        self.calls = self.calls + 1
        return self.message

fn is_missing(cause: Error) -> Bool:
    return category(cause) == some(ErrorCategory.NotFound)

fn yaml_error(cause: Error) -> YamlError:
    match cause:
        YamlError(found): return found
        _: return panic("category changed domain")

test "shared categories keep exact standard domain values":
    if not is_missing(FileSystemError.NotFound): return panic("filesystem category")
    if not is_missing(SystemError.NotFound): return panic("system category")
    if not is_missing(ProcessError.NotFound): return panic("process category")
    if category(IoError.Unavailable) != some(ErrorCategory.Unavailable): return panic(
        "unavailable inferred as missing"
    )
    if category(JsonError.InvalidData) != some(ErrorCategory.InvalidData): return panic(
        "data category"
    )
    if category(FileSystemError.AlreadyExists) != some(ErrorCategory.AlreadyExists): return panic(
        "exists category"
    )
    if category(SystemError.PermissionDenied) != some(ErrorCategory.PermissionDenied): return panic(
        "permission category"
    )
    if category(CryptoError.Unsupported) != some(ErrorCategory.Unsupported): return panic(
        "unsupported category"
    )
    if category(IoError.Closed) != some(ErrorCategory.Closed): return panic(
        "closed category"
    )
    if (
        category(
            TomlError.InvalidData(line: 1, column: 2, reason: "detail")
        ) != some(ErrorCategory.InvalidData)
    ): return panic("source TOML category")
    if category(YamlError.LimitExceeded) != some(ErrorCategory.LimitExceeded): return panic(
        "source YAML budget category"
    )
    if category(TomlError.InvalidInput) != some(ErrorCategory.InvalidInput): return panic(
        "source TOML input category"
    )
    if category(SseError.LimitExceeded) != some(ErrorCategory.LimitExceeded): return panic(
        "source SSE budget category"
    )
    if category(SseError.Truncated).is_some(): return panic(
        "SSE truncation has no shared category"
    )

    let allocation_error = range(start: 0, end: 268435457, step: 1).unwrap_error()
    if category(allocation_error) != some(ErrorCategory.LimitExceeded): return panic(
        "native allocation limit category"
    )

    let original: Error = YamlError.InvalidData(
        line: 3,
        column: 9,
        reason: "retained detail"
    )
    if category(original) != some(ErrorCategory.InvalidData): return panic(
        "payload category"
    )

    match yaml_error(original):
        InvalidData(line, column, reason):
            if (line != 3 or column != 9 or reason != "retained detail"): return panic(
                "category lost payload"
            )
        _: return panic("category changed variant")

test "timeout classification keeps timeout spelling out of generic handling":
    let causes: List[Error] = [
        NetworkError.Timeout,
        HttpError.Timeout,
        CommandError.Timeout,
        ExecutionError.Timeout
    ]
    let query = category
    for cause in causes:
        if query(cause) != some(ErrorCategory.Timeout): return panic("timeout category")

test "classification does not parse messages invoke user code or guess domain-specific cases":
    let custom = CustomError(
        calls: 0,
        message: "filesystem: file or directory not found"
    )
    if category(custom).is_some() or custom.calls != 0: return panic(
        "classifier invoked message"
    )
    if category(PathError.InvalidInput).is_some(): return panic(
        "local standard name was classified"
    )

    let causes: List[Error] = [
        IoError.Failed("not found; operation timed out"),
        NumberError.OutOfRange,
        StartError.Full,
        CommandError.OutputLimit,
        CryptoError.AuthenticationFailed,
        ExecutionError.Cancelled,
        YamlError.UnsupportedFeature(line: 7, reason: "detail"),
        LogError.Io(IoError.Closed)
    ]
    for cause in causes:
        if category(cause).is_some(): return panic("domain-specific cause guessed")
