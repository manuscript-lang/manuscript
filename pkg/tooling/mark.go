package tooling

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// MarkChanges annotates a view with what a diff changed: entity nodes and
// calls to changed entities carry the finding's tier and number, and flow
// steps on changed lines carry "changed". The marks are fixed templates.
func MarkChanges(tree *Node, findings []Finding, touched map[string][]int) {
	byKey := map[string]string{}
	rank := 0
	for _, f := range findings {
		if f.Tier != TierInternal {
			rank++
			byKey[f.ID] = fmt.Sprintf("  <- %s #%d", f.Tier, rank)
		} else {
			byKey[f.ID] = "  <- INTERNAL"
		}
	}
	lines := map[string]map[int]bool{}
	for file, list := range touched {
		lines[file] = map[int]bool{}
		for _, line := range list {
			lines[file][line] = true
		}
	}
	var walk func(n *Node)
	walk = func(n *Node) {
		switch {
		case n.Ref != "" && byKey[n.Ref] != "":
			n.Label += byKey[n.Ref]
		case n.Line > 0 && lines[n.File][n.Line]:
			n.Label += "  <- changed"
		}
		for _, child := range n.Children {
			walk(child)
		}
	}
	walk(tree)
}

// Explain renders one finding's full score derivation, evidence, and callers.
// selector is the display number from LOOK HERE FIRST or a stable finding id.
func Explain(findings []Finding, head Facts, selector string) (string, error) {
	var attention []Finding
	for _, f := range findings {
		if f.Tier != TierInternal {
			attention = append(attention, f)
		}
	}
	var found *Finding
	number := 0
	if n, err := strconv.Atoi(selector); err == nil {
		if n < 1 || n > len(attention) {
			return "", fmt.Errorf("no finding %d; LOOK HERE FIRST numbers run 1 to %d", n, len(attention))
		}
		found, number = &attention[n-1], n
	} else {
		for i := range findings {
			if findings[i].ID == selector || findings[i].Entity == selector {
				found = &findings[i]
				break
			}
		}
		if found == nil {
			return "", fmt.Errorf("no finding %q; pass a number from LOOK HERE FIRST or a finding id", selector)
		}
		for i, f := range attention {
			if f.ID == found.ID {
				number = i + 1
			}
		}
	}
	var b strings.Builder
	title := "EXPLAIN " + found.Entity
	if number > 0 {
		title = fmt.Sprintf("EXPLAIN #%d %s", number, found.Entity)
	}
	fmt.Fprintf(&b, "%s\nreport format %d\n\n", title, ReportFormat)
	fmt.Fprintf(&b, "id       %s\ntier     %s\nwhere    %s\nreach    %d\nscore    %d\n", found.ID, found.Tier, found.Where, found.Reach, found.Score)
	b.WriteString("\nWHY\n")
	for _, c := range found.Changes {
		fmt.Fprintf(&b, "  change   %s\n", c)
	}
	for _, t := range found.Terms {
		fmt.Fprintf(&b, "  term     %s\n", t)
	}
	b.WriteString("\nEVIDENCE\n")
	if len(found.Evidence) == 0 {
		b.WriteString("  none\n")
	}
	for _, e := range found.Evidence {
		fmt.Fprintf(&b, "  %s\n", e)
	}
	b.WriteString("\nCALLERS\n")
	var callers []string
	for _, fact := range head.Entities {
		for _, callee := range fact.Calls {
			if callee == found.ID {
				callers = append(callers, fmt.Sprintf("%s  %s:%d", fact.Name, fact.File, fact.Line))
			}
		}
	}
	sort.Strings(callers)
	if len(callers) == 0 {
		b.WriteString("  none\n")
	}
	for _, c := range callers {
		fmt.Fprintf(&b, "  %s\n", c)
	}
	fmt.Fprintf(&b, "\nNEXT\n  ms diagram <project> --view flow --entity %s --diff <diff>\n", found.Entity)
	return b.String(), nil
}
