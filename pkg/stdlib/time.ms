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
    fn add(right: Duration) -> Duration
    fn subtract(right: Duration) -> Duration
    fn multiply(factor: Int) -> Duration
    fn divide(divisor: Int) -> Duration
    fn negate() -> Duration
    fn abs() -> Duration
    fn compare(right: Duration) -> Int
    fn to_nanoseconds() -> Int
    fn to_microseconds() -> Int
    fn to_milliseconds() -> Int
    fn to_seconds() -> Float
    fn to_minutes() -> Float
    fn to_hours() -> Float

export type Instant:
    fn shift(duration: Duration) -> Instant
    fn difference(right: Instant) -> Duration
    fn compare(right: Instant) -> Int

export type Timestamp:
    fn to_string() -> String
    fn unix_seconds() -> Int
    fn nanoseconds() -> Int
    fn shift(duration: Duration) -> Result[Timestamp, TimeError]
    fn difference(right: Timestamp) -> Result[Duration, TimeError]
    fn compare(right: Timestamp) -> Int

export interface WallClock:
    fn now() -> Timestamp

export fn duration(nanoseconds: Int) -> Duration

fn duration_add(left: Duration, right: Duration) -> Duration
fn duration_subtract(left: Duration, right: Duration) -> Duration
fn duration_multiply(value: Duration, factor: Int) -> Duration
fn duration_divide(value: Duration, divisor: Int) -> Duration
fn duration_negate(value: Duration) -> Duration
fn duration_abs(value: Duration) -> Duration
fn duration_compare(left: Duration, right: Duration) -> Int
fn duration_nanoseconds(value: Duration) -> Int
fn duration_microseconds(value: Duration) -> Int
fn duration_milliseconds(value: Duration) -> Int
fn duration_seconds(value: Duration) -> Float
fn duration_minutes(value: Duration) -> Float
fn duration_hours(value: Duration) -> Float

fn instant_shift(value: Instant, duration: Duration) -> Instant
fn instant_difference(left: Instant, right: Instant) -> Duration
fn instant_compare(left: Instant, right: Instant) -> Int

fn difference(left: Timestamp, right: Timestamp) -> Result[Duration, TimeError]
fn format_timestamp(value: Timestamp) -> String
fn nanoseconds(value: Timestamp) -> Int
fn timestamp_compare(left: Timestamp, right: Timestamp) -> Int

export fn parse_timestamp(text: String) -> Result[Timestamp, TimeError]

fn shift(value: Timestamp, duration: Duration) -> Result[Timestamp, TimeError]

export fn sleep(duration: Duration) -> Unit

export fn timestamp(seconds: Int, nanoseconds: Int) -> Result[Timestamp, TimeError]

fn unix_seconds(value: Timestamp) -> Int

impl Error for TimeError:
    fn message() -> String

export fn clock() -> Clock

export fn wall_clock() -> WallClock
