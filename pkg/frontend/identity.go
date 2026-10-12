package frontend

import "embed"

// ImplementationSources includes parsing and graph orchestration in build pins.
//
//go:embed *.go
var ImplementationSources embed.FS
