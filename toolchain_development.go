//go:build !bundled_toolchain

package manuscriptsupport

// Direct go builds may use MANUSCRIPT_GO or PATH; make build embeds the SDK.
var GoToolchainArchive []byte
