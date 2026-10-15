package mcp

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

//go:embed cheatsheet.md
var cheatsheet string

type promptArgument struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Required    bool   `json:"required,omitempty"`
}

type prompt struct {
	Name        string           `json:"name"`
	Description string           `json:"description"`
	Arguments   []promptArgument `json:"arguments,omitempty"`
	build       func(args map[string]string) (string, error)
}

var prompts = []prompt{
	{
		Name:        "manuscript_cheatsheet",
		Description: "Compact language reference: syntax, types, control flow, errors, tests, and the check-and-fix workflow. Read before writing Manuscript.",
		build:       func(map[string]string) (string, error) { return cheatsheet, nil },
	},
	{
		Name:        "stdlib_cheatsheet",
		Description: "Index of every standard-library module and its exported names, generated from the bundled declarations. Use std_lookup for signatures.",
		build:       func(map[string]string) (string, error) { return stdlibIndex(), nil },
	},
	{
		Name:        "write_idiomatic_manuscript",
		Description: "Frame a coding task: write Manuscript for a goal, verified with the manuscript tools.",
		Arguments:   []promptArgument{{Name: "task", Description: "What the program or change should do.", Required: true}},
		build: func(args map[string]string) (string, error) {
			task := strings.TrimSpace(args["task"])
			if task == "" {
				return "", fmt.Errorf("task is required")
			}
			return "Write Manuscript for this task:\n\n" + task + "\n\n" +
				"Method: read the manuscript_cheatsheet prompt if you have not. Use std_lookup for every standard API before calling it. " +
				"Handle expected failures with Result and try, keep match flat, and prefer small functions. " +
				"After each edit run check, then fmt, then lint; add test blocks and run test on the project's ms.toml. " +
				"Finish only when check and test report no diagnostics or failures, and say which you ran.", nil
		},
	},
	{
		Name:        "fix_diagnostic",
		Description: "Repair a Manuscript diagnostic: apply the fix its message names, then re-check.",
		Arguments: []promptArgument{
			{Name: "diagnostic", Description: "The diagnostic JSON or message from check or lint.", Required: true},
			{Name: "source", Description: "The source the diagnostic refers to, if not already in context."},
		},
		build: func(args map[string]string) (string, error) {
			diagnostic := strings.TrimSpace(args["diagnostic"])
			if diagnostic == "" {
				return "", fmt.Errorf("diagnostic is required")
			}
			text := "Fix this Manuscript diagnostic:\n\n" + diagnostic + "\n\n"
			if source := strings.TrimSpace(args["source"]); source != "" {
				text += "Source:\n\n```manuscript\n" + source + "\n```\n\n"
			}
			return text + "Diagnostic messages read '<cause>; <fix>': apply the named fix at the reported position rather than restructuring. " +
				"If it names a standard API, confirm the signature with std_lookup. Re-run check until the diagnostics are empty, then run test if the project has tests.", nil
		},
	},
}

func listPrompts() []prompt { return prompts }

func getPrompt(params json.RawMessage) (any, *rpcError) {
	var p struct {
		Name      string            `json:"name"`
		Arguments map[string]string `json:"arguments"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, &rpcError{codeInvalidParams, "invalid prompts/get parameters: " + err.Error()}
	}
	for _, candidate := range prompts {
		if candidate.Name != p.Name {
			continue
		}
		text, err := candidate.build(p.Arguments)
		if err != nil {
			return nil, &rpcError{codeInvalidParams, err.Error()}
		}
		return map[string]any{
			"description": candidate.Description,
			"messages":    []map[string]any{{"role": "user", "content": map[string]any{"type": "text", "text": text}}},
		}, nil
	}
	return nil, &rpcError{codeInvalidParams, "unknown prompt " + p.Name}
}

// stdlibIndex lists each module's exported names, generated from the same
// declarations the checker uses so it cannot drift from the library.
func stdlibIndex() string {
	var b strings.Builder
	b.WriteString("# Standard library index\n\nImport with `import Name from \"@std/<module>.ms\"`. Names under `prelude` need no import. Use std_lookup for signatures and docs.\n")
	for _, module := range checker.StandardLibrary() {
		fmt.Fprintf(&b, "\n## %s\n", module.Path)
		names := make([]string, 0, len(module.Declarations))
		for _, d := range module.Declarations {
			names = append(names, d.Name+" ("+d.Kind+")")
		}
		b.WriteString(strings.Join(names, ", "))
		b.WriteString("\n")
	}
	return b.String()
}
