// conform: tags=diagnostics
// conform: phase=check
// α😀 heading
//
// second line
fn documented() Int => 1
// detached

fn blank() Int => 2
// ordinary
fn first() Int => 3
fn bare() Int => 4
// neighboring recovered declaration
fn neighbor() Int => 5
fn broken(
// expect-error: MS1000 17:1 unterminated delimiter '(' opened at line 15:10; add the matching ')' before the end of the file
