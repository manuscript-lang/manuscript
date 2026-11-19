# Teaching Manuscript

When someone who already programs asks how Manuscript works, or asks you to explain or onboard them, tell it in this order. Use short plain sentences, one idea at a time, and show the smallest code that proves each point. Run any example before showing it.

## 1. Every value has one owner

- Strings, lists, maps and records belong to exactly one name. There is no garbage collector and no reference counting; the value is freed when its owner leaves scope.
- Passing a value to a function lends it: the function reads it and you still own it. To change it, write `var` where it is declared and again at the call.
- Storing a value in a list or field moves it, and the old name stops working. The only way to get a second copy is `.clone()`; nothing is copied behind your back.
- Numbers and booleans are the exception: they copy freely.

```manuscript
fn add_name(var names: List[String], name: String) Void:
	names.append(name.clone())

fn main() Void:
	var names = List[String]()
	person := "Ada"
	add_name(var names, person)
	print(person)
```

`person` is still usable because the call stored a clone. Without `.clone()` the compiler says the value moved and was used again; that message is the lesson.

## 2. Failure is a value

- A type ending in `!` can fail; a type ending in `?` can be missing. Neither is thrown.
- `?` after a call means: on failure or absence, return from this function with that. The normal path reads straight down.
- A crash such as indexing past the end of a list is a bug in the program, not something to catch.

## 3. Data is plain

- Facts are a `type`, states are an `enum`, and `match` covers every case. No classes, no inheritance, no null, no tuples (use a small record).
- Methods are written beside the type, not inside it.
- Add an enum case and the compiler lists every `match` to update. The type is your to-do list.

## 4. Side effects are visible

- A function that prints, reads files, uses the network or the clock is flagged unless a comment above it permits that effect.
- Keep the core logic pure and hand it a logger, clock or price lookup from `main`. A test passes a fake.

## 5. Waiting has no keyword

- No `async`. A call that waits, such as reading a file, returns a promise that is already running; call `.wait()` for the result.
- Tasks never share changeable state. One task owns it and the rest send messages through a pipe. A web handler follows the same rule.

## 6. The compiler teaches

- Each error says what is wrong and what to write instead. `ms check --fix` repairs the mechanical ones.
- `ms search_symbol <words>` finds the standard function, so nobody guesses a name from another language.
- The daily loop: write, `ms check`, `ms test`, `ms verify`.

## Where people from other languages trip

- Strings are bytes: `length()` counts bytes, there is no `text[i]`, and raw bytes must be decoded before they print as text.
- Generics use brackets, `List[Int]`, not `List<Int>`. `not x`, not `!x`.
- Methods always take parentheses: `xs.length()`.
- No `try`, `throw`, `null`, `async`, tuples or operator overloading.

Point them to [Mental model](mental-model.md) for the reasons and [Workflow](workflow.md) for the first project.
