// Package manuscriptsupport supplies pinned offline dependencies, the bundled
// toolchain, and the release version for native builds. Go embed paths cannot
// traverse upward, so this file stays beside go.mod, vendor/, .msversion, and
// the generated toolchain payload.
package manuscriptsupport

import (
	"embed"
	"strings"
)

// NativeDependencies includes source and licenses, not a network download hook.
//
//go:embed go.mod go.sum vendor internal/hostos/*.go internal/nativeabi/*.go internal/decimal/*.go
var NativeDependencies embed.FS

// GoToolchainArchive contains only Manuscript's native build tools and references.
//
//go:embed .build-payload.tar.gz
var GoToolchainArchive []byte

// The CLI, build pins, and documentation share one release version.
//
//go:embed .msversion
var releaseVersion string

func Version() string { return strings.TrimSpace(releaseVersion) }
