package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// unsafeAllowed lists the only Rust locations that may contain `unsafe` code
// or lift the workspace `unsafe_code` lint. Extending it needs a reason in the
// change that edits it.
var unsafeAllowed = []string{
	"crates/ms-rt/",                // raw memory behind the C ABI compiled code links against
	"crates/ms-std-",               // C ABI shims (ffi.rs) of the standard-library native crates
	"crates/ms-rt-abi/",            // C-layout types and extern fn pointer types
	"crates/ms-cli/src/process.rs", // libc signal/kill; std has no signal API
}

var unsafeUse = regexp.MustCompile(`\bunsafe\s*(\{|fn\b|impl\b|trait\b|extern\b)|allow\(unsafe_code\)|forbid\(unsafe_code\)`)

// checkUnsafeBoundary reports Rust files outside unsafeAllowed that use unsafe.
func checkUnsafeBoundary(root string) ([]string, error) {
	var issues []string
	err := filepath.WalkDir(filepath.Join(root, "crates"), func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".rs") {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		for _, prefix := range unsafeAllowed {
			if strings.HasPrefix(rel, prefix) {
				return nil
			}
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if m := unsafeUse.Find(data); m != nil {
			issues = append(issues, fmt.Sprintf("%s uses unsafe (%q) outside the allowed Rust modules; see unsafeAllowed in scripts/repo-check/unsafe_boundary.go", rel, m))
		}
		return nil
	})
	return issues, err
}
