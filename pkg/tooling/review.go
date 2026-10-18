package tooling

import (
	"fmt"
	"math/bits"
	"sort"
	"strings"
)

// Tier names, highest attention first. The weights are the whole ranking
// policy; --explain style detail is the Terms on each finding.
const (
	TierContract = "CONTRACT"
	TierEffect   = "EFFECT+"
	TierError    = "ERROR"
	TierResource = "RESOURCE"
	TierInternal = "INTERNAL"
)

var tierRank = map[string]int{TierContract: 0, TierEffect: 1, TierError: 2, TierResource: 3, TierInternal: 4}

// Finding is one changed entity with every reason it needs attention.
type Finding struct {
	ID       string   `json:"id"`
	Tier     string   `json:"tier"`
	Entity   string   `json:"entity"`
	Where    string   `json:"where"`
	Changes  []string `json:"changes"`
	Reach    int      `json:"reach"`
	Score    int      `json:"score"`
	Terms    []string `json:"terms"`
	Evidence []string `json:"evidence,omitempty"`
}

// DiffInput is the changed-file information a diff review needs.
type DiffInput struct {
	Files       int             // files in the diff
	Sources     int             // .ms files inside the project
	Added       map[string]bool // project-relative files that did not exist before
	Touched     map[string][]int
	Insertions  int
	Deletions   int
	BaseChecked bool
}

// CompareFacts classifies what changed between base and head. Both are
// produced by the same checker; touched maps a file to its changed head lines.
func CompareFacts(base, head Facts, input DiffInput) []Finding {
	reach := reachCounts(head)
	keys := map[string]bool{}
	for key := range head.Entities {
		keys[key] = true
	}
	for key := range base.Entities {
		keys[key] = true
	}
	touched := touchedKeys(head, input.Touched)
	var findings []Finding
	for key := range keys {
		h, b := head.Entities[key], base.Entities[key]
		if b != nil && input.Added[b.File] {
			b = nil
		}
		f := classify(key, h, b, input.BaseChecked, reach, head)
		if len(f.Changes) == 0 && touched[key] {
			f.Changes = []string{"body changed"}
		}
		if len(f.Changes) == 0 {
			continue
		}
		findings = append(findings, f)
	}
	sort.Slice(findings, func(i, j int) bool {
		a, b := findings[i], findings[j]
		if a.Score != b.Score {
			return a.Score > b.Score
		}
		if tierRank[a.Tier] != tierRank[b.Tier] {
			return tierRank[a.Tier] < tierRank[b.Tier]
		}
		return a.ID < b.ID
	})
	return findings
}

func classify(key string, h, b *Fact, baseChecked bool, reach map[string]int, head Facts) Finding {
	f := Finding{ID: key}
	subject := h
	if subject == nil {
		subject = b
	}
	f.Entity = subject.Name
	f.Where = fmt.Sprintf("%s:%d", subject.File, subject.Line)
	score := map[string]int{}
	add := func(tier, change, term string, weight int) {
		f.Changes = append(f.Changes, change)
		f.Terms = append(f.Terms, fmt.Sprintf("%s +%d", term, weight))
		score[tier] += weight
		f.Score += weight
	}
	switch {
	case h != nil && b == nil && baseChecked:
		add(TierInternal, "added", "added", 1)
		if h.Exported {
			add(TierContract, "added exported "+h.Kind, "contract", 8)
		}
	case h == nil && b != nil:
		add(TierInternal, "removed", "removed", 1)
		if b.Exported {
			add(TierContract, "removed exported "+b.Kind, "contract", 8)
		}
	case h != nil && b != nil:
		compare(h, b, add)
	}
	if h == nil {
		f.Tier = tierOf(score)
		return f
	}
	if b != nil {
		if gained := gainedEffects(h, b); len(gained) > 0 {
			f.Evidence = append(f.Evidence, effectPath(h, gained, head))
		}
	}
	if len(f.Changes) > 0 && f.Score > 1 {
		r := reach[key]
		f.Reach = r
		if r > 0 {
			f.Terms = append(f.Terms, fmt.Sprintf("reach(%d) +%d", r, 2*bits.Len(uint(r))))
			f.Score += 2 * bits.Len(uint(r))
		}
		if h.Exported {
			f.Terms = append(f.Terms, "exported +3")
			f.Score += 3
		}
	}
	f.Tier = tierOf(score)
	return f
}

func compare(h, b *Fact, add func(tier, change, term string, weight int)) {
	if h.Exported != b.Exported {
		add(TierContract, "visibility: "+visibility(b.Exported)+" -> "+visibility(h.Exported), "contract", 8)
	}
	if h.Type != b.Type {
		if h.Exported {
			add(TierContract, "type: "+b.Type+" -> "+h.Type, "contract", 8)
		} else {
			add(TierInternal, "private type: "+b.Type+" -> "+h.Type, "signature", 1)
		}
	}
	if gained := gainedEffects(h, b); len(gained) > 0 {
		add(TierEffect, "effects: "+effectList(b.Effects)+" -> "+effectList(h.Effects), "effect_gain", 6)
	} else if effectList(h.Effects) != effectList(b.Effects) {
		add(TierInternal, "effects: "+effectList(b.Effects)+" -> "+effectList(h.Effects), "effect_loss", 1)
	}
	if h.Error != b.Error {
		add(TierError, "error type: "+orNone(b.Error)+" -> "+orNone(h.Error), "error_flow", 5)
	}
	if h.Tries != b.Tries {
		add(TierError, fmt.Sprintf("try sites: %d -> %d", b.Tries, h.Tries), "error_flow", 5)
	}
	if h.Withs != b.Withs {
		add(TierResource, fmt.Sprintf("with scopes: %d -> %d", b.Withs, h.Withs), "resource", 4)
	}
}

func tierOf(score map[string]int) string {
	best, rank := TierInternal, tierRank[TierInternal]
	for tier, weight := range score {
		if weight > 1 && tierRank[tier] < rank {
			best, rank = tier, tierRank[tier]
		}
	}
	return best
}

func visibility(exported bool) string {
	if exported {
		return "exported"
	}
	return "private"
}

func orNone(s string) string {
	if s == "" {
		return "none"
	}
	return s
}

func effectList(effects []string) string {
	if len(effects) == 0 {
		return "none"
	}
	return strings.Join(effects, "+")
}

func gainedEffects(h, b *Fact) []string {
	had := map[string]bool{}
	if b != nil {
		for _, e := range b.Effects {
			had[e] = true
		}
	}
	var gained []string
	for _, e := range h.Effects {
		if !had[e] {
			gained = append(gained, e)
		}
	}
	return gained
}

// effectPath follows callees that carry a gained effect down to the native
// operation or boundary where it enters, choosing the first name at each step.
func effectPath(start *Fact, gained []string, head Facts) string {
	path := []string{start.Name}
	seen := map[string]bool{start.Key: true}
	current := start
	for {
		var next *Fact
		for _, key := range current.Calls {
			callee := head.Entities[key]
			if callee != nil && !seen[key] && hasAny(callee.Effects, gained) {
				next = callee
				break
			}
		}
		if next == nil {
			break
		}
		seen[next.Key] = true
		path = append(path, next.Name)
		current = next
	}
	if len(current.External) > 0 {
		path = append(path, current.External[0])
	}
	return "path: " + strings.Join(path, " -> ")
}

func hasAny(have, want []string) bool {
	for _, w := range want {
		for _, h := range have {
			if h == w {
				return true
			}
		}
	}
	return false
}

// reachCounts is the number of distinct project entities that transitively call each entity.
func reachCounts(facts Facts) map[string]int {
	callers := map[string][]string{}
	for key, fact := range facts.Entities {
		for _, callee := range fact.Calls {
			callers[callee] = append(callers[callee], key)
		}
	}
	result := map[string]int{}
	for key := range facts.Entities {
		seen := map[string]bool{key: true}
		queue := []string{key}
		for len(queue) > 0 {
			next := queue[0]
			queue = queue[1:]
			for _, caller := range callers[next] {
				if !seen[caller] {
					seen[caller] = true
					queue = append(queue, caller)
				}
			}
		}
		result[key] = len(seen) - 1
	}
	return result
}

// touchedKeys maps changed head lines to the most specific entity containing them.
func touchedKeys(head Facts, touched map[string][]int) map[string]bool {
	byFile := map[string][]*Fact{}
	for _, fact := range head.Entities {
		if fact.First > 0 {
			byFile[fact.File] = append(byFile[fact.File], fact)
		}
	}
	result := map[string]bool{}
	for file, lines := range touched {
		facts := byFile[file]
		for _, line := range lines {
			var best *Fact
			for _, fact := range facts {
				if line < fact.First || line > fact.Last {
					continue
				}
				if best == nil || fact.Last-fact.First < best.Last-best.First || (fact.Last-fact.First == best.Last-best.First && fact.Key < best.Key) {
					best = fact
				}
			}
			if best != nil {
				result[best.Key] = true
			}
		}
	}
	return result
}
