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
    _distinct := values.distinct()  // error: Clonable
    _repeated := filled(token, 2)  // error: Clonable
    _flattened := flatten(nested)  // error: Clonable
    _nested_distinct := nested.distinct()  // error: Clonable

fn callable_values(values: List[Token]) Unit:
    _distinct := values.distinct  // error: Clonable
    _repeat := filled[Token]  // error: Clonable
    _concatenate := flatten[Token]  // error: Clonable

fn held_resource(holder: Holder) Unit:
    _repeated := filled(holder, 2)  // error: Clonable
    _flattened := flatten([[holder]])  // error: Clonable

fn distinct_unbounded[T: Equal](values: List[T]) List[T]:
    return values.distinct()  // error: Clonable

fn repeat_unbounded[T](value: T) List[T]!:
    return filled(value, 2)  // error: Clonable

fn flatten_unbounded[T](values: List[List[T]]) List[T]:
    return flatten(values)  // error: Clonable
