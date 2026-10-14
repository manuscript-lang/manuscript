package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// primitiveTypeNames are the built-in types that need no declaration.
var primitiveTypeNames = []string{"Int", "Float", "String", "Bool", "Unit", "Never"}

// BuiltinTypeNames lists every type name available without an import.
func BuiltinTypeNames() []string {
	return append(append([]string{}, primitiveTypeNames...), standardPreludeNames...)
}

// Source-backed prelude types retain their standard declaration identities.
var standardPreludeNames = []string{"Equal", "Hashable", "Optional", "Result", "Error", "List", "Map", "Set"}

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
