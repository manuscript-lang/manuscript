// @test: Pattern Matching - Match expressions

// === Match with literals ===
fn describe(n: number): string
  match n
    0 => "zero"
    1 => "one"
    2 => "two"
    _ => "other"

// @expect: one
print(describe(1))
// @expect: other
print(describe(42))

// === Match strings ===
fn http_status(code: number): string
  match code
    200 => "OK"
    404 => "Not Found"
    500 => "Server Error"
    _ => "Unknown"

// @expect: OK
print(http_status(200))
// @expect: Not Found
print(http_status(404))
// @expect: Unknown
print(http_status(999))

// === Grade classification with if-else ===
fn grade(score: number): string
  if score >= 90 then return "A"
  if score >= 80 then return "B"
  if score >= 70 then return "C"
  if score >= 60 then return "D"
  "F"

// @expect: B
print(grade(85))
// @expect: A
print(grade(95))
// @expect: F
print(grade(45))

// === Day type ===
fn day_type(day: string): string
  match day
    "Saturday" => "weekend"
    "Sunday" => "weekend"
    _ => "weekday"

// @expect: weekday
print(day_type("Monday"))
// @expect: weekend
print(day_type("Saturday"))

// === Number classification with if-else ===
fn classify(n: number): string
  if n < 0 then return "negative"
  if n == 0 then return "zero"
  if n < 10 then return "small"
  if n < 100 then return "medium"
  "large"

// @expect: small
print(classify(5))
// @expect: medium
print(classify(50))
// @expect: large
print(classify(500))
// @expect: negative
print(classify(-5))

// === Match with guard ===
fn categorize(n: number): string
  match n
    x if x > 100 => "large"
    x if x > 10 => "medium"
    x if x > 0 => "small"
    _ => "non-positive"

// @expect: large
print(categorize(500))
// @expect: medium
print(categorize(50))
// @expect: small
print(categorize(5))
// @expect: non-positive
print(categorize(-1))
