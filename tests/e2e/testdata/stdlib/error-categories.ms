import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import {TextError, panic} from "@std/core.ms"
import {category, ErrorCategory} from "@std/core.ms"
import {FileSystemError} from "@std/fs.ms"
import {SystemError} from "@std/process.ms"
import {ProcessError, CommandError} from "@std/process.ms"
import {NetworkError} from "@std/net.ms"
import {HttpError} from "@std/http.ms"
import {IoError} from "@std/io.ms"
import {JsonError} from "@std/json.ms"
import {NumberError} from "@std/math.ms"
import {LogError} from "@std/log.ms"
import {CryptoError} from "@std/crypto.ms"
import {YamlError} from "@std/yaml.ms"
import {TomlError} from "@std/toml.ms"
import {SseError} from "@std/sse.ms"
import {range_by} from "@std/collections.ms"

type CustomError:
    message: String

type PathError:
    case InvalidInput

impl Error for PathError:
    fn message() String:
        return "path: invalid input"

impl Error for CustomError:
    fn message() ref String:
        panic("classification must not call user code")
        return self.message

fn is_missing(cause: Error) Bool:
    return category(cause) == some(ErrorCategory.NotFound)

fn yaml_error(cause: Error) Result[YamlError, Error]:
    match cause:
        YamlError(found): return ok(found)
        _: return error(TextError("category changed domain"))

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
        InvalidData(line, column, reason):
            (
                (
                    (
                        line != 3
                        or column != 9
                        or reason != "retained detail"
                    )
                ) | try expect_false
            )
        _: return fail("category changed variant")

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
