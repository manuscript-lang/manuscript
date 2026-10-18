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
            sum = sum + value
    return sum

fn check(value: Bool, message: String) Unit:
    if not value:
        panic(message: message)

test "if let unwraps a present optional":
    if let value = [4, 5].first():
        check(value: value == 4, message: "wrong value")
    else:
        panic(message: "expected some")

test "if let takes else when absent and keeps falsy payloads":
    check(value: describe(none) == "Hello!", message: "none")
    check(value: describe(some("Ada")) == "Hello, Ada", message: "some")
    let items: List[Optional[Int]] = [some(1), none, some(0), some(2)]
    check(value: total(items) == 3, message: "total")
    let empty: List[Int] = []
    if let value = empty.first():
        panic(message: "unexpected {value}")

fn parse(text: String) Result[Int, String]:
    if text == "":
        return error("empty")

    return ok(text.length())

test "if let unwraps an ok result and takes else on error":
    if let value = parse("abc"):
        check(value: value == 3, message: "ok value")
    else:
        panic(message: "expected ok")

    if let value = parse(""):
        panic(message: "unexpected {value}")
    else:
        check(value: true, message: "error branch")
