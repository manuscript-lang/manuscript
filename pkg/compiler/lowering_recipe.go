package compiler

import "github.com/manuscript-lang/manuscript/pkg/checker"

// Keep the recipe with its result rather than retaining checked programs in a
// global cache. The public Source remains the default/Release representation.
type loweringRecipe struct {
	program *checker.Program
	entry   string
	options Options
	source  string
}

func (r Result) sourceForBuild(kind BuildType) (string, error) {
	recipe := r.lowering
	if kind != Debug || recipe == nil || r.Source != recipe.source || r.Program != recipe.program {
		// Edited/handwritten Go is the caller's input, including in Debug.
		return r.Source, nil
	}
	return lowerGoForBuild(optimize(recipe.program), recipe.entry, recipe.options, Debug)
}
