// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
import panic from "@std/faults.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn absent[T]() T?: none
fn identity[T](value: T) T: value
fn convert[T, U](value: T) U?: none
fn from_callback[T](factory: fn() T) T: factory()
fn transform[T, U](callback: fn(T) U) fn(T) U: callback
fn repeated[T]() Pair[T, T]: panic("not called")
fn unused[T]() Int: 0
fn constrained[T: Equal]() T?: none
type Pair[A, B]:
    first: A
    second: B
type Holder:
    value: Int?
type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
fn consume(value: Int?) Unit: return
