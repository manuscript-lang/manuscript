package cli

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// commandDiagnostic preserves the existing diagnostic shape while allowing
// command-specific failures (such as formatting drift) to have stable codes.
type commandDiagnostic struct {
	Code     string                `json:"code"`
	Phase    string                `json:"phase,omitempty"`
	Message  string                `json:"message"`
	Position syntax.Position       `json:"position"`
	End      *syntax.Position      `json:"end,omitempty"`
	Fix      *syntax.DiagnosticFix `json:"fix,omitempty"`
}

func sourceDiagnostic(issue syntax.Diagnostic) commandDiagnostic {
	return commandDiagnostic{issue.Code(), issue.Phase, issue.Message, issue.Position, issue.End, issue.Fix}
}

func emitJSON(value any, status int) int {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(value); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return status
}
