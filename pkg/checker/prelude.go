package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Source-backed prelude types retain their standard declaration identities.
var standardPreludeNames = []string{"Equal", "Hashable", "Optional", "Result", "Error"}

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
		// Optional, Result, and Error are ordinary standard declarations;
		// module declarations may select a local identity instead.
		if name == "Optional" || name == "Result" || name == "Error" {
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
