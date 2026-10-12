package manuscriptsupport

import (
	_ "embed"
	"strings"
)

// The CLI, build pins, and documentation share one release version.
//
//go:embed .msversion
var releaseVersion string

func Version() string { return strings.TrimSpace(releaseVersion) }
