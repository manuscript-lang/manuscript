// @test: Pattern Matching Validation - Type checking for patterns

// === Literal Pattern Type Mismatch ===

fn check_string(s: string): bool
  match s
    42 => true
    _ => false
// @error: cannot match

fn check_number(n: number): string
  match n
    "hello" => "bad"
    _ => "ok"
// @error: cannot match

// === Object Pattern Property Validation ===

type User
  name: string
  age: number

fn match_user(u: User): string
  match u
    {name, invalid_prop} => name
    _ => "unknown"
// @error: does not exist

// === Array Pattern on Non-List ===

fn bad_array_pattern(n: number): number
  let [a, b] = n
  0
// @error: Cannot use array pattern

// === Type Pattern Compatibility ===

type TypeA
  x: number

type TypeB
  y: string

fn match_a(a: TypeA): string
  match a
    TypeB as b => b.y
    _ => "default"
// @error: not compatible

// === Range Pattern on Non-Number ===

fn match_string_range(s: string): bool
  match s
    1..10 => true
    _ => false
// @error: require numeric

// === Guard Expression Type Check ===

fn bad_guard(n: number): string
  match n
    x if "not a bool" => "bad"
    _ => "ok"
// @error: must be bool

fn good_guard(n: number): string
  match n
    x if x > 10 => "big"
    _ => "small"

// === Exhaustiveness Checking ===

fn bool_match(b: bool): string
  match b
    true => "yes"
// @error: not exhaustive

// Exhaustive matches (should pass)
fn complete_optional(x: number?): string
  match x
    null => "none"
    n => "some"

fn complete_bool(b: bool): string
  match b
    true => "yes"
    false => "no"

// === Valid Patterns (should pass) ===

fn valid_literal_match(n: number): string
  match n
    0 => "zero"
    1 => "one"
    _ => "other"

fn valid_object_destructure(u: User): string
  let {name, age} = u
  name

fn valid_array_destructure(nums: list[number]): number
  let [first, ...rest] = nums
  first ?? 0
