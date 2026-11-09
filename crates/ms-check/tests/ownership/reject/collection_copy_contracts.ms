import Closeable from "@std/core.ms"
import filled, flatten from "@std/collections/collections.ms"

type Token:
    id: Int

impl Closeable for Token:
    var fn close() Unit!:
        return ok(unit)

impl Equal for Token:
    fn equals(other: Token) Bool:
        return self.id == other.id

type Holder:
    token: Token

fn concrete(values: List[Token], token: Token, nested: List[List[Token]]) Unit:
    let _distinct = values.distinct()  // error: Clonable
    let _repeated = filled(token, 2)  // error: Clonable
    let _flattened = flatten(nested)  // error: Clonable
    let _nested_distinct = nested.distinct()  // error: Clonable

fn callable_values(values: List[Token]) Unit:
    let _distinct = values.distinct  // error: Clonable
    let _repeat = filled[Token]  // error: Clonable
    let _concatenate = flatten[Token]  // error: Clonable

fn held_resource(holder: Holder) Unit:
    let _repeated = filled(holder, 2)  // error: Clonable
    let _flattened = flatten([[holder]])  // error: Clonable

fn distinct_unbounded[T: Equal](values: List[T]) List[T]:
    return values.distinct()  // error: Clonable

fn repeat_unbounded[T](value: T) List[T]!:
    return filled(value, 2)  // error: Clonable

fn flatten_unbounded[T](values: List[List[T]]) List[T]:
    return flatten(values)  // error: Clonable
