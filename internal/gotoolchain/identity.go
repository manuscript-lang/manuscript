package gotoolchain

import "embed"

// ImplementationSources pins the build driver and the copied tools' release.
// The copied sources themselves are identified by VERSION.
//
//go:embed *.go VERSION
var ImplementationSources embed.FS
