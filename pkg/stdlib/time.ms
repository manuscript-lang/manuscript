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

export type Duration:
    fn add(right: Duration) -> Duration:
    fn subtract(right: Duration) -> Duration:
    fn multiply(factor: Int) -> Duration:
    fn divide(divisor: Int) -> Duration:
    fn negate() -> Duration:
    fn abs() -> Duration:
    fn compare(right: Duration) -> Int:
    fn to_nanoseconds() -> Int:
    fn to_microseconds() -> Int:
    fn to_milliseconds() -> Int:
    fn to_seconds() -> Float:
    fn to_minutes() -> Float:
    fn to_hours() -> Float:

export type Instant:
    fn shift(duration: Duration) -> Instant:
    fn difference(right: Instant) -> Duration:
    fn compare(right: Instant) -> Int:

export type Timestamp:
    fn to_string() -> String:
    fn unix_seconds() -> Int:
    fn nanoseconds() -> Int:
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]:
    fn difference(right: Timestamp) -> Result[Duration, TimeError]:
    fn compare(right: Timestamp) -> Int:

export interface WallClock:
    fn now() -> Timestamp

export fn duration(nanoseconds: Int) -> Duration:

export fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]:

export fn sleep(duration: Duration) -> Unit:

export fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]:

impl Error for TimeError:
    fn message() -> String:

export fn clock() -> Clock:

export fn wall_clock() -> WallClock:
