// @test: Control Flow Errors - Loop and Branch Issues

// === Nested break invalid ===
fn bad_break()
  break
bad_break()
// @error: outside of loop

// === Nested continue invalid ===
fn bad_continue()
  continue
bad_continue()
// @error: outside of loop
