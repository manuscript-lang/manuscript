package lexer

import "embed"

// ImplementationSources pins compiler inputs without checkout-dependent paths.
//
//go:embed *.go
var ImplementationSources embed.FS
