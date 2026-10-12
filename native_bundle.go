// Package manuscriptsupport supplies pinned offline dependencies for native builds.
package manuscriptsupport

import "embed"

// NativeDependencies includes source and licenses, not a network download hook.
//
//go:embed go.mod go.sum vendor internal/hostos/*.go
var NativeDependencies embed.FS
