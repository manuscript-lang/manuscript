# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export type Clock:
    fn now() -> Instant

export type Duration

export type Instant

export type Timestamp

export type WallClock:
    fn now() -> Timestamp

export fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, LibraryError]

export fn format_timestamp(value: Timestamp) -> String

export fn nanoseconds(value: Timestamp) -> Int

export fn parse_timestamp(text: String) -> Result[Timestamp, LibraryError]

export fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, LibraryError]

export fn sleep(duration: Duration) -> Unit

export fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, LibraryError]

export fn unix_seconds(value: Timestamp) -> Int
