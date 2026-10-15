package msruntime

import (
	"embed"
	"go/build/constraint"
	"io/fs"
	"strings"
)

//go:embed *.go
var sources embed.FS

// Sources holds the runtime files a generated program builds with, embedded so
// builds need no download. Tests and the rtcheck signature checks are not part
// of a build and are not visible through Sources.
var Sources buildFiles

type buildFiles struct{}

func (buildFiles) include(name string) bool {
	if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") || name == "bundle.go" {
		return false
	}
	data, err := sources.ReadFile(name)
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "package ") {
			break
		}
		if expression, err := constraint.Parse(line); err == nil {
			return expression.Eval(func(string) bool { return false })
		}
	}
	return true
}

// ReadDir lists the files of a build.
func (b buildFiles) ReadDir(name string) ([]fs.DirEntry, error) {
	entries, err := sources.ReadDir(name)
	if err != nil {
		return nil, err
	}
	kept := entries[:0:0]
	for _, entry := range entries {
		if b.include(entry.Name()) {
			kept = append(kept, entry)
		}
	}
	return kept, nil
}

// ReadFile reads one file of a build.
func (b buildFiles) ReadFile(name string) ([]byte, error) {
	if !b.include(name) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrNotExist}
	}
	return sources.ReadFile(name)
}

// Open opens one file of a build, or the directory listing.
func (b buildFiles) Open(name string) (fs.File, error) {
	if name != "." && !b.include(name) {
		return nil, &fs.PathError{Op: "open", Path: name, Err: fs.ErrNotExist}
	}
	return sources.Open(name)
}
