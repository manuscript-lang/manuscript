package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Source-backed prelude types retain their standard declaration identities.
var standardPreludeNames = []string{"Equal", "Hashable", "Optional", "Result", "Error", "List", "Map", "Set"}

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
