import panic from "@std/faults.ms"

fn describe(name: Optional[String]) String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"

fn total(items: List[Optional[Int]]) Int:
    var sum = 0
    for item in items:
        if let value = item:
            sum += value
    return sum

fn check(value: Bool, message: String) Unit:
    if not value:
        panic(message)

test "if let unwraps a present optional":
    if let value = [4, 5].first():
        check(value == 4, "wrong value")
    else:
        panic("expected some")

test "if let takes else when absent and keeps falsy payloads":
    check(describe(none) == "Hello!", "none")
    check(describe(some("Ada")) == "Hello, Ada", "some")
    let items: List[Optional[Int]] = [some(1), none, some(0), some(2)]
    check(total(items) == 3, "total")
    let empty: List[Int] = []
    if let value = empty.first():
        panic("unexpected {value}")

fn parse(text: String) Result[Int, String]:
    if text == "":
        return error("empty")

    return ok(text.length())

test "if let unwraps an ok result and takes else on error":
    if let value = parse("abc"):
        check(value == 3, "ok value")
    else:
        panic("expected ok")

    if let value = parse(""):
        panic("unexpected {value}")
    else:
        check(true, "error branch")
