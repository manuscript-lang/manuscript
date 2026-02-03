// @test: Match Expressions - Match as expression returning values

// === Basic match expression ===
fn grade(score: number): string
  match score
    100 => "perfect"
    _ => "other"

// @expect: perfect
print(grade(100))
// @expect: other
print(grade(50))

// === Match expression in variable ===
let status = 200
let message = match status
  200 => "OK"
  404 => "Not Found"
  500 => "Server Error"
  _ => "Unknown"

// @expect: OK
print(message)

// === Match with guards in expression ===
fn classify_number(n: number): string
  match n
    x if x < 0 => "negative"
    0 => "zero"
    x if x < 10 => "small"
    x if x < 100 => "medium"
    _ => "large"

// @expect: negative
print(classify_number(-5))
// @expect: zero
print(classify_number(0))
// @expect: small
print(classify_number(5))
// @expect: medium
print(classify_number(50))
// @expect: large
print(classify_number(500))

// === Match expression with range patterns ===
fn http_category(code: number): string
  match code
    x if x >= 100 and x <= 199 => "informational"
    x if x >= 200 and x <= 299 => "success"
    x if x >= 300 and x <= 399 => "redirect"
    x if x >= 400 and x <= 499 => "client error"
    x if x >= 500 and x <= 599 => "server error"
    _ => "unknown"

// @expect: success
print(http_category(200))
// @expect: client error
print(http_category(404))
// @expect: server error
print(http_category(503))
// @expect: unknown
print(http_category(999))

// === Match expression with string patterns ===
fn day_type(day: string): string
  match day
    "Saturday" => "weekend"
    "Sunday" => "weekend"
    _ => "weekday"

// @expect: weekend
print(day_type("Saturday"))
// @expect: weekday
print(day_type("Monday"))

// === Match returning different types (union) ===
fn maybe_number(flag: bool): number?
  match flag
    true => 42
    false => null

// @expect: 42
print(maybe_number(true) ?? 0)
// @expect: 0
print(maybe_number(false) ?? 0)

// === Match expression assigned to variable ===
fn get_status_text(code: number): string
  let text = match code
    200 => "OK"
    201 => "Created"
    204 => "No Content"
    _ => "Unknown"
  return text

// @expect: OK
print(get_status_text(200))
// @expect: Created
print(get_status_text(201))
// @expect: Unknown
print(get_status_text(999))

// === Match used in computation ===
fn calculate(op: string, a: number, b: number): number
  let result = match op
    "add" => a + b
    "sub" => a - b
    "mul" => a * b
    "div" => a / b
    _ => 0
  return result

// @expect: 15
print(calculate("add", 10, 5))
// @expect: 5
print(calculate("sub", 10, 5))
// @expect: 50
print(calculate("mul", 10, 5))
// @expect: 0
print(calculate("unknown", 10, 5))
