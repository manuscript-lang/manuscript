package project

import "embed"

// ImplementationSources participates in compiler pins and native cache identity.
//
//go:embed *.go
var ImplementationSources embed.FS
