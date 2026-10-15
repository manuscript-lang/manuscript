package rt

import "embed"

// Sources is embedded so generated programs can be built without runtime
// downloads. It holds every Go file of the package; consumers skip tests and
// files whose build constraints do not hold (the rtcheck signature checks).
//
//go:embed *.go
var Sources embed.FS
