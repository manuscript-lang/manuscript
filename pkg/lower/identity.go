package lower

import "embed"

// ImplementationSources pins lowering inputs without checkout-dependent paths.
//
//go:embed *.go
var ImplementationSources embed.FS
