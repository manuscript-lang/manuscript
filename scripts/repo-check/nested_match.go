package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const nestedMatchAllowance = "manuscript:allow-nested-match "

var manuscriptFences = regexp.MustCompile("(?m)^```(?:manuscript|ms|text)\\r?\\n([\\s\\S]*?)^```")

// Inspect tracked source, snippets and examples, including Go test strings.
// Deliberate syntax/semantic regressions may opt out at one test literal or
// fixture with a reason; documentation and implementation cannot opt out.
func checkNestedMatches() error {
	paths, err := exec.Command("git", "ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate", "-z").Output()
	if err != nil {
		return fmt.Errorf("list source for nested-match check: %w", err)
	}
	var issues []string
	for _, path := range strings.Split(string(paths), "\x00") {
		if path == "" || strings.HasPrefix(path, "vendor/") || strings.HasPrefix(path, "website/themes/") {
			continue
		}
		switch filepath.Ext(path) {
		case ".ms", ".go", ".md":
		default:
			continue
		}
		source, err := os.ReadFile(path)
		if os.IsNotExist(err) {
			continue // A tracked file may have been removed in this working tree.
		}
		if err != nil {
			return err
		}
		found, err := nestedMatchIssues(path, string(source))
		if err != nil {
			return err
		}
		issues = append(issues, found...)
	}
	if len(issues) > 0 {
		return fmt.Errorf("nested match anti-pattern:\n- %s", strings.Join(issues, "\n- "))
	}
	return nil
}

func nestedMatchIssues(path, source string) ([]string, error) {
	var issues []string
	inspect := func(code string, line int, allowed, physicalLines bool) {
		module, _ := frontend.Parse(path, code, true)
		// Reference fragments may consist solely of executable statements.
		wrapped := module == nil || len(module.Declarations) == 0
		if wrapped {
			lines := strings.Split(code, "\n")
			indent := len(code)
			for _, text := range lines {
				if strings.TrimSpace(text) != "" {
					count := len(text) - len(strings.TrimLeft(text, " \t"))
					if count < indent {
						indent = count
					}
				}
			}
			for index, text := range lines {
				if len(text) >= indent {
					lines[index] = text[indent:]
				}
			}
			code = strings.Join(lines, "\n")
			module, _ = frontend.Parse(path, "fn fragment() Unit:\n    "+strings.ReplaceAll(code, "\n", "\n    "), true)
		}
		for _, match := range syntax.NestedMatches(module) {
			lines := strings.Split(code, "\n")
			previous := match.Pos.Line - 2
			if wrapped {
				previous--
			}
			fixtureAllowance := false
			if strings.HasPrefix(path, "tests/") && filepath.Ext(path) == ".ms" && previous >= 0 && previous < len(lines) {
				comment := strings.TrimSpace(lines[previous])
				fixtureAllowance = strings.HasPrefix(comment, "# "+nestedMatchAllowance) && strings.TrimSpace(strings.TrimPrefix(comment, "# "+nestedMatchAllowance)) != ""
			}
			if allowed || fixtureAllowance {
				continue
			}
			at := line + match.Pos.Line - 1
			if wrapped {
				at--
			}
			if !physicalLines {
				at = line
			}
			issues = append(issues, fmt.Sprintf("%s:%d: flatten the outer match with an early exit, compatible try, or a small helper", path, at))
		}
	}
	switch filepath.Ext(path) {
	case ".ms":
		inspect(source, 1, false, true)
	case ".md":
		for _, fence := range manuscriptFences.FindAllStringSubmatchIndex(source, -1) {
			inspect(source[fence[2]:fence[3]], 1+strings.Count(source[:fence[2]], "\n"), false, true)
		}
	case ".go":
		positions := token.NewFileSet()
		file, err := parser.ParseFile(positions, path, source, parser.ParseComments)
		if err != nil {
			return nil, err
		}
		allowances := map[int]bool{}
		if strings.HasSuffix(path, "_test.go") {
			for _, group := range file.Comments {
				for _, comment := range group.List {
					text := strings.TrimSpace(strings.TrimPrefix(comment.Text, "//"))
					if strings.HasPrefix(text, nestedMatchAllowance) && strings.TrimSpace(strings.TrimPrefix(text, nestedMatchAllowance)) != "" {
						allowances[positions.Position(comment.End()).Line+1] = true
					}
				}
			}
		}
		ast.Inspect(file, func(node ast.Node) bool {
			expression, ok := node.(ast.Expr)
			if !ok {
				return true
			}
			code, ok := stringSnippet(expression)
			if !ok {
				return true
			}
			if strings.Contains(code, "match") {
				line := positions.Position(expression.Pos()).Line
				raw, literal := expression.(*ast.BasicLit)
				inspect(code, line, allowances[line], literal && strings.HasPrefix(raw.Value, "`"))
			}
			return false
		})
	}
	return issues, nil
}

func stringSnippet(expression ast.Expr) (string, bool) {
	switch value := expression.(type) {
	case *ast.BasicLit:
		if value.Kind == token.STRING {
			text, err := strconv.Unquote(value.Value)
			return text, err == nil
		}
	case *ast.BinaryExpr:
		if value.Op == token.ADD {
			left, a := stringSnippet(value.X)
			right, b := stringSnippet(value.Y)
			return left + right, a && b
		}
	case *ast.ParenExpr:
		return stringSnippet(value.X)
	}
	return "", false
}
