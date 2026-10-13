package compiler

import (
	"fmt"
	"strings"
)

// BuildType selects native optimization and debugging information.
type BuildType string

const (
	Debug          BuildType = "Debug"
	Release        BuildType = "Release"
	RelWithDebInfo BuildType = "RelWithDebInfo"
	MinSizeRel     BuildType = "MinSizeRel"
)

// ParseBuildType accepts the familiar CMake names, ignoring case. Empty means Release.
func ParseBuildType(name string) (BuildType, error) {
	if name == "" {
		return Release, nil
	}
	for _, kind := range []BuildType{Debug, Release, RelWithDebInfo, MinSizeRel} {
		if strings.EqualFold(name, string(kind)) {
			return kind, nil
		}
	}
	return "", fmt.Errorf("unknown build type %q; expected Debug, Release, RelWithDebInfo, or MinSizeRel", name)
}

func (kind BuildType) sourcePaths() bool { return kind == Debug || kind == RelWithDebInfo }

// goFlags reports the go command's -gcflags and -ldflags settings and
// whether paths are trimmed for a build type.
func (kind BuildType) goFlags() (gcflags, ldflags string, trimpath bool) {
	switch kind {
	case Debug:
		// Uncompressed DWARF links faster; Debug artifacts favor rebuild time.
		return "all=-N -l", "-compressdwarf=false", false
	case RelWithDebInfo:
		return "", "", false
	default:
		// Go has no size-specific optimizer; both release types use its
		// normal optimizer and omit symbol tables and DWARF information.
		return "", "-s -w", true
	}
}

func (kind BuildType) nativeFlags() []string {
	gcflags, ldflags, trimpath := kind.goFlags()
	var flags []string
	if trimpath {
		flags = append(flags, "-trimpath")
	}
	if gcflags != "" {
		flags = append(flags, "-gcflags="+gcflags)
	}
	if ldflags != "" {
		flags = append(flags, "-ldflags="+ldflags)
	}
	return flags
}
