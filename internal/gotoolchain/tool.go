// Package gotoolchain runs the Go compiler, assembler, and linker copied from
// the pinned SDK (see scripts/mkgotoolchain), so native builds need no go
// command or separate tool executables.
//
// The copied tools keep process-wide state: flags, exit calls, and logging.
// Each invocation therefore runs in a fresh child process of the current
// executable, which dispatches to the tool during package initialization.
package gotoolchain

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/asm"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/compile"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/link"
)

//go:embed VERSION
var version string

// Version reports the Go release the copied tools come from, such as go1.25.1.
// Package archives and SDK sources must come from the same release.
func Version() string { return strings.TrimSpace(version) }

// toolVariable selects a copied tool in a child process of this executable.
const toolVariable = "MANUSCRIPT_GO_TOOL"

var tools = map[string]func(){"compile": compile.Main, "link": link.Main, "asm": asm.Main}

func init() {
	name, ok := os.LookupEnv(toolVariable)
	if !ok {
		return
	}
	main := tools[name]
	if main == nil {
		fmt.Fprintf(os.Stderr, "unknown Go tool %q\n", name)
		os.Exit(2)
	}
	main()
	os.Exit(0)
}

// run executes a copied tool in dir with the given environment and returns
// its combined output on failure.
func run(tool, dir string, environment []string, arguments ...string) error {
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("locate executable for Go %s: %w", tool, err)
	}
	command := exec.Command(executable, arguments...)
	command.Dir = dir
	command.Env = append(append([]string{}, environment...), toolVariable+"="+tool)
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = &output
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s: %w\n%s", tool, err, bytes.TrimSpace(output.Bytes()))
	}
	return nil
}
