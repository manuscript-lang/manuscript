package docgen

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"unicode"
)

// The backlog records exact existing gaps during the source-comment sweep. It
// is not an exemption: new gaps fail, invalid prose cannot use it, and described
// entries must be removed. The completed sweep leaves this list empty.
//
//go:embed description_backlog.json
var descriptionBacklog []byte

type DescriptionPolicy struct {
	Format  int      `json:"format"`
	Backlog []string `json:"backlog"`
}

func StandardDescriptionPolicy() (DescriptionPolicy, error) {
	var policy DescriptionPolicy
	decoder := json.NewDecoder(strings.NewReader(string(descriptionBacklog)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&policy); err != nil {
		return policy, err
	}
	if policy.Format != 1 {
		return policy, fmt.Errorf("unsupported description policy format %d", policy.Format)
	}
	return policy, nil
}

// DescriptionKey identifies a checked declaration/member, including its actual
// module and implementation contract. Prelude aliases retain separate entries.
func DescriptionKey(entry DocumentationEntry) string {
	return strings.Join([]string{entry.Module, entry.Declaration, entry.Kind, entry.Name, entry.Contract}, "|")
}

// CheckDescriptions enforces source-derived coverage and a shrinking backlog.
// Quality checks reject obvious boilerplate; semantic accuracy still requires
// reviewing the source/native contracts, not counting words as a proof.
func CheckDescriptions(report DocumentationInventory, policy DescriptionPolicy) []string {
	backlog := map[string]bool{}
	var problems []string
	for _, key := range policy.Backlog {
		if backlog[key] {
			problems = append(problems, key+": duplicate description backlog entry")
		}
		backlog[key] = true
	}
	seen := map[string]bool{}
	for _, entry := range report.Entries {
		key := DescriptionKey(entry)
		seen[key] = true
		if backlog[key] && entry.Described {
			problems = append(problems, key+": description exists; remove the stale backlog entry")
		}
		if entry.Qualified || !entry.Described && backlog[key] {
			continue
		}
		problems = append(problems, key+": "+entry.Problem+"; describe observable behavior, units, defaults, errors or ownership")
	}
	for key := range backlog {
		if !seen[key] {
			problems = append(problems, key+": API no longer exists; remove the stale backlog entry")
		}
	}
	sort.Strings(problems)
	return problems
}

func descriptionProblem(entry DocumentationEntry, doc string) string {
	raw := strings.TrimSpace(doc)
	text := strings.ToLower(raw)
	if text == "" {
		return "missing description"
	}
	for _, placeholder := range []string{"todo", "tbd", "fixme", "placeholder", "undocumented", "description goes here", "documentation goes here"} {
		if strings.HasPrefix(strings.TrimLeft(text, "# `*"), placeholder) {
			return "placeholder description"
		}
	}
	words := descriptionWords(raw)
	if len(words) < 4 {
		return "description is too terse to state a contract"
	}
	ignored := map[string]bool{}
	for _, word := range descriptionWords(entry.Name + " " + entry.Declaration) {
		ignored[word] = true
	}
	for _, word := range strings.Fields("a an the this that these those it its s of for to from with without and or in on at by as is are be can may will field member method function operation case type declaration public exported native standard api value data object property describes describing represents returns holds provides gets sets has about information description documentation named called contains containing stores stored storing reports whether behavior behaviour contract fn record interface int int64 float float64 bool unit never string bytes optional result list map set payload") {
		ignored[word] = true
	}
	for _, word := range words {
		if !ignored[word] {
			return ""
		}
	}
	return "description only restates the API name or kind"
}

func descriptionWords(text string) []string {
	// Split camel-case names as well as ordinary prose and snake_case names.
	var separated strings.Builder
	var previous rune
	for _, r := range text {
		if unicode.IsUpper(r) && unicode.IsLower(previous) {
			separated.WriteByte(' ')
		}
		separated.WriteRune(unicode.ToLower(r))
		previous = r
	}
	return strings.FieldsFunc(separated.String(), func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
}
