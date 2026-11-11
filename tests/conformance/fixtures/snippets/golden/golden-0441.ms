// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn apply[T, U](value: T, transform: fn(T) U) U: transform(value)
fn chain[T, U](first: fn() T, second: fn(T) U) U: second(first())
fn result[T](transform: fn() Result[T, TextError]) Result[T, TextError]: transform()
fn checked() Result[Int, TextError]: ok(3)
fn choose[T](first: fn() T, second: fn() T) T: second()
fn optional(transform: (fn(Int) Int)? = none) Unit: return
type Box[T]:
    value: T
type Callback[T, U]:
    transform: fn(T) U
enum Choice[T]:
    Payload(value: T)
type Pair:
    first: Int
    second: Int = 2
enum TwoPayloads:
    Pair(first: Int, second: Int)
interface Read:
    fn get() Int
impl Read for Box[Int]:
    fn get() Int: self.value
