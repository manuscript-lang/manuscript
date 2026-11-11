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
