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

// Prompts are rediscovered on every session, so each stays within about 150 tokens.
// The longer reference lives in resources, which agents read on demand.
const quickRules = `Manuscript rules:
- 4-space indent; no print (write bytes via @std/io.ms); main() -> Int is the exit status.
- let binds once, var reassigns; Optional is some(x)/none; no implicit conversions.
- Errors: Result ok(v)/error(e); try unwraps or returns. Never nest match.
- Methods only via interface + impl I for T. Tests: test "name": blocks.
- search_stdlib every std API before use; check after each edit. Full guide: manuscript://cheatsheet.`

var prompts = []prompt{
	{
		Name:        "manuscript_cheatsheet",
		Description: "Core Manuscript rules in a few lines.",
		build:       func(map[string]string) (string, error) { return quickRules, nil },
	},
	{
		Name:        "write_idiomatic_manuscript",
		Description: "Write Manuscript for a task and verify it.",
		Arguments:   []promptArgument{{Name: "task", Description: "What to build.", Required: true}},
		build: func(args map[string]string) (string, error) {
			task := strings.TrimSpace(args["task"])
			if task == "" {
				return "", fmt.Errorf("task is required")
			}
			return quickRules + "\n\nTask: " + task + "\nDone when check and test are clean.", nil
		},
	},
	{
		Name:        "fix_diagnostic",
		Description: "Fix a diagnostic, then re-check.",
		Arguments:   []promptArgument{{Name: "diagnostic", Description: "Message or JSON from check or lint.", Required: true}},
		build: func(args map[string]string) (string, error) {
			diagnostic := strings.TrimSpace(args["diagnostic"])
			if diagnostic == "" {
				return "", fmt.Errorf("diagnostic is required")
			}
			return "Diagnostic: " + diagnostic + "\nMessages read '<cause>; <fix>': apply the fix at the position, nothing more; re-run check.", nil
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
	b.WriteString("# Standard library\n\n`import Name from \"@std/<module>.ms\"`; `prelude` names need no import. search_stdlib gives signatures.\n")
	for _, module := range checker.StandardLibrary() {
		fmt.Fprintf(&b, "\n## %s\n", module.Path)
		names := make([]string, 0, len(module.Declarations))
		for _, d := range module.Declarations {
			names = append(names, d.Name)
		}
		b.WriteString(strings.Join(names, ", "))
		b.WriteString("\n")
	}
	return b.String()
}
