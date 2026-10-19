//go:build ignore

// extract_go_sources lists string literals in Go tests that look like
// Manuscript source, as JSON lines {file,line,func,label,text}. Run from the
// repository root of the Go implementation:
//
//	go run tests/conformance/tools/extract_go_sources.go . > sources.jsonl
package main

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var looks = regexp.MustCompile(`(?m)^(export fn |fn |type |import |interface |impl |test "|let |var |const )`)

type record struct {
	File  string `json:"file"`
	Line  int    `json:"line"`
	Func  string `json:"func"`
	Label string `json:"label"`
	Text  string `json:"text"`
}

func main() {
	root := os.Args[1]
	enc := json.NewEncoder(os.Stdout)
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			switch info.Name() {
			case "vendor", "toolchain", "website", ".git", "node_modules", "experiments":
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, "_test.go") {
			return nil
		}
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		for _, decl := range file.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok {
				continue
			}
			name := fn.Name.Name
			var prev string
			ast.Inspect(fn, func(n ast.Node) bool {
				lit, ok := n.(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					return true
				}
				text, err := strconv.Unquote(lit.Value)
				if err != nil {
					return true
				}
				if strings.Contains(text, "\n") && looks.MatchString(text) && len(text) < 20000 {
					enc.Encode(record{rel, fset.Position(lit.Pos()).Line, name, prev, text})
				} else if !strings.Contains(text, "\n") && len(text) < 80 {
					prev = text
				}
				return true
			})
		}
		return nil
	})
	fmt.Fprintln(os.Stderr, "done")
}
