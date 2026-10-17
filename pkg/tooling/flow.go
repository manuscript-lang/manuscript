package tooling

import (
	"fmt"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// flowBuilder turns one module's callable bodies into ordered significant
// steps: calls, branches, loops, match arms, try sites, cleanup scopes, and
// exits. Bindings and arithmetic are elided. Labels are the source lines
// themselves, so they are exact and need no wording of their own.
type flowBuilder struct {
	module *syntax.Module
	lines  []string
	sites  map[string]CallSite
	keys   map[string]string
}

func (b *flowBuilder) source(pos syntax.Position) string {
	if pos.Line < 1 || pos.Line > len(b.lines) {
		return ""
	}
	text := strings.TrimSpace(strings.TrimRight(b.lines[pos.Line-1], "\r"))
	return strings.TrimSpace(strings.TrimSuffix(text, ":"))
}

// at records where a step came from so a diff can mark it.
func (b *flowBuilder) at(n *Node, pos syntax.Position) *Node {
	n.File, n.Line = b.module.File, pos.Line
	return n
}

func (b *flowBuilder) body(statements []*syntax.Statement) []*Node {
	var out []*Node
	for _, s := range statements {
		out = append(out, b.statement(s)...)
	}
	return out
}

func (b *flowBuilder) statement(s *syntax.Statement) []*Node {
	switch s.Kind {
	case syntax.KindIf, syntax.KindWhile, syntax.KindFor:
		node := b.at(&Node{Kind: "branch", Label: b.source(s.Pos)}, s.Pos)
		node.Children = append(b.events(s.Value), b.body(s.Body)...)
		if len(s.Else) > 0 {
			node.Children = append(node.Children, &Node{Kind: "branch", Label: "else", Children: b.body(s.Else)})
		}
		return []*Node{node}
	case syntax.KindWith:
		node := b.at(&Node{Kind: "with", Label: b.source(s.Pos) + "  [closed on exit]"}, s.Pos)
		node.Children = append(b.events(s.Value), b.body(s.Body)...)
		return []*Node{node}
	case syntax.KindBreak, syntax.KindContinue:
		return []*Node{b.at(&Node{Kind: "exit", Label: s.Kind}, s.Pos)}
	}
	var out []*Node
	if s.Value != nil && s.Value.Kind == syntax.KindMatch {
		out = append(b.events(s.Target), b.events(s.Value.Left)...)
		out = append(out, b.matchNode(s))
	} else {
		out = append(b.events(s.Target), b.events(s.Value)...)
	}
	if s.Kind == syntax.KindReturn {
		out = append(out, b.at(&Node{Kind: "exit", Label: b.source(s.Pos)}, s.Pos))
	}
	return out
}

func (b *flowBuilder) matchNode(s *syntax.Statement) *Node {
	node := b.at(&Node{Kind: "match", Label: b.source(s.Pos)}, s.Pos)
	for _, arm := range s.Value.Arms {
		child := b.at(&Node{Kind: "arm", Label: b.source(arm.Pos)}, arm.Pos)
		for _, step := range append(b.events(arm.Value), b.body(arm.Body)...) {
			if step.Kind == "exit" && strings.HasSuffix(child.Label, step.Label) {
				continue
			}
			child.Children = append(child.Children, step)
		}
		node.Children = append(node.Children, child)
	}
	return node
}

// events lists the calls and try markers inside one expression, outermost first.
func (b *flowBuilder) events(e *syntax.Expression) []*Node {
	if e == nil {
		return nil
	}
	var out []*Node
	pendingTry := false
	syntax.Visitor{Expression: func(x *syntax.Expression) {
		if x.Kind == syntax.KindUnary && x.Text == "try" {
			pendingTry = true
			return
		}
		if x.Kind != syntax.KindCall {
			return
		}
		node := b.call(x)
		if node == nil {
			return
		}
		b.at(node, x.Pos)
		if pendingTry {
			node.Label, node.Kind, pendingTry = "try "+node.Label, "try", false
		}
		out = append(out, node)
	}}.Callable(nil, []*syntax.Statement{{Kind: syntax.KindCall, Value: e}})
	if pendingTry {
		out = append(out, b.at(&Node{Kind: "try", Label: "try"}, e.Pos))
	}
	return out
}

func (b *flowBuilder) call(e *syntax.Expression) *Node {
	site, ok := b.sites[fmt.Sprintf("%s#call#%d", b.module.File, e.Pos.Offset)]
	if !ok {
		return nil
	}
	if site.Kind == "construct" {
		return nil
	}
	if key, ok := b.keys[site.Target]; ok {
		return &Node{Kind: "call", Label: "call " + keyName(key), Ref: key}
	}
	return &Node{Kind: "native", Label: "native " + site.Target}
}

func keyName(key string) string {
	parts := strings.SplitN(key, "#", 3)
	return parts[len(parts)-1]
}

// flowView prints one callable's steps, expanding project calls to depth levels.
func flowView(facts Facts, view, entity string, depth int) (*Node, error) {
	if entity == "" {
		return nil, fmt.Errorf("%s needs --entity; name a function or method (ms review lists the public surface)", view)
	}
	f, err := findEntity(facts, entity)
	if err != nil {
		return nil, err
	}
	steps := facts.flows[f.Key]
	e := &flowExpander{facts: facts, depth: depth}
	root := &Node{Label: strings.ToUpper(view) + " VIEW"}
	body := e.expand(steps, 1, map[string]bool{f.Key: true})
	if view == "scope" {
		body = pruneScopes(body, false)
	}
	header := &Node{Label: fmt.Sprintf("%s  [%s] %s:%d", f.Name, f.Kind, f.File, f.Line), Ref: f.Key, Children: body}
	if len(body) == 0 {
		header.Children = []*Node{{Label: "none"}}
	}
	root.Children = []*Node{header}
	if e.skipped > 0 {
		root.Children = append(root.Children, &Node{Label: fmt.Sprintf("+%d more (output capped at %d nodes)", e.skipped, nodeCap)})
	}
	return root, nil
}

type flowExpander struct {
	facts   Facts
	depth   int
	count   int
	skipped int
}

func (e *flowExpander) expand(nodes []*Node, level int, path map[string]bool) []*Node {
	var out []*Node
	for _, n := range nodes {
		if e.count >= nodeCap {
			e.skipped++
			continue
		}
		e.count++
		copied := &Node{Label: n.Label, Kind: n.Kind, Ref: n.Ref, File: n.File, Line: n.Line}
		copied.Children = e.expand(n.Children, level, path)
		if n.Ref != "" && level < e.depth {
			if path[n.Ref] {
				copied.Children = append(copied.Children, &Node{Label: "(cycle)"})
			} else {
				path[n.Ref] = true
				copied.Children = append(copied.Children, e.expand(e.facts.flows[n.Ref], level+1, path)...)
				delete(path, n.Ref)
			}
		}
		out = append(out, copied)
	}
	return out
}

// pruneScopes keeps cleanup scopes and, inside them, the exits that run the
// cleanup: return, break, continue, and try sites.
func pruneScopes(nodes []*Node, inScope bool) []*Node {
	var out []*Node
	for _, n := range nodes {
		kids := pruneScopes(n.Children, inScope || n.Kind == "with")
		exit := inScope && (n.Kind == "exit" || n.Kind == "try")
		if n.Kind == "with" || exit || len(kids) > 0 {
			out = append(out, &Node{Label: n.Label, Kind: n.Kind, File: n.File, Line: n.Line, Children: kids})
		}
	}
	return out
}
