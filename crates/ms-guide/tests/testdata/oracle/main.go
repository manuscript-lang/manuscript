// Command oracle prints the Go guide's answers for the Rust differential tests
// in crates/ms-guide/tests. Each stdin line is one request:
//
//	index
//	cheatsheet
//	page <path>
//	search <limit> <query>
//	moddoc <file.ms>
//	site
//
// Every answer is framed as "\x00<request>\n<output>\n".
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling/docgen"
	"github.com/manuscript-lang/manuscript/pkg/tooling/guide"
)

func main() {
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 1<<20), 1<<20)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	for in.Scan() {
		line := in.Text()
		command, rest, _ := strings.Cut(line, " ")
		fmt.Fprintf(out, "\x00%s\n", line)
		switch command {
		case "index":
			fmt.Fprint(out, guide.Index())
		case "cheatsheet":
			fmt.Fprint(out, guide.Cheatsheet())
		case "page":
			text, err := guide.Page(rest)
			if err != nil {
				fmt.Fprint(out, "error: "+err.Error())
			} else {
				fmt.Fprint(out, text)
			}
		case "site":
			files, err := docgen.SiteFiles()
			if err != nil {
				fmt.Fprint(out, "error: "+err.Error())
				break
			}
			names := make([]string, 0, len(files))
			for name := range files {
				names = append(names, name)
			}
			sort.Strings(names)
			for _, name := range names {
				fmt.Fprintf(out, "%s %d\n%s", name, len(files[name]), files[name])
			}
		case "moddoc":
			fmt.Fprint(out, moduleDocumentation(rest))
		case "search":
			limit, query, _ := strings.Cut(rest, " ")
			n, _ := strconv.Atoi(limit)
			matches := guide.Search(query, n)
			data, _ := json.MarshalIndent(matches, "", "  ")
			fmt.Fprintf(out, "%s\n%s", data, guide.FormatMatches(query, matches))
		}
		fmt.Fprintln(out)
	}
}

// moduleDocumentation renders the exports of one checked source file as the
// JSON snapshot followed by each module's portable Markdown.
func moduleDocumentation(path string) string {
	source, err := os.ReadFile(path)
	if err != nil {
		return "error: " + err.Error()
	}
	module, err := parser.Parse(path, string(source))
	if err != nil {
		return "error: " + err.Error()
	}
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		return fmt.Sprintf("error: %v", program.Diagnostics)
	}
	modules := checker.ModuleDocumentation(program)
	data, err := docgen.JSON(modules)
	if err != nil {
		return "error: " + err.Error()
	}
	var b strings.Builder
	b.Write(data)
	for _, m := range modules {
		b.WriteString(docgen.RenderModule(m))
	}
	return b.String()
}
