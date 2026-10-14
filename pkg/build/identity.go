package build

import "embed"

// ImplementationSources pins build inputs without checkout-dependent paths.
//
//go:embed *.go
var ImplementationSources embed.FS
