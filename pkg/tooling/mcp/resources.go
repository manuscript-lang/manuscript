package mcp

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

type resource struct {
	URI         string `json:"uri"`
	Name        string `json:"name"`
	Description string `json:"description"`
	MimeType    string `json:"mimeType"`
}

const (
	cheatsheetURI = "manuscript://cheatsheet"
	stdlibURI     = "manuscript://stdlib"
	stdlibPrefix  = "manuscript://stdlib/"
)

func listResources() []resource {
	out := []resource{
		{cheatsheetURI, "Manuscript cheat sheet", "Compact language reference and the check-and-fix workflow.", "text/markdown"},
		{stdlibURI, "Standard library index", "Every standard module and its exported names.", "text/markdown"},
	}
	for _, module := range checker.StandardLibrary() {
		short := moduleShortName(module.Path)
		out = append(out, resource{stdlibPrefix + short, module.Path, "Declarations and docs for " + module.Path + ".", "text/markdown"})
	}
	return out
}

func resourceTemplates() []map[string]any {
	return []map[string]any{{
		"uriTemplate": stdlibPrefix + "{module}",
		"name":        "Standard module",
		"description": "Declarations and docs for one standard module, for example manuscript://stdlib/json.",
		"mimeType":    "text/markdown",
	}}
}

func moduleShortName(path string) string {
	return strings.TrimSuffix(strings.TrimPrefix(path, "@std/"), ".ms")
}

func readResource(params json.RawMessage) (any, *rpcError) {
	var p struct {
		URI string `json:"uri"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, &rpcError{codeInvalidParams, "invalid resources/read parameters: " + err.Error()}
	}
	text, ok := resourceText(p.URI)
	if !ok {
		return nil, &rpcError{-32002, "resource not found: " + p.URI}
	}
	return map[string]any{"contents": []map[string]any{{"uri": p.URI, "mimeType": "text/markdown", "text": text}}}, nil
}

func resourceText(uri string) (string, bool) {
	switch {
	case uri == cheatsheetURI:
		return cheatsheet, true
	case uri == stdlibURI:
		return stdlibIndex(), true
	case strings.HasPrefix(uri, stdlibPrefix):
		name := strings.TrimPrefix(uri, stdlibPrefix)
		for _, module := range checker.StandardLibrary() {
			if moduleShortName(module.Path) == name {
				return renderModule(module), true
			}
		}
	}
	return "", false
}

// renderModule writes one module's declarations and documented members as Markdown.
func renderModule(module checker.APIModule) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", module.Path)
	for _, d := range module.Declarations {
		fmt.Fprintf(&b, "## %s\n\n**%s**\n\n", d.Name, d.Kind)
		if d.Doc != "" {
			fmt.Fprintf(&b, "%s\n\n", d.Doc)
		}
		if d.Declaration != "" {
			fmt.Fprintf(&b, "```manuscript\n%s```\n\n", d.Declaration)
		}
		for _, m := range d.Members {
			if strings.TrimSpace(m.Doc) != "" {
				fmt.Fprintf(&b, "### %s.%s\n\n%s\n\n```manuscript\n%s\n```\n\n", d.Name, m.Name, m.Doc, m.Signature)
			}
		}
	}
	return b.String()
}
