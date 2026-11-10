+++
title = "When things go wrong"
weight = 3
+++

# When things go wrong

Order lines arrive as text such as `pen,2,150`. Some will be wrong: a missing field, a quantity of zero, a price that is not a number. These are not bugs in your program; they are input. A function that can fail says so in its return type.

<!-- manuscript-example: {"mode":"run","stdout":"good: 1199\nbad: quantity must be positive: ink,0,899\nbroken: quantity is not a number: pen,two,150\n"} -->
```manuscript {filename="lines.ms"}
type Line:
    name: String
    quantity: Int
    cents: Int

fn parse_line(text: String) Line!:
    parts := text.split(",")
    if parts.length() != 3:
        return error(Error("expected name,quantity,cents: {text}", kind: "EBADMSG"))
    quantity := try parts[1].parse_int().ok_or(Error("quantity is not a number: {text}", kind: "EINVAL"))
    if quantity <= 0:
        return error(Error("quantity must be positive: {text}", kind: "EINVAL"))
    cents := try parts[2].parse_int().ok_or(Error("price is not a number: {text}", kind: "EINVAL"))
    return ok(Line(parts[0].clone(), quantity, cents))

fn total(lines: List[String]) Int!:
    var sum = 0
    for text in lines:
        line := try parse_line(text)
        sum += line.quantity * line.cents
    return ok(sum)

fn main() Unit:
    good := total(["pen,2,150", "ink,1,899"])
    print("good: {good.get(0)}")
    bad := total(["pen,2,150", "ink,0,899"])
    if bad.is_error():
        print("bad: {bad.err().message}")
    broken := total(["pen,two,150"])
    if broken.is_error():
        print("broken: {broken.err().message}")
```

```text
good: 1199
bad: quantity must be positive: ink,0,899
broken: quantity is not a number: pen,two,150
```

Nothing is thrown. `total` returned an error value, and `main` decided what to print.

## What to notice

- `Int!` means "an `Int`, or an `Error`". It is short for `Result[Int, Error]`, and `Line!` works the same way. A caller cannot use the number without handling the other case.
- `return ok(value)` and `return error(Error(...))` are ordinary values with no hidden control flow.
- `try` unwraps a success. If the call failed, the function returns that error immediately. That is the whole error plumbing in `total`: one `try` per call that can fail.
- `parse_int()` returns an optional, because the text might not be a number. `.ok_or(error)` turns "nothing" into a specific error, so the message names the bad line.
- `kind` is a short code a caller can branch on, such as `"EINVAL"`. The standard library uses the same codes, so you never import a per-module error type.
- `good.get(0)` reads a result with a fallback. For a full branch use `if result.is_error():` as `main` does.

## Try it

Delete the `try` in front of `parse_line(text)` and run the program. The compiler stops you: `line` is now a `Result[Line, Error]`, which has no `quantity`. You cannot use a result as if it were its success value, and you cannot drop one unseen.

## Absent is not an error

`T?` is an optional: a value or nothing, with no error to explain. A map lookup and `first()` are optionals. Use `T!` when a failure needs a reason the caller can read, and `T?` when absence is normal.

**Next:** [Who owns what](ownership.md). **Exact rules:** [Results](../core-language/errors/results.md), [Propagation with try](../core-language/errors/propagation.md), [Optionals](../core-language/types/optionals.md).
