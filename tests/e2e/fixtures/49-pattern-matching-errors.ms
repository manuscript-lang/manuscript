// @test: Pattern Matching Errors - Guard and Expression Errors

// === Guard using undefined variable ===
match 10
  x if unknown_var => "bad"
  _ => "ok"
// @error: Unknown identifier

// === Match arm calling undefined function ===
match 5
  1 => undefined_fn()
  _ => 0
// @error: Unknown identifier
