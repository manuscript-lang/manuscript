package tooling

import (
	"fmt"
	"sort"
	"strings"
)

// Node is one line of a view: a label and what hangs under it.
type Node struct {
	Label    string
	Children []*Node
	// Kind and Ref describe flow steps: Kind is call, native, try, with, branch,
	// match, arm, or exit; Ref is the callee's entity key for project calls.
	Kind, Ref string
}

// Views names the diagram views, in help order.
var Views = []string{"calls", "effects", "errors", "modules", "flow", "scope"}

// nodeCap bounds one view so a large project stays readable and the output size predictable.
const nodeCap = 200

// BuildView builds one question's tree from the fact model. With entity empty
// the roots are chosen by the view; otherwise the entity is the single root.
func BuildView(facts Facts, view, entity string, depth int) (*Node, error) {
	if depth <= 0 {
		depth = 3
		if view == "flow" || view == "scope" {
			depth = 1
		}
	}
	if view == "modules" {
		return modulesView(facts, entity)
	}
	if view == "flow" || view == "scope" {
		return flowView(facts, view, entity, depth)
	}
	roots, err := viewRoots(facts, view, entity)
	if err != nil {
		return nil, err
	}
	b := &viewBuilder{facts: facts, view: view, depth: depth}
	root := &Node{Label: strings.ToUpper(view) + " VIEW"}
	for _, fact := range roots {
		root.Children = append(root.Children, b.expand(fact, 0, map[string]bool{}))
	}
	if len(roots) == 0 {
		root.Children = append(root.Children, &Node{Label: "none"})
	}
	if b.skipped > 0 {
		root.Children = append(root.Children, &Node{Label: fmt.Sprintf("+%d more (output capped at %d nodes)", b.skipped, nodeCap)})
	}
	return root, nil
}

type viewBuilder struct {
	facts   Facts
	view    string
	depth   int
	count   int
	skipped int
}

func (b *viewBuilder) label(f *Fact) string {
	switch b.view {
	case "effects":
		return fmt.Sprintf("%s  effects: %s", f.Name, effectList(f.Effects))
	case "errors":
		return fmt.Sprintf("%s  error: %s, try sites: %d", f.Name, orNone(f.Error), f.Tries)
	}
	return fmt.Sprintf("%s  [%s] %s:%d", f.Name, f.Kind, f.File, f.Line)
}

func (b *viewBuilder) expand(f *Fact, level int, path map[string]bool) *Node {
	node := &Node{Label: b.label(f)}
	b.count++
	if level >= b.depth {
		return node
	}
	path[f.Key] = true
	defer delete(path, f.Key)
	for _, key := range f.Calls {
		callee := b.facts.Entities[key]
		if callee == nil || !b.relevant(callee) {
			continue
		}
		if path[key] {
			node.Children = append(node.Children, &Node{Label: callee.Name + "  (cycle)"})
			continue
		}
		if b.count >= nodeCap {
			b.skipped++
			continue
		}
		node.Children = append(node.Children, b.expand(callee, level+1, path))
	}
	if b.view == "effects" || b.view == "calls" {
		for _, target := range f.External {
			if b.view == "effects" && len(f.Effects) == 0 {
				break
			}
			if b.count >= nodeCap {
				b.skipped++
				continue
			}
			b.count++
			node.Children = append(node.Children, &Node{Label: target})
		}
	}
	return node
}

// relevant drops callees that cannot answer the view's question.
func (b *viewBuilder) relevant(f *Fact) bool {
	switch b.view {
	case "effects":
		return len(f.Effects) > 0
	case "errors":
		return f.Error != "" || f.Tries > 0
	}
	return true
}

func viewRoots(facts Facts, view, entity string) ([]*Fact, error) {
	if entity != "" {
		f, err := findEntity(facts, entity)
		if err != nil {
			return nil, err
		}
		return []*Fact{f}, nil
	}
	b := &viewBuilder{view: view}
	called := map[string]bool{}
	for _, f := range facts.Entities {
		if !b.relevant(f) {
			continue
		}
		for _, key := range f.Calls {
			if callee := facts.Entities[key]; callee != nil && b.relevant(callee) {
				called[key] = true
			}
		}
	}
	var roots []*Fact
	for _, f := range facts.Entities {
		if (f.Kind == "fn" || f.Kind == "method") && b.relevant(f) && !called[f.Key] {
			roots = append(roots, f)
		}
	}
	sort.Slice(roots, func(i, j int) bool { return roots[i].Key < roots[j].Key })
	return roots, nil
}

// findEntity resolves a name, file::name, or full key to exactly one entity.
func findEntity(facts Facts, name string) (*Fact, error) {
	var matches []*Fact
	for _, f := range facts.Entities {
		if f.Name == name || f.Key == name || f.File+"::"+f.Name == name {
			matches = append(matches, f)
		}
	}
	sort.Slice(matches, func(i, j int) bool { return matches[i].Key < matches[j].Key })
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		return nil, fmt.Errorf("no entity named %s; use a declaration name or file::name (ms review lists the public surface)", name)
	}
	var keys []string
	for _, f := range matches {
		keys = append(keys, f.File+"::"+f.Name)
	}
	return nil, fmt.Errorf("%s is ambiguous: %s; qualify it as file::name", name, strings.Join(keys, ", "))
}

func modulesView(facts Facts, entity string) (*Node, error) {
	var files []string
	for file := range facts.Imports {
		if entity == "" || file == entity {
			files = append(files, file)
		}
	}
	sort.Strings(files)
	if entity != "" && len(files) == 0 {
		return nil, fmt.Errorf("no module named %s; use a project-relative path such as src/main.ms", entity)
	}
	root := &Node{Label: "MODULES VIEW"}
	for _, file := range files {
		node := &Node{Label: file}
		for _, path := range facts.Imports[file] {
			node.Children = append(node.Children, &Node{Label: path})
		}
		root.Children = append(root.Children, node)
	}
	if len(files) == 0 {
		root.Children = append(root.Children, &Node{Label: "none"})
	}
	return root, nil
}

// ASCII prints the tree with fixed connectors.
func (n *Node) ASCII() string {
	var b strings.Builder
	b.WriteString(n.Label + "\n")
	writeChildren(&b, n.Children, "")
	return b.String()
}

func writeChildren(b *strings.Builder, children []*Node, prefix string) {
	for i, child := range children {
		last := i == len(children)-1
		connector, next := "|- ", "|  "
		if last {
			connector, next = "`- ", "   "
		}
		b.WriteString(prefix + connector + child.Label + "\n")
		writeChildren(b, child.Children, prefix+next)
	}
}

// Mermaid prints the same tree as a flowchart; node names are pre-order numbers.
func (n *Node) Mermaid() string {
	var b strings.Builder
	b.WriteString("flowchart TD\n")
	count := 0
	var walk func(node *Node) string
	walk = func(node *Node) string {
		id := fmt.Sprintf("n%d", count)
		count++
		label := strings.NewReplacer("&", "&amp;", "\"", "&quot;", "<", "&lt;", ">", "&gt;").Replace(node.Label)
		fmt.Fprintf(&b, "    %s[\"%s\"]\n", id, label)
		for _, child := range node.Children {
			childID := walk(child)
			fmt.Fprintf(&b, "    %s --> %s\n", id, childID)
		}
		return id
	}
	walk(n)
	return b.String()
}
