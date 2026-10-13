// docgen captures the implemented standard library from checker definitions.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/tooling/docgen"
	"os"
	"path/filepath"
)

func generate() (map[string][]byte, error) { return docgen.SiteFiles() }
func main() {
	check := flag.Bool("check", false, "fail if generated documentation differs")
	coverage := flag.String("coverage", "", "write a complete description inventory as JSON (includes prelude aliases)")
	flag.Parse()
	report := docgen.Inventory(checker.StandardLibrary())
	fmt.Fprintf(os.Stderr, "API descriptions: %d/%d declarations, %d/%d members (including prelude aliases)\n", report.DescribedDeclarations, report.Declarations, report.DescribedMembers, report.Members)
	if *coverage != "" {
		data, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := os.MkdirAll(filepath.Dir(*coverage), 0755); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := os.WriteFile(*coverage, append(data, '\n'), 0644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	files, err := generate()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	failed := false
	for path, data := range files {
		if *check {
			old, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(old, data) {
				fmt.Fprintln(os.Stderr, "stale documentation:", path)
				failed = true
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			panic(err)
		}
		if err := os.WriteFile(path, data, 0644); err != nil {
			panic(err)
		}
	}
	// Removed modules must not leave misleading reference pages behind.
	paths, _ := filepath.Glob("documentation/standard-library/reference/*.md")
	for _, path := range paths {
		if _, ok := files[path]; !ok {
			if *check {
				fmt.Fprintln(os.Stderr, "obsolete documentation:", path)
				failed = true
			} else if err := os.Remove(path); err != nil {
				panic(err)
			}
		}
	}
	if failed {
		os.Exit(1)
	}
}
