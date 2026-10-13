// ms is the Manuscript command-line entry point.
package main

import (
	"github.com/manuscript-lang/manuscript/internal/cli"
	"os"
	"runtime/debug"
)

func main() {
	// One-shot commands finish in milliseconds; collecting less often while
	// loading standard declarations shortens every edit-and-run. The language
	// server and embedded debugger sessions are long-lived and keep Go's default.
	if os.Getenv("GOGC") == "" && (len(os.Args) < 2 || os.Args[1] != "lsp" && os.Args[1] != "dap" && os.Args[1] != "debug") {
		debug.SetGCPercent(400)
	}
	os.Exit(cli.Run(os.Args[1:]))
}
