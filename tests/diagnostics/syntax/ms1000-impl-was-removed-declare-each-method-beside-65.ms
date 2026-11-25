// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
import panic from "@std/faults.ms"
type E1 {
    code Int
}
impl Error for E1 {
    fn message() String => "e1"
}
type E2 {
    code: Int
}
impl Error for E2 {
    fn message() String => "e2"
}
type Missing {
    code: Int
}
type GenericError[V: Equal] {
    value: V
}
impl Error for GenericError[V] {
    fn message() String => self.value.to_string()
}
fn f() Result[Int, E1] => error(E1(1))
fn other() Result[Int, E2] => error(E2(2))
fn ignore[T](r: Result[T, Error]) Int => 1
fn h[T](r: Result[T, Error]) T {
    match r {
        ok(value) => return value
        error(_) => return panic("unused")
    }
}
fn pair[T](first: Result[T, Error], second: Result[T, Error]) Void => return
fn optional[T](r: Result[T, Error]?) Void => return
fn convert[T, U](r: Result[T, Error]) U? => null
fn apply[T, U](r: Result[T, Error], callback: fn(T) U) U => callback(h(r))
fn exact[T, E: Error](r: Result[T, E]) Result[T, E]: r
// expect-error: MS1000 8:1-8:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 12:9-12:10 remove the ':' between 'code' and its type; write code Type
// expect-fix: 12:9-12:10 ""
// expect-error: MS1000 14:1-14:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 18:9-18:10 remove the ':' between 'code' and its type; write code Type
// expect-fix: 18:9-18:10 ""
// expect-error: MS1000 20:20-20:21 a type parameter's bound follows its name without ':'; write V Comparable
// expect-fix: 20:20-20:21 ""
// expect-error: MS1000 23:1-23:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 28:15-28:16 remove the ':' between 'r' and its type; write r Type
// expect-fix: 28:15-28:16 ""
// expect-error: MS1000 29:10-29:11 remove the ':' between 'r' and its type; write r Type
// expect-fix: 29:10-29:11 ""
// expect-error: MS1000 35:17-35:18 remove the ':' between 'first' and its type; write first Type
// expect-fix: 35:17-35:18 ""
// expect-error: MS1000 36:17-36:18 remove the ':' between 'r' and its type; write r Type
// expect-fix: 36:17-36:18 ""
// expect-error: MS1000 37:19-37:20 remove the ':' between 'r' and its type; write r Type
// expect-fix: 37:19-37:20 ""
// expect-error: MS1000 38:17-38:18 remove the ':' between 'r' and its type; write r Type
// expect-fix: 38:17-38:18 ""
// expect-error: MS1000 39:14-39:15 a type parameter's bound follows its name without ':'; write E Comparable
// expect-fix: 39:14-39:15 ""
