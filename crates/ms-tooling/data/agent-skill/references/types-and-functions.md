# Types and functions

Declare parameter/return types: `fn f(value: Int, offset: Int = 1) Int:`. Call labels are optional: `f(2, offset: 3)`. Generics follow the name. Callback type: `fn(Int) Int`; closures: `fn x: x + 1` or `fn(x: Int) Int: x + 1`.

<!-- complete: types.ms -->
```manuscript
interface Apply:
	fn apply(value: Int) Int

type Offset:
	delta: Int

fn Offset.apply(value: Int) Int:
	return value + self.delta

fn use(value: Int, operation: Apply) Int:
	return operation.apply(value)

fn identity[T](value: T) T: value

enum Choice:
	Empty
	Number(value: Int)

fn number(choice: Choice) Int:
	match choice:
		Empty: return 0
		Number(value): return value

fn main() Int:
	chosen := Choice.Number(identity(40))
	if use(number(chosen), Offset(2)) == 42: return 0
	return 1
```

Receiver methods satisfy interfaces by shape: names, parameter labels/types/mutability and return types must match. A read-only receiver method may satisfy a mutable receiver operation. Declare methods at module scope; there are no `impl` blocks.

Enum cases need no `case` keyword. Construct `Choice.Empty` or `Choice.Number(40)`. Match exhaustively; `_:` handles the remainder. Keep matches flat.

Generic operations need bounds, such as `T: Clonable` for copying T. Not every type is cloneable.

A generic type takes its parameter after the name and its methods repeat it: `type Repository[T]:` with `items: List[T] = []`, built `Repository[Book]()`. A method names one receiver argument per type parameter: `fn Lru[K, V].size() Int:`. A method that calls an interface member on `T` states the bound on the receiver: `fn var Repository[T: Searchable].add(item: T) Void:`. Combine bounds with `&`: `T: Searchable & Clonable`. `fn var` belongs to methods only; a free function takes `var` on the parameter: `fn transfer(var from: Account)`. There are no static methods or constructors: build a record by calling the type, or write a free function such as `new_store()`.

Required fields and parameters come before optional (defaulted) ones. A function without a result type is an error: write `Void`. Functions are called as `f(x)`, never `x.f()`; only methods declared with a receiver use dot syntax. Bool and enums have no `compare`: order them with a small rank function. Enums read and write JSON as the case name (`"High"`).

`List[Txn]` does not convert to `List[Auditable]` (lists are invariant): write `fn report[T: Auditable](items: List[T])`. There are no bit operators (`&` is not `and`); `bit_and`, `bit_or`, `bit_xor` and `shift_left` come from `@std/math/math.ms`. A String from character codes is `from_scalars(List[Int])` in `@std/string.ms`; upper-casing is `upper()`.
