package guide

import (
	"fmt"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// Every page is bounded so an agent can read it without flooding its context:
// the index and module pages list one line per item, a declaration page lists
// its members as signatures, and only a single member shows its full doc.
const (
	pageBudget  = 3500
	lineWidth   = 150
	moduleLines = 45
)

func shortName(path string) string {
	return strings.TrimSuffix(strings.TrimPrefix(path, "@std/"), ".ms")
}

// bare drops a generic parameter list: group_by[K: Hashable] becomes group_by.
func bare(name string) string {
	if i := strings.IndexByte(name, '['); i >= 0 {
		return name[:i]
	}
	return name
}

// stdPath is the path that `ms std` accepts for a declaration or member.
func stdPath(modulePath, name string) string { return shortName(modulePath) + "." + bare(name) }

// oneLine collapses a signature to a single line of at most limit runes.
func oneLine(text string, limit int) string {
	text = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(strings.Join(strings.Fields(text), " ")), ":"))
	if r := []rune(text); len(r) > limit {
		return string(r[:limit-1]) + "…"
	}
	return text
}

// firstLine returns the first non-empty line of a doc, cut at a word boundary.
func firstLine(doc string, limit int) string {
	for _, line := range strings.Split(doc, "\n") {
		if line = strings.Join(strings.Fields(line), " "); line != "" {
			if r := []rune(line); len(r) > limit {
				cut := strings.LastIndex(string(r[:limit-1]), " ")
				if cut < limit/2 {
					cut = limit - 1
				}
				return string(r[:cut]) + "…"
			}
			return line
		}
	}
	return ""
}

// capDoc limits a full doc to limit bytes without cutting a rune.
func capDoc(doc string, limit int) string {
	doc = strings.TrimSpace(doc)
	if len(doc) <= limit {
		return doc
	}
	r := []rune(doc)
	for len(string(r)) > limit {
		r = r[:len(r)-20]
	}
	return string(r) + "…"
}

func modules() []checker.APIModule {
	all := checker.StandardLibrary()
	sort.SliceStable(all, func(i, j int) bool {
		if (all[i].Path == "prelude") != (all[j].Path == "prelude") {
			return all[i].Path == "prelude"
		}
		return all[i].Path < all[j].Path
	})
	return all
}

// ModuleNames returns the short names of every standard module, prelude first.
func ModuleNames() []string {
	var names []string
	for _, m := range modules() {
		names = append(names, shortName(m.Path))
	}
	return names
}

// Index lists each module with a few of its names.
func Index() string {
	var b strings.Builder
	b.WriteString("Standard library modules (prelude needs no import).\n`ms std <module>` lists one, `ms std <module>.<Name>` shows a declaration, `ms std search <words>` searches.\n\n")
	for _, m := range modules() {
		head := fmt.Sprintf("%-12s", shortName(m.Path))
		line := head
		shown := 0
		for _, d := range m.Declarations {
			next := line + " " + d.Name + ","
			if len(next) > 84 && shown > 0 {
				break
			}
			line, shown = next, shown+1
		}
		line = strings.TrimSuffix(line, ",")
		if rest := len(m.Declarations) - shown; rest > 0 {
			line += fmt.Sprintf(" +%d", rest)
		}
		b.WriteString(line + "\n")
	}
	return b.String()
}

// Page renders `ms std <path>`: a module ("json"), a declaration ("json.parse"),
// or one member ("prelude.List.sorted"). A leading "@std/" and ".ms" are accepted.
func Page(path string) (string, error) {
	parts := splitPath(path)
	module := findModule(parts[0])
	if module == nil {
		return "", fmt.Errorf("no standard module %q; modules: %s", parts[0], strings.Join(ModuleNames(), ", "))
	}
	if len(parts) == 1 {
		return modulePage(*module), nil
	}
	var found *checker.APIDeclaration
	for i := range module.Declarations {
		if bare(module.Declarations[i].Name) == parts[1] {
			found = &module.Declarations[i]
			break
		}
	}
	if found == nil {
		return "", fmt.Errorf("%s has no declaration %q; see `ms std %s` (or `ms std search %s`)", shortName(module.Path), parts[1], shortName(module.Path), parts[1])
	}
	if len(parts) == 2 {
		return declarationPage(*module, *found), nil
	}
	return memberPage(*module, *found, parts[2])
}

func splitPath(path string) []string {
	path = strings.TrimSpace(path)
	if strings.HasPrefix(path, "@std/") {
		path = strings.TrimPrefix(path, "@std/")
		if name, rest, found := strings.Cut(path, ".ms"); found {
			path = name + rest
		}
	}
	return strings.SplitN(path, ".", 3)
}

func findModule(name string) *checker.APIModule {
	all := modules()
	for i := range all {
		if shortName(all[i].Path) == name {
			return &all[i]
		}
	}
	return nil
}

func importLine(m checker.APIModule) string {
	if m.Path == "prelude" {
		return "available in every module; no import"
	}
	return fmt.Sprintf("import Name from %q", m.Path)
}

func modulePage(m checker.APIModule) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s: %s\n", m.Path, importLine(m))
	for i, d := range m.Declarations {
		if i == moduleLines {
			fmt.Fprintf(&b, "... %d more; narrow with `ms std search <words>`\n", len(m.Declarations)-moduleLines)
			break
		}
		if d.Kind == "fn" && d.Declaration != "" {
			b.WriteString(oneLine(d.Declaration, lineWidth) + "\n")
			continue
		}
		fmt.Fprintf(&b, "%s %s", d.Kind, bare(d.Name))
		if doc := firstLine(d.Doc, 90); doc != "" {
			b.WriteString(" # " + doc)
		}
		b.WriteString("\n")
	}
	b.WriteString("Details: ms std " + shortName(m.Path) + ".<Name>\n")
	return clipText(b.String(), pageBudget)
}

func declarationPage(m checker.APIModule, d checker.APIDeclaration) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s %s (%s)\n", d.Kind, d.Name, m.Path)
	if m.Path != "prelude" {
		fmt.Fprintf(&b, "import %s from %q\n", bare(d.Name), m.Path)
	}
	if doc := capDoc(d.Doc, 500); doc != "" {
		b.WriteString(doc + "\n")
	}
	if len(d.Members) == 0 {
		if d.Declaration != "" {
			b.WriteString(clipLines(strings.TrimRight(d.Declaration, "\n"), 12) + "\n")
		}
		return clipText(b.String(), pageBudget)
	}
	fmt.Fprintf(&b, "members (%d):\n", len(d.Members))
	for i, member := range d.Members {
		line := "  " + oneLine(member.Signature, lineWidth) + "\n"
		if b.Len()+len(line) > pageBudget-160 {
			fmt.Fprintf(&b, "  ... %d more; use `ms std %s.%s.<member>`\n", len(d.Members)-i, shortName(m.Path), bare(d.Name))
			break
		}
		b.WriteString(line)
	}
	fmt.Fprintf(&b, "Details: ms std %s.%s.<member>\n", shortName(m.Path), bare(d.Name))
	return b.String()
}

func memberPage(m checker.APIModule, d checker.APIDeclaration, name string) (string, error) {
	var b strings.Builder
	count := 0
	for _, member := range d.Members {
		if bare(member.Name) != name {
			continue
		}
		if count++; count > 3 {
			break
		}
		fmt.Fprintf(&b, "%s.%s (%s)\n%s\n", d.Name, member.Name, m.Path, clipLines(strings.TrimRight(member.Signature, "\n"), 6))
		if doc := capDoc(member.Doc, 800); doc != "" {
			b.WriteString(doc + "\n")
		}
	}
	if count == 0 {
		return "", fmt.Errorf("%s has no member %q; see `ms std %s.%s`", d.Name, name, shortName(m.Path), bare(d.Name))
	}
	return clipText(b.String(), pageBudget), nil
}

func clipLines(text string, limit int) string {
	lines := strings.Split(text, "\n")
	if len(lines) <= limit {
		return text
	}
	return strings.Join(append(lines[:limit], "..."), "\n")
}
