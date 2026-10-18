package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"sort"
)

type fact struct {
	Offset                                                                 int
	Kind, Text, Type, Native, Symbol, Method, Constructor, Error, Optional string
	Args                                                                   []string
	TypeArgs                                                               []string
}
type evidence struct {
	File        string
	Source      string
	Diagnostics []syntax.Diagnostic
	Effects     map[string][]string
	Facts       []fact
}

func main() {
	encoder := json.NewEncoder(os.Stdout)
	for _, category := range []string{"accept", "reject"} {
		files, err := filepath.Glob("tests/e2e/testdata/" + category + "/*.ms")
		if err != nil {
			panic(err)
		}
		for _, file := range files {
			source, err := os.ReadFile(file)
			if err != nil {
				panic(err)
			}
			result := compiler.CompileSource(file, string(source), compiler.Options{Tests: true})
			hash := sha256.Sum256([]byte(result.Source))
			item := evidence{File: file, Source: hex.EncodeToString(hash[:]), Diagnostics: result.Diagnostics}
			sort.Slice(item.Diagnostics, func(i, j int) bool {
				a, b := item.Diagnostics[i], item.Diagnostics[j]
				if a.Position.Offset != b.Position.Offset {
					return a.Position.Offset < b.Position.Offset
				}
				return a.Phase+a.Message < b.Phase+b.Message
			})
			if result.Program != nil {
				item.Effects = result.Program.Effects
				for expr, info := range result.Program.Expressions() {
					f := fact{Offset: expr.Pos.Offset, Kind: expr.Kind, Text: expr.Text, Type: info.Type.String(), Native: info.Native}
					if info.Symbol != nil {
						f.Symbol = info.Symbol.ID
					}
					if info.Method != nil {
						f.Method = info.Method.ID
					}
					if info.Constructor != nil {
						f.Constructor = info.Constructor.String()
					}
					if info.ErrorSource != nil {
						f.Error = info.ErrorSource.String()
					}
					if info.OptionalArgument != nil {
						f.Optional = info.OptionalArgument.String()
					}
					for _, a := range info.Arguments {
						f.Args = append(f.Args, fmt.Sprintf("%s:%d", a.Name, a.Pos.Offset))
					}
					for _, a := range info.TypeArgs {
						f.TypeArgs = append(f.TypeArgs, a.String())
					}
					item.Facts = append(item.Facts, f)
				}
				sort.Slice(item.Facts, func(i, j int) bool {
					a, b := item.Facts[i], item.Facts[j]
					if a.Offset != b.Offset {
						return a.Offset < b.Offset
					}
					return a.Kind+a.Text+a.Type < b.Kind+b.Text+b.Type
				})
			}
			if err := encoder.Encode(item); err != nil {
				panic(err)
			}
		}
	}
}
