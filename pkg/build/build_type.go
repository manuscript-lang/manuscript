package build

import "github.com/manuscript-lang/manuscript/pkg/compiler"

func sourcePaths(kind compiler.BuildType) bool {
	return kind == compiler.Debug || kind == compiler.RelWithDebInfo
}

func nativeFlags(kind compiler.BuildType) []string {
	switch kind {
	case compiler.Debug:
		// Uncompressed DWARF links faster; Debug artifacts favor rebuild time.
		return []string{"-gcflags=all=-N -l", "-ldflags=-compressdwarf=false"}
	case compiler.RelWithDebInfo:
		return nil
	default:
		// Go has no size-specific optimizer; both release types use its
		// normal optimizer and omit symbol tables and DWARF information.
		return []string{"-trimpath", "-ldflags=-s -w"}
	}
}
