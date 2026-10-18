package checker

import (
	"slices"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Source-backed prelude types retain their standard declaration identities.
var standardPreludeNames = []string{"Equal", "Comparable", "Hashable", "Optional", "Result", "Error", "List", "Map", "Set", "CollectionError", "ListEntry", "MapEntry", "MissingValue"}

// IsPreludeSymbol reports whether a symbol is a canonical source-backed prelude
// declaration. Application declarations with the same name retain their identity.
func IsPreludeSymbol(symbol *Symbol) bool {
	ensureStandard()
	return isPreludeSymbol(symbol)
}

func isPreludeSymbol(symbol *Symbol) bool {
	return symbol != nil && slices.Contains(standardPreludeNames, symbol.Name) && standardSymbols[symbol.Name] == symbol
}

// primitiveNames are the built-in types every module sees without an import.
var primitiveNames = []string{"Bool", "Int", "Float", "String", "Unit", "Never"}

// PreludeTypeNames lists every type name available without an import.
func PreludeTypeNames() []string {
	return append(append([]string{}, primitiveNames...), standardPreludeNames...)
}

// preludeCaseNames are prelude constructors a declaration may not replace.
var preludeCaseNames = []string{"some", "none", "ok", "error"}

func (c *checker) addStandardPrelude() {
	if !strings.HasPrefix(c.module.File, "@std/") {
		for _, decl := range c.module.Declarations {
			if decl.Kind != syntax.KindImpl && decl.Kind != syntax.KindTest && slices.Contains(preludeCaseNames, decl.Name) {
				c.error(decl.Pos, "resolution", "declaration "+decl.Name+" reuses a prelude constructor name; rename it, because "+decl.Name+" always refers to the prelude case")
			}
		}
	}
	for _, name := range standardPreludeNames {
		symbol := standardSymbols[name]
		if symbol.Module == c.module.File {
			continue
		}
		// A redundant standard import is reported on its own; a declaration or
		// application import that reuses the name is rejected by addSymbol.
		explicit := false
		for _, item := range c.module.Imports {
			if item.Name == name && strings.HasPrefix(item.Path, "@std/") {
				explicit = true
			}
		}
		if !explicit {
			c.names[name] = symbol
		}
	}
}
