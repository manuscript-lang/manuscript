import Bytes from "@std/bytes.ms"
import Synchronized from "@std/sync.ms"
import {ClientResponse, HttpResponseMetadata, headers} from "@std/http.ms"
import duration from "@std/time.ms"
import {create, stdout_transport, LogLevel} from "@std/log.ms"

fn list_length(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.length
        index = index + 1

    return total

fn map_length(values: Map[Int, Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.length
        index = index + 1

    return total

fn set_length(values: Set[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.length
        index = index + 1

    return total

fn list_empty(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_empty:
            total = total + 1

        index = index + 1

    return total

fn string_bytes(values: String, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.byte_length
        index = index + 1

    return total

fn string_length(values: String, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.length
        index = index + 1

    return total

fn list_first(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.first.unwrap()
        index = index + 1

    return total

fn list_last(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.last.unwrap()
        index = index + 1

    return total

fn map_empty(values: Map[Int, Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_empty:
            total = total + 1

        index = index + 1

    return total

fn set_empty(values: Set[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_empty:
            total = total + 1

        index = index + 1

    return total

fn bytes_empty(values: Bytes, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_empty:
            total = total + 1

        index = index + 1

    return total

fn string_empty(values: String, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_empty:
            total = total + 1

        index = index + 1

    return total

fn string_scalars(values: String, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.scalar_length
        index = index + 1

    return total

fn bytes_length(values: Bytes, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.length
        index = index + 1

    return total

fn optional_some(values: Optional[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_some:
            total = total + 1

        index = index + 1

    return total

fn optional_none(values: Optional[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_none:
            total = total + 1

        index = index + 1

    return total

fn result_ok(values: Result[Int, String], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_ok:
            total = total + 1

        index = index + 1

    return total

fn result_error(values: Result[Int, String], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_error:
            total = total + 1

        index = index + 1

    return total

fn float_nan(values: Float, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_nan:
            total = total + 1

        index = index + 1

    return total

fn float_finite(values: Float, limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        if values.is_finite:
            total = total + 1

        index = index + 1

    return total

fn method_control(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.at(0).unwrap()
        index = index + 1

    return total

interface Observed:
    get observed -> Int

type Holder:
    items: List[Int]

impl Observed for Holder:
    get observed -> Int:
        return self.items.length

fn read_generic[T: Observed](value: T) -> Int:
    return value.observed

fn source_direct(values: List[Int], limit: Int) -> Int:
    let value = Holder(values)
    var total = 0
    var index = 0

    while index < limit:
        total = total + value.observed
        index = index + 1

    return total

fn source_view(values: List[Int], limit: Int) -> Int:
    let value = Observed(Holder(values))
    var total = 0
    var index = 0

    while index < limit:
        total = total + value.observed
        index = index + 1

    return total

fn source_generic(values: List[Int], limit: Int) -> Int:
    let value = Holder(values)
    var total = 0
    var index = 0

    while index < limit:
        total = total + read_generic(value)
        index = index + 1

    return total

fn guard_length(values: List[Int], limit: Int) -> Int:
    let shared = Synchronized(values)

    with guard = shared.lock():
        var total = 0
        var index = 0

        while index < limit:
            total = total + guard.value.length
            index = index + 1

        return total

fn metadata_status(values: Int, limit: Int) -> Int:
    let response = ClientResponse(
        HttpResponseMetadata(values, headers()),
        "".to_bytes()
    )
    var total = 0
    var index = 0

    while index < limit:
        total = total + response.metadata.status
        index = index + 1

    return total

fn typed_optional(values: Int, limit: Int) -> Int:
    let present: Optional[Int] = some(values)
    var total = 0
    var index = 0

    while index < limit:
        if present.is_some:
            total = total + 1

        index = index + 1

    return total

fn typed_result(values: Int, limit: Int) -> Int:
    let success: Result[Int, String] = ok(values)
    var total = 0
    var index = 0

    while index < limit:
        if success.is_ok:
            total = total + 1

        index = index + 1

    return total

fn duration_seconds(values: Int, limit: Int) -> Int:
    let span = duration(values)
    var total = 0
    var index = 0

    while index < limit:
        if span.seconds == 1.5:
            total = total + 1

        index = index + 1

    return total

fn string_alternating(values: List[String], limit: Int) -> Int:
    var total = 0
    var index = 0

    while index < limit:
        total = total + values.at(index % 2).unwrap().scalar_length
        index = index + 1

    return total

fn logger_level(values: Int, limit: Int) -> Int:
    with transport = stdout_transport():
        let logger = create(transport: transport, timestamp: false).unwrap()
        var total = 0
        var index = 0

        while index < limit:
            if logger.level == LogLevel.Info:
                total = total + 1

            index = index + 1

        return total
