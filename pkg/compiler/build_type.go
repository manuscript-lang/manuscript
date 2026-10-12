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

func (kind BuildType) nativeFlags() []string {
	switch kind {
	case Debug:
		return []string{"-gcflags=all=-N -l"}
	case RelWithDebInfo:
		return nil
	default:
		// Go has no size-specific optimizer; both release types use its
		// normal optimizer and omit symbol tables and DWARF information.
		return []string{"-trimpath", "-ldflags=-s -w"}
	}
}
