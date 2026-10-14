package project

import "fmt"

// Location refers to the original manifest text, without importing source syntax.
// Offset is a byte offset; Line and Column are one-based.
type Location struct {
	File                 string
	Line, Column, Offset int
}

// Assignment retains both spellings so invalid keys and targets have distinct sites.
type Assignment struct{ Key, Value Location }

// ManifestError keeps manifest location data separate from its diagnostic cause.
type ManifestError struct {
	Location Location
	Cause    error
}

func (e *ManifestError) Error() string {
	return fmt.Sprintf("%s:%d:%d: %s", e.Location.File, e.Location.Line, e.Location.Column, e.Cause)
}

func (e *ManifestError) Unwrap() error { return e.Cause }
