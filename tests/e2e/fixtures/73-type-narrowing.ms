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
