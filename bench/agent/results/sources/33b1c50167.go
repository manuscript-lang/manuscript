package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

var out *bufio.Writer

// ---------- hashing ----------

func hashStr(s string) string {
	h := uint64(14695981039346656037)
	for i := 0; i < len(s); i++ {
		h ^= uint64(s[i])
		h *= 1099511628211
	}
	return fmt.Sprintf("%016x", h)
}

func short(id string) string {
	if len(id) > 7 {
		return id[:7]
	}
	return id
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func copyMap(m map[string]string) map[string]string {
	c := make(map[string]string, len(m))
	for k, v := range m {
		c[k] = v
	}
	return c
}

func treesEqual(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		w, ok := b[k]
		if !ok || w != v {
			return false
		}
	}
	return true
}

func eqFile(a string, aok bool, b string, bok bool) bool {
	return aok == bok && (!aok || a == b)
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func isLowerHex(s string) bool {
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return s != ""
}

var nameRe = regexp.MustCompile(`^[A-Za-z0-9._/][A-Za-z0-9._/-]*$`)

func validName(s string) bool { return nameRe.MatchString(s) }

func treeHash(tree map[string]string) string {
	var b strings.Builder
	for _, n := range sortedKeys(tree) {
		b.WriteString(n + " " + hashStr(tree[n]) + "\n")
	}
	return hashStr(b.String())
}

// ---------- line diff ----------

func splitLines(content string) []string {
	if content == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(content, "\n"), "\n")
}

func eqLines(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// matchPairs returns the matching pairs (i, j) as walked by the spec's algorithm.
func matchPairs(a, b []string) [][2]int {
	n, m := len(a), len(b)
	L := make([][]int, n+1)
	for i := range L {
		L[i] = make([]int, m+1)
	}
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if a[i] == b[j] {
				L[i][j] = L[i+1][j+1] + 1
			} else if L[i+1][j] >= L[i][j+1] {
				L[i][j] = L[i+1][j]
			} else {
				L[i][j] = L[i][j+1]
			}
		}
	}
	var pairs [][2]int
	i, j := 0, 0
	for i < n && j < m {
		if a[i] == b[j] {
			pairs = append(pairs, [2]int{i, j})
			i++
			j++
		} else if L[i+1][j] >= L[i][j+1] {
			i++
		} else {
			j++
		}
	}
	return pairs
}

func lineDiff(a, b []string) []string {
	var res []string
	pa, pb := 0, 0
	for _, p := range matchPairs(a, b) {
		for pa < p[0] {
			res = append(res, "- "+a[pa])
			pa++
		}
		for pb < p[1] {
			res = append(res, "+ "+b[pb])
			pb++
		}
		res = append(res, "  "+a[p[0]])
		pa = p[0] + 1
		pb = p[1] + 1
	}
	for ; pa < len(a); pa++ {
		res = append(res, "- "+a[pa])
	}
	for ; pb < len(b); pb++ {
		res = append(res, "+ "+b[pb])
	}
	return res
}

// mergeLines performs the three-way line merge. clean is false if conflict markers were emitted.
func mergeLines(base, ours, theirs []string, branch string) ([]string, bool) {
	bo := map[int]int{}
	for _, p := range matchPairs(base, ours) {
		bo[p[0]] = p[1]
	}
	bt := map[int]int{}
	for _, p := range matchPairs(base, theirs) {
		bt[p[0]] = p[1]
	}
	type triple struct{ b, o, t int }
	var stable []triple
	for bi := range base {
		oi, ok1 := bo[bi]
		ti, ok2 := bt[bi]
		if ok1 && ok2 {
			stable = append(stable, triple{bi, oi, ti})
		}
	}
	var res []string
	clean := true
	pb, po, pt := -1, -1, -1
	process := func(sb, so, st int, final bool) {
		bc := base[pb+1 : sb]
		oc := ours[po+1 : so]
		tc := theirs[pt+1 : st]
		switch {
		case eqLines(oc, bc):
			res = append(res, tc...)
		case eqLines(tc, bc):
			res = append(res, oc...)
		case eqLines(oc, tc):
			res = append(res, oc...)
		default:
			clean = false
			res = append(res, "<<<<<<< HEAD")
			res = append(res, oc...)
			res = append(res, "=======")
			res = append(res, tc...)
			res = append(res, ">>>>>>> "+branch)
		}
		if !final {
			res = append(res, base[sb])
		}
		pb, po, pt = sb, so, st
	}
	for _, s := range stable {
		process(s.b, s.o, s.t, false)
	}
	process(len(base), len(ours), len(theirs), true)
	return res, clean
}

func joinLines(lines []string) string {
	var b strings.Builder
	for _, l := range lines {
		b.WriteString(l + "\n")
	}
	return b.String()
}

// ---------- repository ----------

type Commit struct {
	id      string
	parents []string
	msg     string
	tree    map[string]string
	seq     int
}

type Repo struct {
	commits     map[string]*Commit
	count       int
	branches    map[string]string // name -> commit id ("" = unborn)
	head        string            // current branch name (when attached)
	detached    bool
	detachedID  string
	tags        map[string]string
	work        map[string]string
	index       map[string]string
	conflicts   map[string]bool
	merging     bool
	mergeOther  string
	mergeBranch string
}

func newRepo() *Repo {
	return &Repo{
		commits:   map[string]*Commit{},
		branches:  map[string]string{"main": ""},
		head:      "main",
		tags:      map[string]string{},
		work:      map[string]string{},
		index:     map[string]string{},
		conflicts: map[string]bool{},
	}
}

func (r *Repo) headID() string {
	if r.detached {
		return r.detachedID
	}
	return r.branches[r.head]
}

func (r *Repo) headTree() map[string]string {
	id := r.headID()
	if id == "" {
		return map[string]string{}
	}
	return r.commits[id].tree
}

func (r *Repo) headLabel() string {
	if r.detached {
		return "detached"
	}
	return r.head
}

func (r *Repo) makeCommit(tree map[string]string, parents []string, msg string) *Commit {
	var b strings.Builder
	b.WriteString("tree " + treeHash(tree) + "\n")
	for _, p := range parents {
		b.WriteString("parent " + p + "\n")
	}
	b.WriteString("\n" + msg + "\n")
	id := hashStr(b.String())
	if c, ok := r.commits[id]; ok {
		return c
	}
	r.count++
	c := &Commit{id: id, parents: append([]string(nil), parents...), msg: msg, tree: copyMap(tree), seq: r.count}
	r.commits[id] = c
	return c
}

func (r *Repo) moveHead(id string) {
	if r.detached {
		r.detachedID = id
	} else {
		r.branches[r.head] = id
	}
}

func (r *Repo) commitLine(c *Commit) string {
	if len(c.parents) == 0 {
		return fmt.Sprintf("[%s (root-commit) %s] %s", r.headLabel(), short(c.id), c.msg)
	}
	return fmt.Sprintf("[%s %s] %s", r.headLabel(), short(c.id), c.msg)
}

func (r *Repo) ancestors(id string) map[string]bool {
	set := map[string]bool{}
	stack := []string{id}
	for len(stack) > 0 {
		x := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if set[x] {
			continue
		}
		set[x] = true
		stack = append(stack, r.commits[x].parents...)
	}
	return set
}

// resolve implements REF / BASE~N resolution. Returns id, or an error message.
func (r *Repo) resolve(ref string) (string, string) {
	unknown := "unknown revision '" + ref + "'"
	base := ref
	steps := 0
	if k := strings.Index(ref, "~"); k >= 0 {
		base = ref[:k]
		ns := ref[k+1:]
		if !isDigits(ns) {
			return "", unknown
		}
		v, err := strconv.Atoi(ns)
		if err != nil {
			v = 1 << 62
		}
		steps = v
	}
	id, e := r.resolveBase(base, ref)
	if e != "" {
		return "", e
	}
	for s := 0; s < steps; s++ {
		c := r.commits[id]
		if len(c.parents) == 0 {
			return "", unknown
		}
		id = c.parents[0]
	}
	return id, ""
}

func (r *Repo) resolveBase(base, ref string) (string, string) {
	if base == "HEAD" {
		if id := r.headID(); id != "" {
			return id, ""
		}
	}
	if id, ok := r.branches[base]; ok && id != "" {
		return id, ""
	}
	if id, ok := r.tags[base]; ok {
		return id, ""
	}
	if len(base) >= 4 && isLowerHex(base) {
		var matches []string
		for id := range r.commits {
			if strings.HasPrefix(id, base) {
				matches = append(matches, id)
			}
		}
		if len(matches) == 1 {
			return matches[0], ""
		}
		if len(matches) > 1 {
			return "", "ambiguous revision '" + ref + "'"
		}
	}
	return "", "unknown revision '" + ref + "'"
}

func (r *Repo) treeOf(ref string) (map[string]string, string) {
	id, e := r.resolve(ref)
	if e != "" {
		return nil, e
	}
	return r.commits[id].tree, ""
}

// dirtyCheck returns the error message if local changes would be overwritten.
func (r *Repo) dirtyCheck() string {
	const msg = "local changes would be overwritten"
	if !treesEqual(r.index, r.headTree()) {
		return msg
	}
	for _, n := range sortedKeys(r.index) {
		w, ok := r.work[n]
		if !ok || w != r.index[n] {
			return msg
		}
	}
	return ""
}

// untrackedCheck returns the error for a file in target that is untracked in the working tree.
func (r *Repo) untrackedCheck(target map[string]string) string {
	for _, n := range sortedKeys(target) {
		if _, inIdx := r.index[n]; inIdx {
			continue
		}
		if _, inW := r.work[n]; inW {
			return "untracked file would be overwritten: " + n
		}
	}
	return ""
}

// switchTo sets the index to target and updates the working tree (checks already done).
func (r *Repo) switchTo(target map[string]string) {
	for n := range r.index {
		delete(r.work, n)
	}
	for n, c := range target {
		r.work[n] = c
	}
	r.index = copyMap(target)
}

// resetTo implements reset --hard to commit id.
func (r *Repo) resetTo(id string) {
	oldIdx := r.index
	oldHT := r.headTree()
	r.moveHead(id)
	newT := r.commits[id].tree
	for n := range oldIdx {
		delete(r.work, n)
	}
	for n := range oldHT {
		delete(r.work, n)
	}
	for n, c := range newT {
		r.work[n] = c
	}
	r.index = copyMap(newT)
	r.conflicts = map[string]bool{}
	r.merging = false
	r.mergeOther = ""
	r.mergeBranch = ""
}

// ---------- output helpers ----------

func fail(msg string) {
	fmt.Fprintf(out, "error: %s\n", msg)
}

func usage(s string) {
	fmt.Fprintf(out, "usage: %s\n", s)
}

// ---------- commands ----------

func (r *Repo) addPath(p string) bool {
	if p == "." {
		for _, n := range sortedKeys(r.work) {
			r.index[n] = r.work[n]
			delete(r.conflicts, n)
		}
		for _, n := range sortedKeys(r.index) {
			if _, ok := r.work[n]; !ok {
				delete(r.index, n)
				delete(r.conflicts, n)
			}
		}
		return true
	}
	if c, ok := r.work[p]; ok {
		r.index[p] = c
		delete(r.conflicts, p)
		return true
	}
	if _, ok := r.index[p]; ok {
		delete(r.index, p)
		delete(r.conflicts, p)
		return true
	}
	if r.conflicts[p] {
		delete(r.conflicts, p)
		return true
	}
	return false
}

func (r *Repo) status() {
	if r.detached {
		fmt.Fprintf(out, "HEAD detached at %s\n", short(r.detachedID))
	} else {
		fmt.Fprintf(out, "On branch %s\n", r.head)
	}
	if r.merging {
		fmt.Fprintf(out, "merging: %s\n", r.mergeBranch)
	}
	headT := r.headTree()
	var staged, unstaged, conflicts, untracked []string

	seen := map[string]bool{}
	var union []string
	for n := range headT {
		if !seen[n] {
			seen[n] = true
			union = append(union, n)
		}
	}
	for n := range r.index {
		if !seen[n] {
			seen[n] = true
			union = append(union, n)
		}
	}
	sort.Strings(union)
	for _, n := range union {
		if r.conflicts[n] {
			continue
		}
		hc, inH := headT[n]
		ic, inI := r.index[n]
		switch {
		case inI && !inH:
			staged = append(staged, "new file: "+n)
		case inH && !inI:
			staged = append(staged, "deleted: "+n)
		case hc != ic:
			staged = append(staged, "modified: "+n)
		}
	}
	for _, n := range sortedKeys(r.index) {
		if r.conflicts[n] {
			continue
		}
		w, ok := r.work[n]
		if !ok {
			unstaged = append(unstaged, "deleted: "+n)
		} else if w != r.index[n] {
			unstaged = append(unstaged, "modified: "+n)
		}
	}
	for _, n := range sortedKeys(r.conflicts) {
		conflicts = append(conflicts, "unmerged: "+n)
	}
	for _, n := range sortedKeys(r.work) {
		if _, ok := r.index[n]; ok || r.conflicts[n] {
			continue
		}
		untracked = append(untracked, n)
	}
	if len(staged)+len(unstaged)+len(conflicts)+len(untracked) == 0 {
		fmt.Fprintln(out, "nothing to commit, working tree clean")
		return
	}
	section := func(h string, items []string) {
		if len(items) == 0 {
			return
		}
		fmt.Fprintln(out, h+":")
		for _, it := range items {
			fmt.Fprintln(out, "  "+it)
		}
	}
	section("staged", staged)
	section("unstaged", unstaged)
	section("conflicts", conflicts)
	section("untracked", untracked)
}

func (r *Repo) commit(msg string) {
	if msg == "" {
		fail("empty commit message")
		return
	}
	if len(r.conflicts) > 0 {
		fail("unresolved conflicts: " + strings.Join(sortedKeys(r.conflicts), " "))
		return
	}
	if r.merging {
		c := r.makeCommit(r.index, []string{r.headID(), r.mergeOther}, msg)
		r.moveHead(c.id)
		r.merging = false
		r.mergeOther = ""
		r.mergeBranch = ""
		fmt.Fprintln(out, r.commitLine(c))
		return
	}
	if treesEqual(r.index, r.headTree()) {
		fail("nothing to commit")
		return
	}
	var parents []string
	if id := r.headID(); id != "" {
		parents = []string{id}
	}
	c := r.makeCommit(r.index, parents, msg)
	r.moveHead(c.id)
	fmt.Fprintln(out, r.commitLine(c))
}

func (r *Repo) log(args []string) {
	n := -1
	if len(args) == 2 && args[0] == "-n" && isDigits(args[1]) {
		v, err := strconv.Atoi(args[1])
		if err != nil {
			v = 1 << 62
		}
		n = v
	} else if len(args) != 0 {
		usage("log [-n N]")
		return
	}
	id := r.headID()
	if id == "" {
		fail("no commits yet")
		return
	}
	set := r.ancestors(id)
	var cs []*Commit
	for x := range set {
		cs = append(cs, r.commits[x])
	}
	sort.Slice(cs, func(i, j int) bool { return cs[i].seq > cs[j].seq })
	for i, c := range cs {
		if n >= 0 && i >= n {
			break
		}
		if len(c.parents) == 2 {
			fmt.Fprintf(out, "%s %s (merge %s %s)\n", short(c.id), c.msg, short(c.parents[0]), short(c.parents[1]))
		} else {
			fmt.Fprintf(out, "%s %s\n", short(c.id), c.msg)
		}
	}
}

func (r *Repo) diff(args []string) {
	if len(args) > 2 {
		usage("diff [REF [REF]]")
		return
	}
	var left, right map[string]string
	var e string
	switch len(args) {
	case 0:
		left, right = r.index, r.work
	case 1:
		if left, e = r.treeOf(args[0]); e != "" {
			fail(e)
			return
		}
		right = r.work
	case 2:
		if left, e = r.treeOf(args[0]); e != "" {
			fail(e)
			return
		}
		if right, e = r.treeOf(args[1]); e != "" {
			fail(e)
			return
		}
	}
	seen := map[string]bool{}
	var names []string
	for _, m := range []map[string]string{left, right} {
		for n := range m {
			if !seen[n] {
				seen[n] = true
				names = append(names, n)
			}
		}
	}
	sort.Strings(names)
	any := false
	for _, n := range names {
		lc, lok := left[n]
		rc, rok := right[n]
		if eqFile(lc, lok, rc, rok) {
			continue
		}
		any = true
		fmt.Fprintf(out, "diff %s\n", n)
		if !lok {
			fmt.Fprintln(out, "new file")
		}
		if !rok {
			fmt.Fprintln(out, "deleted file")
		}
		for _, l := range lineDiff(splitLines(lc), splitLines(rc)) {
			fmt.Fprintln(out, l)
		}
	}
	if !any {
		fmt.Fprintln(out, "(no differences)")
	}
}

// createBranch checks and creates a branch at HEAD's commit; returns error message.
func (r *Repo) createBranch(name string) string {
	if !validName(name) {
		return "invalid branch name '" + name + "'"
	}
	if _, ok := r.branches[name]; ok {
		return "branch '" + name + "' already exists"
	}
	id := r.headID()
	if id == "" {
		return "no commits yet"
	}
	r.branches[name] = id
	return ""
}

func (r *Repo) branchCmd(args []string) {
	switch {
	case len(args) == 0:
		if r.detached {
			fmt.Fprintf(out, "* (HEAD detached at %s)\n", short(r.detachedID))
		}
		for _, n := range sortedKeys(r.branches) {
			if !r.detached && n == r.head {
				fmt.Fprintln(out, "* "+n)
			} else {
				fmt.Fprintln(out, "  "+n)
			}
		}
	case len(args) == 1:
		if e := r.createBranch(args[0]); e != "" {
			fail(e)
		}
	case len(args) == 2 && args[0] == "-d":
		name := args[1]
		id, ok := r.branches[name]
		if !ok {
			fail("branch '" + name + "' not found")
			return
		}
		if !r.detached && name == r.head {
			fail("cannot delete the current branch '" + name + "'")
			return
		}
		merged := false
		if hid := r.headID(); hid != "" && id != "" {
			merged = id == hid || r.ancestors(hid)[id]
		}
		if !merged {
			fail("branch '" + name + "' is not fully merged")
			return
		}
		fmt.Fprintf(out, "Deleted branch %s (was %s).\n", name, short(id))
		delete(r.branches, name)
	default:
		usage("branch [NAME | -d NAME]")
	}
}

func (r *Repo) tagCmd(args []string) {
	if len(args) == 0 {
		for _, n := range sortedKeys(r.tags) {
			fmt.Fprintln(out, n)
		}
		return
	}
	if len(args) > 2 {
		usage("tag [NAME [REF]]")
		return
	}
	name := args[0]
	if !validName(name) {
		fail("invalid tag name '" + name + "'")
		return
	}
	if _, ok := r.tags[name]; ok {
		fail("tag '" + name + "' already exists")
		return
	}
	ref := "HEAD"
	if len(args) == 2 {
		ref = args[1]
	}
	if ref == "HEAD" && r.headID() == "" {
		fail("no commits yet")
		return
	}
	id, e := r.resolve(ref)
	if e != "" {
		fail(e)
		return
	}
	r.tags[name] = id
}

func (r *Repo) show(args []string) {
	if len(args) != 1 {
		usage("show REF")
		return
	}
	id, e := r.resolve(args[0])
	if e != "" {
		fail(e)
		return
	}
	c := r.commits[id]
	fmt.Fprintf(out, "commit %s\n", c.id)
	fmt.Fprintf(out, "tree %s\n", treeHash(c.tree))
	for _, p := range c.parents {
		fmt.Fprintf(out, "parent %s\n", p)
	}
	fmt.Fprintf(out, "message: %s\n", c.msg)
	fmt.Fprintln(out, "files:")
	for _, n := range sortedKeys(c.tree) {
		fmt.Fprintf(out, "  %s %s\n", n, short(hashStr(c.tree[n])))
	}
}

func (r *Repo) checkout(args []string) {
	if len(args) == 2 && args[0] == "-b" {
		name := args[1]
		if e := r.createBranch(name); e != "" {
			fail(e)
			return
		}
		r.head = name
		r.detached = false
		fmt.Fprintf(out, "Switched to a new branch '%s'\n", name)
		return
	}
	if len(args) != 1 {
		usage("checkout REF | checkout -b NAME")
		return
	}
	target := args[0]
	if r.merging {
		fail("merge in progress")
		return
	}
	if _, isBranch := r.branches[target]; isBranch {
		if !r.detached && r.head == target {
			fmt.Fprintf(out, "Already on '%s'\n", target)
			return
		}
		tree := map[string]string{}
		if id := r.branches[target]; id != "" {
			tree = r.commits[id].tree
		}
		if e := r.dirtyCheck(); e != "" {
			fail(e)
			return
		}
		if e := r.untrackedCheck(tree); e != "" {
			fail(e)
			return
		}
		r.switchTo(tree)
		r.head = target
		r.detached = false
		fmt.Fprintf(out, "Switched to branch '%s'\n", target)
		return
	}
	id, e := r.resolve(target)
	if e != "" {
		fail(e)
		return
	}
	tree := r.commits[id].tree
	if e := r.dirtyCheck(); e != "" {
		fail(e)
		return
	}
	if e := r.untrackedCheck(tree); e != "" {
		fail(e)
		return
	}
	r.switchTo(tree)
	r.detached = true
	r.detachedID = id
	fmt.Fprintf(out, "HEAD is now at %s %s\n", short(id), r.commits[id].msg)
}

func (r *Repo) reset(args []string) {
	if len(args) == 0 || args[0] != "--hard" || len(args) > 2 {
		usage("reset --hard [REF]")
		return
	}
	ref := "HEAD"
	if len(args) == 2 {
		ref = args[1]
	}
	if ref == "HEAD" && r.headID() == "" {
		fail("no commits yet")
		return
	}
	id, e := r.resolve(ref)
	if e != "" {
		fail(e)
		return
	}
	r.resetTo(id)
	fmt.Fprintf(out, "HEAD is now at %s %s\n", short(id), r.commits[id].msg)
}

func (r *Repo) merge(args []string) {
	if len(args) == 1 && args[0] == "--abort" {
		if !r.merging {
			fail("no merge in progress")
			return
		}
		r.resetTo(r.headID())
		fmt.Fprintln(out, "Merge aborted.")
		return
	}
	if len(args) != 1 {
		usage("merge BRANCH")
		return
	}
	if r.merging {
		fail("merge in progress")
		return
	}
	if r.headID() == "" {
		fail("no commits yet")
		return
	}
	name := args[0]
	other := r.branches[name]
	if other == "" {
		fail("unknown branch '" + name + "'")
		return
	}
	if e := r.dirtyCheck(); e != "" {
		fail(e)
		return
	}
	cur := r.headID()
	if r.ancestors(cur)[other] {
		fmt.Fprintln(out, "Already up to date.")
		return
	}
	if r.ancestors(other)[cur] {
		tree := r.commits[other].tree
		if e := r.untrackedCheck(tree); e != "" {
			fail(e)
			return
		}
		r.switchTo(tree)
		r.moveHead(other)
		fmt.Fprintln(out, "Fast-forward")
		return
	}

	// Merge base: common ancestor with greatest creation number.
	ancCur := r.ancestors(cur)
	ancOther := r.ancestors(other)
	baseTree := map[string]string{}
	bestSeq := -1
	for x := range ancCur {
		if ancOther[x] && r.commits[x].seq > bestSeq {
			bestSeq = r.commits[x].seq
			baseTree = r.commits[x].tree
		}
	}
	O := r.commits[cur].tree
	T := r.commits[other].tree
	B := baseTree

	seen := map[string]bool{}
	var names []string
	for _, m := range []map[string]string{B, O, T} {
		for n := range m {
			if !seen[n] {
				seen[n] = true
				names = append(names, n)
			}
		}
	}
	sort.Strings(names)

	newIndex := map[string]string{}
	override := map[string]string{}
	kinds := map[string]string{}
	for _, n := range names {
		bc, bok := B[n]
		oc, ook := O[n]
		tc, tok := T[n]
		switch {
		case eqFile(oc, ook, tc, tok):
			if ook {
				newIndex[n] = oc
			}
		case eqFile(oc, ook, bc, bok):
			if tok {
				newIndex[n] = tc
			}
		case eqFile(tc, tok, bc, bok):
			if ook {
				newIndex[n] = oc
			}
		case ook != tok:
			surv := oc
			if !ook {
				surv = tc
			}
			override[n] = surv
			kinds[n] = "modify/delete"
			if ook {
				newIndex[n] = oc
			}
		default:
			merged, clean := mergeLines(splitLines(bc), splitLines(oc), splitLines(tc), name)
			content := joinLines(merged)
			if clean {
				newIndex[n] = content
			} else {
				override[n] = content
				if bok {
					kinds[n] = "content"
				} else {
					kinds[n] = "add/add"
				}
				newIndex[n] = oc
			}
		}
	}

	// Untracked check over result names and working overrides.
	checkSet := map[string]bool{}
	for n := range newIndex {
		checkSet[n] = true
	}
	for n := range override {
		checkSet[n] = true
	}
	for _, n := range sortedKeys(checkSet) {
		if _, inOld := O[n]; inOld {
			continue
		}
		if _, inW := r.work[n]; inW {
			fail("untracked file would be overwritten: " + n)
			return
		}
	}

	// Apply.
	for n := range O {
		if _, ok := newIndex[n]; !ok {
			delete(r.work, n)
		}
	}
	for n, c := range newIndex {
		r.work[n] = c
	}
	for n, c := range override {
		r.work[n] = c
	}
	r.index = newIndex

	if len(kinds) == 0 {
		c := r.makeCommit(newIndex, []string{cur, other}, "Merge branch '"+name+"'")
		r.moveHead(c.id)
		fmt.Fprintln(out, "Merge made by the 'three-way' strategy.")
		fmt.Fprintln(out, r.commitLine(c))
		return
	}
	r.conflicts = map[string]bool{}
	for n := range kinds {
		r.conflicts[n] = true
	}
	r.merging = true
	r.mergeOther = other
	r.mergeBranch = name
	for _, n := range sortedKeys(kinds) {
		switch kinds[n] {
		case "modify/delete":
			fmt.Fprintf(out, "CONFLICT (modify/delete): %s\n", n)
		default:
			fmt.Fprintf(out, "CONFLICT (%s): Merge conflict in %s\n", kinds[n], n)
		}
	}
	fmt.Fprintln(out, "Automatic merge failed; fix conflicts and then commit the result.")
}

func (r *Repo) exec(cmd string, args []string, trimmed string) {
	switch cmd {
	case "rm":
		if len(args) == 0 {
			usage("rm FILE...")
			return
		}
		for _, n := range args {
			if _, ok := r.work[n]; !ok {
				fail("no such file: " + n)
				return
			}
			delete(r.work, n)
		}
	case "mv":
		if len(args) != 2 {
			usage("mv OLD NEW")
			return
		}
		c, ok := r.work[args[0]]
		if !ok {
			fail("no such file: " + args[0])
			return
		}
		delete(r.work, args[0])
		r.work[args[1]] = c
	case "cat":
		if len(args) != 1 {
			usage("cat FILE")
			return
		}
		c, ok := r.work[args[0]]
		if !ok {
			fail("no such file: " + args[0])
			return
		}
		fmt.Fprint(out, c)
	case "ls":
		names := sortedKeys(r.work)
		if len(names) == 0 {
			fmt.Fprintln(out, "(empty)")
		}
		for _, n := range names {
			fmt.Fprintln(out, n)
		}
	case "add":
		if len(args) == 0 {
			usage("add PATH...")
			return
		}
		for _, p := range args {
			if !r.addPath(p) {
				fail("pathspec '" + p + "' did not match any files")
				return
			}
		}
	case "status":
		r.status()
	case "commit":
		r.commit(strings.TrimSpace(trimmed[len(cmd):]))
	case "log":
		r.log(args)
	case "diff":
		r.diff(args)
	case "branch":
		r.branchCmd(args)
	case "tag":
		r.tagCmd(args)
	case "show":
		r.show(args)
	case "checkout":
		r.checkout(args)
	case "merge":
		r.merge(args)
	case "reset":
		r.reset(args)
	default:
		fail("unknown command '" + cmd + "'")
	}
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	raw := strings.Split(string(data), "\n")
	if len(raw) > 0 && raw[len(raw)-1] == "" {
		raw = raw[:len(raw)-1]
	}
	lines := make([]string, len(raw))
	for i, l := range raw {
		lines[i] = strings.TrimSuffix(l, "\r")
	}

	out = bufio.NewWriter(os.Stdout)
	defer out.Flush()

	r := newRepo()
	for i := 0; i < len(lines); {
		line := lines[i]
		i++
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || trimmed[0] == '#' {
			continue
		}
		fmt.Fprintln(out, "> "+strings.TrimRightFunc(line, unicode.IsSpace))
		fields := strings.Fields(line)
		cmd, args := fields[0], fields[1:]
		if cmd == "write" || cmd == "append" {
			if len(args) != 1 {
				usage(cmd + " FILE")
				continue
			}
			j := i
			for j < len(lines) && lines[j] != "." {
				j++
			}
			content := joinLines(lines[i:j])
			i = j
			if i < len(lines) {
				i++
			}
			if cmd == "write" {
				r.work[args[0]] = content
			} else {
				r.work[args[0]] += content
			}
			continue
		}
		r.exec(cmd, args, trimmed)
	}
}
