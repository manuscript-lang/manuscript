// Package devtool selects the checkout's pinned SDK for maintenance subprocesses.
package devtool

import (
	"path/filepath"
	"runtime"
)

func Go() string {
	name := "go"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	absolute, err := filepath.Abs(filepath.Join("toolchain", "go", "bin", name))
	if err != nil {
		panic(err)
	}
	return absolute
}
