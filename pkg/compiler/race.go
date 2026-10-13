//go:build race

package compiler

// A race-instrumented executable would run the built-in Go tools with race
// instrumentation too, several times slower; such test binaries use the go
// command. internal/gotoolchain's own tests cover the built-in tools under race.
const raceEnabled = true
