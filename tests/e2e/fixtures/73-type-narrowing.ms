// @test: Type Narrowing - Control flow based type refinement

// === Null Check Narrowing ===

fn process_optional(x: number?): number
  if x != null
    x * 2
  else
    0

fn inverse_null_check(x: string?): string
  if x == null
    "empty"
  else
    x.upper()

// === Negated Conditions ===

fn negated_null(x: number?): number
  if not (x == null)
    x + 1
  else
    0

// === Guard Narrowing in Match ===

fn guarded_match(n: number): string
  match n
    x if x < 0 => "negative"
    x if x == 0 => "zero"
    x if x > 0 => "positive"
    _ => "impossible"

// === Optional Chaining and Narrowing ===

type User
  profile: Profile?

type Profile
  name: string

fn get_username(u: User): string
  if u.profile != null
    u.profile.name
  else
    "anonymous"

// === Narrowing in Conditional ===

fn narrow_in_conditional(x: number?): number
  if x != null
    x * 2
  else
    0

// === is type check narrowing ===

fn demo_is_string(x: string or number): string
  if x is string
    "str:" + x
  else
    "num:" + to_str(x)

fn demo_is_optional(n: number?): string
  if n is number?
    "optional:" + to_str(n ?? 0)
  else
    "not-optional"

// @expect: str:hello
print(demo_is_string("hello"))
// @expect: num:42
print(demo_is_string(42))

// === Type guard declaration (predicate) ===
fn is_string_guard(x: unknown): x is string
  typeof(x) == "string"

fn use_guard(raw: unknown): string
  if is_string_guard(raw)
    "str:" + raw
  else
    "not-str"

// @expect: str:hello
print(use_guard("hello"))
// @expect: not-str
print(use_guard(42))
