package checker

import "sort"

// StandardDataTypes returns every standard record and alternative type in a
// stable order, so the lowerer can register the field order and payload labels
// that dynamic standard values do not carry (see @std/json's stringify).
func StandardDataTypes() []*Type {
	seen := map[string]bool{}
	var out []*Type
	add := func(s *Symbol) {
		if s == nil || s.Type == nil || s.Type.Def == nil || seen[s.Type.ID] {
			return
		}
		if s.Type.Kind != "record" && s.Type.Kind != "alternative" {
			return
		}
		seen[s.Type.ID] = true
		out = append(out, s.Type)
	}
	for _, exports := range allStandardExports() {
		for _, s := range exports {
			add(s)
		}
	}
	standardMu.Lock()
	for _, s := range standardSymbols {
		add(s)
	}
	standardMu.Unlock()
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}
