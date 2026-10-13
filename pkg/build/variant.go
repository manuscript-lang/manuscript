package build

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"strings"
	"sync"
)

// leanRuntimeTag selects the native runtime without network, TLS, HTTP,
// WebSocket, system, and process-control implementations. Those depend on
// net/http, crypto/tls, and gopsutil, which roughly double the linker's input;
// omitting them makes relinking an edited program substantially faster.
const leanRuntimeTag = "ms_lean"

// Standard modules whose values or functions reach full-runtime code. Values of
// their types can only originate from these modules, so a program that imports
// none of them, directly or through bundled standard sources, never calls it.
var fullRuntimeModules = map[string]bool{
	"@std/http.ms":      true,
	"@std/net.ms":       true,
	"@std/process.ms":   true,
	"@std/system.ms":    true,
	"@std/tls.ms":       true,
	"@std/websocket.ms": true,
}

var standardImports = sync.OnceValue(func() map[string][]string {
	imports := map[string][]string{}
	for _, module := range checker.StandardModules() {
		for _, item := range module.Imports {
			imports[module.File] = append(imports[module.File], item.Path)
		}
	}
	return imports
})

// runtimeTags returns the Go build tags selecting the runtime for program.
// It follows imports through native and bundled standard modules alike.
func runtimeTags(program *checker.Program) []string {
	if program == nil {
		return nil
	}
	seen := map[string]bool{}
	var pending []string
	for _, module := range program.Modules {
		for _, item := range module.Imports {
			pending = append(pending, item.Path)
		}
	}
	for len(pending) > 0 {
		path := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		if seen[path] || !strings.HasPrefix(path, "@std/") {
			continue
		}
		if fullRuntimeModules[path] {
			return nil
		}
		seen[path] = true
		pending = append(pending, standardImports()[path]...)
	}
	return []string{leanRuntimeTag}
}
