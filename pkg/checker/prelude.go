package checker

import (
	"slices"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Source-backed prelude types retain their standard declaration identities.
var standardPreludeNames = []string{"Equal", "Hashable", "Optional", "Result", "Error", "List", "Map", "Set", "CollectionError", "ListEntry", "MapEntry", "MissingValue"}

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

func (c *checker) addStandardPrelude() {
	for _, name := range standardPreludeNames {
		symbol := standardSymbols[name]
		if symbol.Module == c.module.File {
			continue
		}
		explicit := false
		for _, item := range c.module.Imports {
			if item.Name == name {
				explicit = true
			}
		}
		// Prelude data types are ordinary standard declarations;
		// module declarations may select a local identity instead.
		if name != "Equal" && name != "Hashable" {
			for _, decl := range c.module.Declarations {
				if decl.Kind != syntax.KindImpl && decl.Kind != syntax.KindTest && decl.Name == name {
					explicit = true
				}
			}
		}
		if !explicit {
			c.names[name] = symbol
		}
	}
}
