import TextError from "@std/errors.ms"
import SseError from "@std/sse.ms"
import panic from "@std/faults.ms"

type UserError:
    reads: List[Int]
    text: String

impl Error for UserError:
    fn message() -> String:
        self.reads.append(1)
        return self.text

fn describe[T: Error](value: T) -> String:
    return value.message()

test "Error message remains a method and a lazy bound callable":
    let reads: List[Int] = []
    let failure = UserError(reads, "verbatim custom failure")
    let message: fn() -> String = failure.message
    if not reads.is_empty:
        return panic("taking message method executed its body")
    if message() != "verbatim custom failure" or reads.length != 1:
        return panic("bound message method")
    if failure.message() != "verbatim custom failure" or reads.length != 2:
        return panic("concrete message method")

    let view = Error(failure)
    let viewed_message: fn() -> String = view.message
    if reads.length != 2:
        return panic("taking interface message method executed its body")
    if viewed_message() != "verbatim custom failure" or reads.length != 3:
        return panic("interface message method")
    if describe(failure) != "verbatim custom failure" or reads.length != 4:
        return panic("generic message method")

test "native and source standard Error implementations remain callable":
    let native = TextError.Text("verbatim native failure")
    let native_message: fn() -> String = native.message
    if (
        native_message() != "verbatim native failure"
        or describe(native) != "verbatim native failure"
    ):
        return panic("native Error message changed")

    let source = SseError.InvalidInput
    let source_message: fn() -> String = source.message
    if (
        source_message() != "SSE invalid input"
        or describe(source) != "SSE invalid input"
    ):
        return panic("source Error message changed")

    let view = Error(source)
    if view.message() != "SSE invalid input":
        return panic("source Error view method changed")
