package tooling

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// ReportFormat is the version of the report template set. Any wording change
// bumps it, so two reports with the same format are comparable.
const ReportFormat = 1

// Section is one numbered report section: a table, plain lines, or both.
type Section struct {
	Title   string     `json:"title"`
	Headers []string   `json:"headers,omitempty"`
	Rows    [][]string `json:"rows,omitempty"`
	Lines   []string   `json:"lines,omitempty"`
	More    int        `json:"more,omitempty"`
}

// Report is the review result. Every string in it comes from a fixed template
// filled with checker facts; nothing is written by a model.
type Report struct {
	Format   int       `json:"format"`
	Mode     string    `json:"mode"`
	Input    string    `json:"input"`
	Result   string    `json:"result"`
	Sections []Section `json:"sections"`
	Findings []Finding `json:"findings,omitempty"`
	Digest   string    `json:"digest"`
}

// ReviewOptions selects how much of each section is shown.
type ReviewOptions struct{ All bool }

const rowCap = 5

func capped(rows [][]string, options ReviewOptions) ([][]string, int) {
	if options.All || len(rows) <= rowCap {
		return rows, 0
	}
	return rows[:rowCap], len(rows) - rowCap
}

func capLines(lines []string, options ReviewOptions) ([]string, int) {
	if options.All || len(lines) <= rowCap {
		return lines, 0
	}
	return lines[:rowCap], len(lines) - rowCap
}

// DiffReport builds the report for a change: head facts, base facts, and input.
func DiffReport(base, head Facts, input DiffInput, options ReviewOptions) Report {
	findings := CompareFacts(base, head, input)
	counts := map[string]int{}
	attention := 0
	for _, f := range findings {
		counts[f.Tier]++
		if f.Tier != TierInternal {
			attention++
		}
	}
	internal := counts[TierInternal]
	r := Report{Format: ReportFormat, Mode: "diff", Findings: findings}
	r.Input = fmt.Sprintf("diff (%d files, %d source, +%d -%d)", input.Files, input.Sources, input.Insertions, input.Deletions)
	switch {
	case !input.BaseChecked:
		r.Result = "base did not check; semantic comparison unavailable"
	case len(findings) == 0:
		r.Result = "no semantic change"
	default:
		r.Result = fmt.Sprintf("%d need attention, %d internal", attention, internal)
	}
	summary := Section{Title: "SUMMARY", Lines: []string{
		fmt.Sprintf("changed entities      %d", len(findings)),
		fmt.Sprintf("contract              %d", counts[TierContract]),
		fmt.Sprintf("effect                %d", counts[TierEffect]),
		fmt.Sprintf("error flow            %d", counts[TierError]),
		fmt.Sprintf("resource              %d", counts[TierResource]),
		fmt.Sprintf("internal only         %d", internal),
	}}
	var rows, evidence [][]string
	for _, f := range findings {
		if f.Tier == TierInternal {
			continue
		}
		rows = append(rows, []string{fmt.Sprint(len(rows) + 1), f.Tier, f.Entity, strings.Join(f.Changes, "; "), fmt.Sprint(f.Reach), f.Where, fmt.Sprint(f.Score)})
		evidence = append(evidence, []string{fmt.Sprint(len(rows)), strings.Join(append(append([]string{}, f.Evidence...), "score: "+strings.Join(f.Terms, ", ")), " | ")})
	}
	shown, more := capped(rows, options)
	look := Section{Title: "LOOK HERE FIRST", Headers: []string{"#", "TIER", "ENTITY", "CHANGE", "REACH", "WHERE", "SCORE"}, Rows: shown, More: more}
	shownEvidence, _ := capped(evidence, options)
	ev := Section{Title: "EVIDENCE", Headers: []string{"#", "DETAIL"}, Rows: shownEvidence}
	r.Sections = []Section{summary, look, ev,
		tierSection("EFFECTS", TierEffect, findings, options),
		tierSection("ERROR FLOW", TierError, findings, options),
		tierSection("RESOURCES", TierResource, findings, options),
		importSection(base, head),
		internalSection(findings, options),
	}
	r.Digest = r.digest()
	return r
}

// tierSection lists entities whose reasons include the tier, including those
// ranked into other tiers, so a section answers its question completely.
func tierSection(title, tier string, findings []Finding, options ReviewOptions) Section {
	prefixes := map[string][]string{
		TierEffect:   {"effects:"},
		TierError:    {"error type:", "try sites:"},
		TierResource: {"with scopes:"},
	}[tier]
	var lines []string
	for _, f := range findings {
		for _, change := range f.Changes {
			for _, p := range prefixes {
				if strings.HasPrefix(change, p) {
					lines = append(lines, f.Entity+" "+change)
				}
			}
		}
	}
	shown, more := capLines(lines, options)
	return Section{Title: title, Lines: shown, More: more}
}

func importSection(base, head Facts) Section {
	files := map[string]bool{}
	for file := range base.Imports {
		files[file] = true
	}
	for file := range head.Imports {
		files[file] = true
	}
	var names []string
	for file := range files {
		names = append(names, file)
	}
	sort.Strings(names)
	var lines []string
	for _, file := range names {
		old, now := toSet(base.Imports[file]), toSet(head.Imports[file])
		for _, path := range sortedKeys(now) {
			if !old[path] {
				lines = append(lines, "+ "+file+" imports "+path)
			}
		}
		for _, path := range sortedKeys(old) {
			if !now[path] {
				lines = append(lines, "- "+file+" imports "+path)
			}
		}
	}
	return Section{Title: "DEPENDENCIES", Lines: lines}
}

func internalSection(findings []Finding, options ReviewOptions) Section {
	var lines []string
	for _, f := range findings {
		if f.Tier == TierInternal {
			lines = append(lines, f.Entity+" ("+strings.Join(f.Changes, "; ")+")")
		}
	}
	sort.Strings(lines)
	shown, more := capLines(lines, options)
	return Section{Title: "INTERNAL", Lines: shown, More: more}
}

func toSet(list []string) map[string]bool {
	set := map[string]bool{}
	for _, v := range list {
		set[v] = true
	}
	return set
}

func sortedKeys(set map[string]bool) []string {
	var keys []string
	for k := range set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// ProjectReport describes the head alone: the same template without a diff.
func ProjectReport(head Facts, options ReviewOptions) Report {
	r := Report{Format: ReportFormat, Mode: "project", Input: "project (no diff)"}
	var keys []string
	exported, tests, withs := 0, 0, 0
	for key, f := range head.Entities {
		keys = append(keys, key)
		if f.Exported {
			exported++
		}
		if f.Kind == "test" {
			tests++
		}
		if f.Withs > 0 {
			withs++
		}
	}
	sort.Strings(keys)
	files := map[string]bool{}
	for _, f := range head.Entities {
		files[f.File] = true
	}
	r.Result = fmt.Sprintf("%d modules, %d entities", len(files), len(keys))
	summary := Section{Title: "SUMMARY", Lines: []string{
		fmt.Sprintf("modules               %d", len(files)),
		fmt.Sprintf("entities              %d", len(keys)),
		fmt.Sprintf("exported              %d", exported),
		fmt.Sprintf("tests                 %d", tests),
		fmt.Sprintf("with scopes           %d", withs),
	}}
	var surface, entries, resources [][]string
	errorTypes := map[string]int{}
	for _, key := range keys {
		f := head.Entities[key]
		if f.Exported {
			surface = append(surface, []string{f.Name, f.Kind, f.Type, fmt.Sprintf("%s:%d", f.File, f.Line)})
		}
		if (f.Name == "main" && f.Exported) || f.Kind == "test" {
			entries = append(entries, []string{f.Name, f.Kind, effectList(f.Effects), fmt.Sprintf("%s:%d", f.File, f.Line)})
		}
		if f.Withs > 0 {
			resources = append(resources, []string{f.Name, fmt.Sprint(f.Withs), fmt.Sprintf("%s:%d", f.File, f.Line)})
		}
		if f.Error != "" {
			errorTypes[f.Error]++
		}
	}
	var errorRows [][]string
	for _, e := range sortedMapKeys(errorTypes) {
		errorRows = append(errorRows, []string{e, fmt.Sprint(errorTypes[e])})
	}
	section := func(title string, headers []string, rows [][]string) Section {
		shown, more := capped(rows, options)
		return Section{Title: title, Headers: headers, Rows: shown, More: more}
	}
	r.Sections = []Section{summary,
		section("PUBLIC SURFACE", []string{"ENTITY", "KIND", "TYPE", "WHERE"}, surface),
		section("ENTRY POINTS", []string{"ENTITY", "KIND", "EFFECTS", "WHERE"}, entries),
		section("ERROR TYPES", []string{"TYPE", "FUNCTIONS"}, errorRows),
		section("RESOURCES", []string{"ENTITY", "WITH", "WHERE"}, resources),
		importMap(head),
	}
	r.Digest = r.digest()
	return r
}

func importMap(head Facts) Section {
	var files []string
	for file := range head.Imports {
		files = append(files, file)
	}
	sort.Strings(files)
	var lines []string
	for _, file := range files {
		lines = append(lines, file+" imports "+strings.Join(head.Imports[file], ", "))
	}
	return Section{Title: "DEPENDENCIES", Lines: lines}
}

func sortedMapKeys(m map[string]int) []string {
	var keys []string
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// digest hashes the ascii body, so equal digests mean equal reports.
func (r Report) digest() string {
	sum := sha256.Sum256([]byte(r.body("ascii")))
	return "sha256:" + hex.EncodeToString(sum[:])
}

// Render writes the report as ascii, markdown, or json.
func (r Report) Render(format string) string {
	if format == "json" {
		data, _ := json.MarshalIndent(r, "", "  ")
		return string(data) + "\n"
	}
	return r.body(format) + "\ndigest " + r.Digest + "\n"
}

func (r Report) body(format string) string {
	var b strings.Builder
	md := format == "markdown"
	if md {
		fmt.Fprintf(&b, "# Manuscript review report (format %d)\n\n- input: %s\n- result: %s\n", r.Format, r.Input, r.Result)
	} else {
		fmt.Fprintf(&b, "MANUSCRIPT REVIEW REPORT  format %d\ninput   %s\nresult  %s\n", r.Format, r.Input, r.Result)
	}
	for i, s := range r.Sections {
		if md {
			fmt.Fprintf(&b, "\n## %d. %s\n\n", i+1, s.Title)
		} else {
			fmt.Fprintf(&b, "\n%d. %s\n", i+1, s.Title)
		}
		writeSection(&b, s, md)
	}
	return strings.TrimRight(b.String(), "\n") + "\n"
}

func writeSection(b *strings.Builder, s Section, md bool) {
	if len(s.Rows) == 0 && len(s.Lines) == 0 {
		b.WriteString(indent(md) + "none\n")
		return
	}
	if len(s.Rows) > 0 {
		writeTable(b, s, md)
	}
	for _, line := range s.Lines {
		b.WriteString(indent(md) + line + "\n")
	}
	if s.More > 0 {
		fmt.Fprintf(b, "%s+%d more (use --all)\n", indent(md), s.More)
	}
}

func indent(md bool) string {
	if md {
		return "- "
	}
	return "   "
}

func writeTable(b *strings.Builder, s Section, md bool) {
	if md {
		b.WriteString("| " + strings.Join(s.Headers, " | ") + " |\n")
		b.WriteString("|" + strings.Repeat(" --- |", len(s.Headers)) + "\n")
		for _, row := range s.Rows {
			b.WriteString("| " + strings.Join(escapeCells(row), " | ") + " |\n")
		}
		return
	}
	widths := make([]int, len(s.Headers))
	for i, h := range s.Headers {
		widths[i] = len(h)
	}
	for _, row := range s.Rows {
		for i, cell := range row {
			widths[i] = max(widths[i], len(cell))
		}
	}
	line := func(cells []string) {
		var parts []string
		for i, cell := range cells {
			if i == len(cells)-1 {
				parts = append(parts, cell)
				continue
			}
			parts = append(parts, cell+strings.Repeat(" ", widths[i]-len(cell)))
		}
		b.WriteString("   " + strings.Join(parts, "  ") + "\n")
	}
	line(s.Headers)
	for _, row := range s.Rows {
		line(row)
	}
}

func escapeCells(row []string) []string {
	out := make([]string, len(row))
	for i, c := range row {
		out[i] = strings.ReplaceAll(c, "|", "\\|")
	}
	return out
}
