package guide

import (
	_ "embed"
)

//go:embed cheatsheet.md
var cheatsheet string

// Cheatsheet is the one-page language guide for agents.
func Cheatsheet() string { return cheatsheet }
