// docgen captures the implemented standard library from checker definitions.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/tooling/docgen"
	"os"
	"path/filepath"
)

func generate() (map[string][]byte, error) { return docgen.SiteFiles() }

// Published API downloads are built from the checked declarations when the
// site is built; they are not committed, so -check has nothing to compare.
var downloads = map[string]bool{"website/static/stdlib.md": true, "website/static/stdlib.json": true}

func main() {
	check := flag.Bool("check", false, "validate source documentation without writing generated files")
	onlyDownloads := flag.Bool("downloads", false, "write only the uncommitted API downloads (website/static/stdlib.*)")
	coverage := flag.String("coverage", "", "write a complete description inventory as JSON (includes prelude aliases)")
	flag.Parse()
	report := docgen.Inventory(checker.StandardLibrary())
	fmt.Fprintf(os.Stderr, "API descriptions: %d/%d declarations, %d/%d members (including prelude aliases)\n", report.DescribedDeclarations, report.Declarations, report.DescribedMembers, report.Members)
	fmt.Fprintf(os.Stderr, "Description quality: %d/%d declarations, %d/%d members pass structural checks; semantic review remains required\n", report.QualifiedDeclarations, report.Declarations, report.QualifiedMembers, report.Members)
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
	policy, err := docgen.StandardDescriptionPolicy()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if problems := docgen.CheckDescriptions(report, policy); len(problems) != 0 {
		for _, problem := range problems {
			fmt.Fprintln(os.Stderr, "API description:", problem)
		}
		os.Exit(1)
	}
	files, err := generate()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *check {
		return
	}
	// All book Markdown is disposable; rebuild its tree to retire removed routes.
	if !*onlyDownloads {
		if err := os.RemoveAll(".artifacts/docs"); err != nil {
			panic(err)
		}
	}
	for path, data := range files {
		if *onlyDownloads && !downloads[path] {
			continue
		}
		if !downloads[path] {
			path = filepath.Join(".artifacts/docs", path)
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			panic(err)
		}
		if err := os.WriteFile(path, data, 0644); err != nil {
			panic(err)
		}
	}
}
