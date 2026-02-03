// @test: Match Expression Edge Cases - Pattern matching stress test

// === Match with number ranges ===
fn grade(score: number): string
  match score
    90..100 => "A"
    80..89 => "B"
    70..79 => "C"
    60..69 => "D"
    _ => "F"

// @expect: A
print(grade(95))
// @expect: B
print(grade(85))
// @expect: F
print(grade(50))

// === Match with guards ===
fn describe(n: number): string
  match n
    x if x < 0 => "negative"
    0 => "zero"
    x if x % 2 == 0 => "positive even"
    x if x % 2 == 1 => "positive odd"
    _ => "?"

// @expect: negative
print(describe(-5))
// @expect: zero
print(describe(0))
// @expect: positive even
print(describe(4))
// @expect: positive odd
print(describe(7))

// === Match on optional ===
fn unwrap_or(opt: number?, fallback: number): number
  match opt
    null => fallback
    n => n

// @expect: 42
print(unwrap_or(42, 0))
// @expect: 0
print(unwrap_or(null, 0))

// === Match as expression in various contexts ===
let match_result = match 5
  1 => "one"
  2 => "two"
  _ => "many"
// @expect: many
print(match_result)

// === Match with list length ===
fn describe_list_len(items: list[number]): string
  match len(items)
    0 => "empty"
    1 => "single"
    2 => "pair"
    _ => "many items"

// @expect: empty
print(describe_list_len([]))
// @expect: single
print(describe_list_len([42]))
// @expect: pair
print(describe_list_len([1, 2]))
// @expect: many items
print(describe_list_len([1, 2, 3]))

// === Match with computed values (fibonacci) ===
fn fib(n: number): number
  match n
    0 => 0
    1 => 1
    _ => fib(n - 1) + fib(n - 2)

// @expect: 0
print(fib(0))
// @expect: 1
print(fib(1))
// @expect: 55
print(fib(10))

// === Match with string patterns ===
fn parse_command(cmd: string): string
  match cmd
    "quit" => "exiting"
    "help" => "showing help"
    _ => "unknown: {cmd}"

// @expect: exiting
print(parse_command("quit"))
// @expect: showing help
print(parse_command("help"))
// @expect: unknown: foo
print(parse_command("foo"))

// === Nested match expressions ===
fn classify_pair(a: number, b: number): string
  match a
    0 => match b
      0 => "both zero"
      _ => "a is zero"
    _ => match b
      0 => "b is zero"
      _ => "neither zero"

// @expect: both zero
print(classify_pair(0, 0))
// @expect: a is zero
print(classify_pair(0, 5))
// @expect: b is zero
print(classify_pair(5, 0))
// @expect: neither zero
print(classify_pair(5, 5))

// === Match with boolean patterns ===
fn bool_to_str(b: bool): string
  match b
    true => "yes"
    false => "no"

// @expect: yes
print(bool_to_str(true))
// @expect: no
print(bool_to_str(false))

// === Match return value used in expression ===
fn get_multiplier(mode: string): number
  match mode
    "double" => 2
    "triple" => 3
    _ => 1

// @expect: 20
print(10 * get_multiplier("double"))
// @expect: 30
print(10 * get_multiplier("triple"))
// @expect: 10
print(10 * get_multiplier("normal"))
