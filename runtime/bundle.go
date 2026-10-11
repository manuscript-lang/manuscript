package msruntime

import "embed"

// Sources is embedded so generated programs can be built without runtime downloads.
//
//go:embed values.go numeric.go collections.go tasks.go host.go background.go lifetime.go services.go http.go process.go
var Sources embed.FS
