from "@std/testing.ms" import expect_equal, expect_false, expect_true, fail
from "@std/core.ms" import TextError, panic
from "@std/core.ms" import category, ErrorCategory
from "@std/fs.ms" import FileSystemError
from "@std/process.ms" import SystemError
from "@std/process.ms" import ProcessError, CommandError
from "@std/net.ms" import NetworkError
from "@std/http.ms" import HttpError
from "@std/io.ms" import IoError
from "@std/json.ms" import JsonError
from "@std/math.ms" import NumberError
from "@std/log.ms" import LogError
from "@std/crypto.ms" import CryptoError
from "@std/yaml.ms" import YamlError
from "@std/toml.ms" import TomlError
from "@std/sse.ms" import SseError
from "@std/collections.ms" import range_by

type CustomError:
    message: String

type PathError:
    case InvalidInput

impl Error for PathError:
    def message() -> String:
        return "path: invalid input"

impl Error for CustomError:
    def message() -> String:
        panic("classification must not call user code")
        return self.message

def is_missing(cause: Error) -> Bool:
    return category(cause) == some(ErrorCategory.NotFound)

def yaml_error(cause: Error) -> Result[YamlError, Error]:
    match cause:
        case YamlError(found): return ok(found)
        case _: return error(TextError("category changed domain"))

test "shared categories keep exact standard domain values":
    (is_missing(FileSystemError.NotFound)) | try expect_true
    (is_missing(SystemError.NotFound)) | try expect_true
    (is_missing(ProcessError.NotFound)) | try expect_true
    category(IoError.Unavailable) | try expect_equal(some(ErrorCategory.Unavailable))
    category(JsonError.InvalidData) | try expect_equal(some(ErrorCategory.InvalidData))
    category(FileSystemError.AlreadyExists) | try expect_equal(
        some(ErrorCategory.AlreadyExists)
    )
    category(SystemError.PermissionDenied) | try expect_equal(
        some(ErrorCategory.PermissionDenied)
    )
    category(CryptoError.Unsupported) | try expect_equal(
        some(ErrorCategory.Unsupported)
    )
    category(IoError.Closed) | try expect_equal(some(ErrorCategory.Closed))
    (
        (
            category(
                TomlError.InvalidData(
                    line: 1, column: 2, reason: "detail"
                )
            ) != some(ErrorCategory.InvalidData)
        )
    ) | try expect_false
    category(YamlError.LimitExceeded) | try expect_equal(
        some(ErrorCategory.LimitExceeded)
    )
    category(TomlError.InvalidInput) | try expect_equal(
        some(ErrorCategory.InvalidInput)
    )
    category(SseError.LimitExceeded) | try expect_equal(
        some(ErrorCategory.LimitExceeded)
    )
    category(SseError.Truncated).is_some() | try expect_false

    let allocation_error = range_by(start: 0, end: 268435457, step: 1).err()
    category(allocation_error) | try expect_equal(some(ErrorCategory.LimitExceeded))

    let original: Error = YamlError.InvalidData(
        line: 3, column: 9, reason: "retained detail"
    )
    category(original) | try expect_equal(some(ErrorCategory.InvalidData))

    match (try yaml_error(original)):
        case InvalidData(line, column, reason):
            (
                (
                    (
                        line != 3
                        or column != 9
                        or reason != "retained detail"
                    )
                ) | try expect_false
            )
        case _: return fail("category changed variant")

test "timeout classification keeps timeout spelling out of generic handling":
    let causes: List[Error] = [
        NetworkError.Timeout, HttpError.Timeout, CommandError.Timeout
    ]
    let query = category
    for cause in causes:
        query(cause) | try expect_equal(some(ErrorCategory.Timeout))

test "classification does not parse messages invoke user code or guess domain-specific cases":
    let custom = CustomError(message: "filesystem: file or directory not found")
    category(custom).is_some() | try expect_false
    category(PathError.InvalidInput).is_some() | try expect_false

    let causes: List[Error] = [
        IoError.Failed("not found; operation timed out"), NumberError.OutOfRange,
        CommandError.OutputLimit, CryptoError.AuthenticationFailed,
        YamlError.UnsupportedFeature(line: 7, reason: "detail"),
        LogError.Io(IoError.Closed)
    ]
    for cause in causes:
        category(cause).is_some() | try expect_false
