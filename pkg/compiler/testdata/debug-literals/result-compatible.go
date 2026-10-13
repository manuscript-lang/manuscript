// Compile with bundled Go: go build -mod=vendor -o /tmp/result-compatible
// pkg/compiler/testdata/debug-literals/result-compatible.go
package main

import "github.com/manuscript-lang/manuscript/pkg/compiler"

var originalLayout = compiler.Result{"", nil, "", nil, "", ""}

func main() { _ = originalLayout }
