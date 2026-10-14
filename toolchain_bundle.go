package manuscriptsupport

import _ "embed"

// GoToolchainArchive contains only Manuscript's native build tools and references.
//
//go:embed .build-payload.tar.gz
var GoToolchainArchive []byte
