package ir

import "embed"

// ImplementationSources pins IR inputs without checkout-dependent paths.
//
//go:embed *.go
var ImplementationSources embed.FS
