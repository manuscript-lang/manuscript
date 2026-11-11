# Types and functions

Named functions declare parameter and return types: `fn f(value: Int, offset: Int = 1) Int:`. Labels are optional at calls: `f(2, offset: 3)`. Generic parameters follow the name, as in `fn identity[T](value: T) T`. A callback type is `fn(Int) Int`; closures can be `fn x: x + 1` or `fn(x: Int) Int: x + 1`.

Save as `types.ms`:

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

`ms run types.ms` prints nothing and exits 0.

- Own receiver methods with matching names, parameter labels/types, mutability and result types satisfy an interface by shape. Explicit implementations use `impl Contract for Type:` with method declarations inside.
- Enum cases are declared directly, without a `case` keyword. Construct with `Choice.Empty` or `Choice.Number(40)`. Match arms must be exhaustive; `_:` is the fallback.

Keep match flow flat: return early or extract a payload before the next decision. Use Optional/Result methods and conditional bindings for their normal control flow. Generic operations need appropriate bounds, for example `T: Clonable` when copying T; do not assume every value can be cloned.
