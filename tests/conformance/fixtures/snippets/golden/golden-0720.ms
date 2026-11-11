// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
import panic from "@std/faults.ms"
type E1:
    code: Int
impl Error for E1:
    fn message() String: "e1"
type E2:
    code: Int
impl Error for E2:
    fn message() String: "e2"
type Missing:
    code: Int
type GenericError[V: Equal]:
    value: V
impl Error for GenericError[V]:
    fn message() String: self.value.to_string()
fn f() Result[Int, E1]: error(E1(1))
fn other() Result[Int, E2]: error(E2(2))
fn ignore[T](r: Result[T, Error]) Int: 1
fn h[T](r: Result[T, Error]) T:
    match r:
        ok(value): return value
        error(_): return panic("unused")
fn pair[T](first: Result[T, Error], second: Result[T, Error]) Unit: return
fn optional[T](r: Result[T, Error]?) Unit: return
fn convert[T, U](r: Result[T, Error]) U?: none
fn apply[T, U](r: Result[T, Error], callback: fn(T) U) U: callback(h(r))
fn exact[T, E: Error](r: Result[T, E]) Result[T, E]: r
