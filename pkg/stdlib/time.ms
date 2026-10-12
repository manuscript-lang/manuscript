# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Result from "@std/result.ms"

export type TimeError:
    case InvalidInput
    case Closed
    case InvalidData
    case OutOfRange

export interface Clock:
    fn now() -> Instant

export type Duration

export type Instant

export type Timestamp

export interface WallClock:
    fn now() -> Timestamp

export fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, TimeError]

export fn format_timestamp(value: Timestamp) -> String

export fn nanoseconds(value: Timestamp) -> Int

export fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]

export fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, TimeError]

export fn sleep(duration: Duration) -> Unit

export fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]

export fn unix_seconds(value: Timestamp) -> Int

impl Error for TimeError:
    fn message() -> String

export fn clock() -> Clock

export fn wall_clock() -> WallClock
