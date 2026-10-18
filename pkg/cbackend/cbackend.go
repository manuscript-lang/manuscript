// Package cbackend is a prototype that compiles a numeric subset of checked
// Manuscript functions to C. It keeps the language's checked Int arithmetic,
// list bounds and negative indexes, cancellation polls, and evaluation order.
//
// Subset: Int, Float and Bool scalars; non-generic records of those; Lists of
// any of those built and
// used inside one call; plain function calls, if, while, return, break and
// continue. Anything else leaves the function to the Go backend. Lists live in
// a per-call region that is freed when the entry function returns or faults.
package cbackend

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Entry is a compiled function whose signature is scalar, so Go can call it.
type Entry struct {
	Name    string // Manuscript function name
	CName   string // C entry symbol: ms_run_<name>
	Params  []Param
	Result  string // "Int", "Float", "Bool" or "Unit"
	Unified string
}

// Param is a scalar parameter of an entry.
type Param struct{ Name, Type string }

// Result is the generated C and the functions that were and were not compiled.
type Result struct {
	C       string
	Entries []Entry
	Skipped map[string]string
}

type compiler struct {
	program  *checker.Program
	skipped  map[string]string
	state    map[*syntax.Declaration]int // 0 unseen, 1 in progress, 2 compiled, 3 rejected
	names    map[*syntax.Declaration]string
	code     map[*syntax.Declaration]string
	order    []*syntax.Declaration
	lists    map[string]string // C list type name -> element C type
	listOrd  []string
	reason   map[*syntax.Declaration]string
	recurses map[*syntax.Declaration]bool
	decls    map[string]*syntax.Declaration
	recs     map[string]*record // checker type ID -> record
	recOrd   []*record
}

// record is a Manuscript record lowered to a C struct that lives in the call's
// region. Records are references, as in the Go backend.
type record struct {
	name   string
	fields []recordField
}

type recordField struct{ name, ctype string }

// Generate compiles every eligible function of the modules whose file name
// has the given prefix.
func Generate(program *checker.Program, filePrefix string) Result {
	c := &compiler{
		program: program, skipped: map[string]string{}, state: map[*syntax.Declaration]int{},
		names: map[*syntax.Declaration]string{}, code: map[*syntax.Declaration]string{},
		lists: map[string]string{}, reason: map[*syntax.Declaration]string{}, recurses: map[*syntax.Declaration]bool{},
		decls: map[string]*syntax.Declaration{}, recs: map[string]*record{},
	}
	var candidates []*syntax.Declaration
	for _, m := range program.Modules {
		if !strings.HasPrefix(m.File, filePrefix) || strings.HasPrefix(m.File, "@std/") || m.File == "std:prelude" {
			continue
		}
		for _, d := range m.Declarations {
			if d.Kind == syntax.KindFn && !d.Constant && len(d.TypeParams) == 0 && d.Receiver == nil {
				candidates = append(candidates, d)
				c.names[d] = "ms_" + sanitize(m.File) + "_" + d.Name
				c.decls[m.File+"\x00"+d.Name] = d
			}
		}
	}
	for _, d := range candidates {
		c.compile(d, 0)
	}
	var out strings.Builder
	out.WriteString(prelude)
	for _, r := range c.recOrd {
		fmt.Fprintf(&out, "typedef struct %s %s;\n", r.name, r.name)
	}
	for _, name := range c.listOrd {
		fmt.Fprintf(&out, "MS_LIST(%s, %s)\n", name, c.lists[name])
	}
	for _, r := range c.recOrd {
		fmt.Fprintf(&out, "struct %s {", r.name)
		for _, f := range r.fields {
			fmt.Fprintf(&out, " %s f_%s;", f.ctype, f.name)
		}
		out.WriteString(" };\n")
	}
	for _, d := range c.order {
		if c.state[d] == 2 {
			fmt.Fprintf(&out, "static %s;\n", c.signature(d))
		}
	}
	for _, d := range c.order {
		if c.state[d] == 2 {
			out.WriteString(c.assemble(d))
		}
	}
	var entries []Entry
	for _, d := range c.order {
		if c.state[d] != 2 {
			continue
		}
		if e, ok := c.entry(d); ok {
			entries = append(entries, e)
			out.WriteString(c.entryC(d, e))
		}
	}
	skipped := map[string]string{}
	for _, d := range candidates {
		if c.state[d] == 3 {
			skipped[d.Name] = c.reason[d]
		}
	}
	return Result{C: out.String(), Entries: entries, Skipped: skipped}
}

// assemble wraps d's body; a function in a recursion cycle counts its depth
// like the Go backend's Enter and Exit.
func (c *compiler) assemble(d *syntax.Declaration) string {
	if !c.recurses[d] {
		return c.signature(d) + " {\n" + c.code[d] + "}\n"
	}
	body := strings.Replace(c.signature(d), c.names[d]+"(", c.names[d]+"_body(", 1)
	var args []string
	for _, b := range c.program.ParameterBindings(d) {
		args = append(args, "v_"+sanitize(b.Name))
	}
	result, _ := c.ctype(c.resultType(d))
	call := c.names[d] + "_body(" + strings.Join(args, ", ") + ")"
	wrapper := "\tif (__builtin_expect(++ms_depth > MS_MAX_DEPTH, 0)) ms_raise(MS_DEPTH, 0, 0);\n"
	if result == "void" {
		wrapper += "\t" + call + ";\n\tms_depth--;\n"
	} else {
		wrapper += "\t" + result + " r = " + call + ";\n\tms_depth--;\n\treturn r;\n"
	}
	return "static inline " + body + " {\n" + c.code[d] + "}\n" + c.signature(d) + " {\n" + wrapper + "}\n"
}

func sanitize(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String()
}

// scalar reports the C type of Int, Float and Bool.
func scalar(t *checker.Type) (string, bool) {
	if t == nil {
		return "", false
	}
	switch t.ID {
	case "Int":
		return "int64_t", true
	case "Float":
		return "double", true
	case "Bool":
		return "bool", true
	}
	return "", false
}

// ctype returns the C type of t, registering list types.
func (c *compiler) ctype(t *checker.Type) (string, bool) {
	if s, ok := scalar(t); ok {
		return s, true
	}
	if t != nil && t.ID == "Unit" {
		return "void", true
	}
	if t != nil && t.ID == "@std/List" || t != nil && t.Name == "List" && len(t.Args) == 1 {
		elem, ok := c.ctype(t.Args[0])
		if !ok || elem == "void" {
			return "", false
		}
		name := "ms_list_" + mangle(elem)
		if _, seen := c.lists[name]; !seen {
			c.lists[name] = elem
			c.listOrd = append(c.listOrd, name)
		}
		return name + " *", true
	}
	if r := c.record(t); r != nil {
		return r.name + " *", true
	}
	return "", false
}

// record returns the C struct for a plain, non-generic record type, or nil.
func (c *compiler) record(t *checker.Type) *record {
	if t == nil || t.Def == nil || len(t.Args) != 0 || len(t.Def.Variables) != 0 || len(t.Def.Cases) != 0 || len(t.Def.Fields) == 0 || t.Def.Symbol == nil {
		return nil
	}
	if m := t.Def.Symbol.Module; strings.HasPrefix(m, "@std/") || strings.HasPrefix(m, "std:") {
		return nil
	}
	if r, ok := c.recs[t.ID]; ok {
		return r
	}
	r := &record{name: fmt.Sprintf("ms_rec_%s_%d", sanitize(t.Name), len(c.recOrd))}
	c.recs[t.ID] = r
	c.recOrd = append(c.recOrd, r)
	for _, f := range t.Def.Fields {
		ct, ok := c.ctype(f.Type)
		if !ok || ct == "void" {
			delete(c.recs, t.ID)
			reject("record %s field %s of type %v", t.Name, f.Name, f.Type)
		}
		r.fields = append(r.fields, recordField{f.Name, ct})
	}
	return r
}

func mangle(elem string) string {
	switch elem {
	case "int64_t":
		return "i64"
	case "double":
		return "f64"
	case "bool":
		return "bool"
	}
	return "L" + sanitize(strings.TrimSuffix(strings.TrimSpace(elem), "*"))
}

func (c *compiler) signature(d *syntax.Declaration) string {
	var params []string
	for _, b := range c.program.ParameterBindings(d) {
		t, _ := c.ctype(b.Type)
		params = append(params, t+" v_"+sanitize(b.Name))
	}
	if len(params) == 0 {
		params = []string{"void"}
	}
	result, _ := c.ctype(c.resultType(d))
	return result + " " + c.names[d] + "(" + strings.Join(params, ", ") + ")"
}

func (c *compiler) resultType(d *syntax.Declaration) *checker.Type {
	for _, m := range c.program.Modules {
		for _, x := range m.Declarations {
			if x == d {
				if s := c.program.Symbol(m.File, d.Name); s != nil && s.Type != nil {
					return s.Type.Result
				}
			}
		}
	}
	return nil
}

func (c *compiler) entry(d *syntax.Declaration) (Entry, bool) {
	e := Entry{Name: d.Name, CName: "ms_run_" + strings.TrimPrefix(c.names[d], "ms_")}
	for _, b := range c.program.ParameterBindings(d) {
		if _, ok := scalar(b.Type); !ok {
			return e, false
		}
		e.Params = append(e.Params, Param{Name: b.Name, Type: b.Type.ID})
	}
	rt := c.resultType(d)
	switch {
	case rt == nil:
		return e, false
	case rt.ID == "Unit":
		e.Result = "Unit"
	default:
		if _, ok := scalar(rt); !ok {
			return e, false
		}
		e.Result = rt.ID
	}
	return e, true
}

func (c *compiler) entryC(d *syntax.Declaration, e Entry) string {
	var params, args []string
	for i, b := range c.program.ParameterBindings(d) {
		t, _ := scalar(b.Type)
		params = append(params, fmt.Sprintf("%s p%d", t, i))
		args = append(args, fmt.Sprintf("p%d", i))
	}
	out, call := "", c.names[d]+"("+strings.Join(args, ", ")+")"
	if e.Result != "Unit" {
		t, _ := scalar(c.resultType(d))
		params = append(params, t+" *out")
		call = "*out = " + call
	}
	_ = out
	pl := strings.Join(append([]string{"volatile int *cancel"}, params...), ", ")
	return fmt.Sprintf("ms_fault %s(%s) {\n\tMS_ENTER(cancel);\n\tif (setjmp(jb) == 0) { %s; }\n\tMS_LEAVE();\n}\n", e.CName, pl, call)
}

type unsupported struct{ why string }

func (u unsupported) Error() string { return u.why }

func reject(format string, args ...any) { panic(unsupported{fmt.Sprintf(format, args...)}) }

// compile generates d, first compiling its callees. A function is rejected if
// any construct or callee is outside the subset.
func (c *compiler) compile(d *syntax.Declaration, depth int) bool {
	switch c.state[d] {
	case 1, 2:
		return true
	case 3:
		return false
	}
	c.state[d] = 1
	defer func() {
		if r := recover(); r != nil {
			u, ok := r.(unsupported)
			if !ok {
				panic(r)
			}
			c.state[d], c.reason[d] = 3, u.why
		}
	}()
	f := &fnGen{c: c, decl: d, vars: map[*checker.Binding]string{}}
	rt := c.resultType(d)
	if _, ok := c.ctype(rt); !ok {
		reject("unsupported result type %v", rt)
	}
	for _, b := range c.program.ParameterBindings(d) {
		if _, ok := c.ctype(b.Type); !ok {
			reject("unsupported parameter type %v", b.Type)
		}
		f.vars[b] = "v_" + sanitize(b.Name)
	}
	f.result = rt
	f.block(d.Body, 1)
	if rt.ID != "Unit" {
		f.line(1, "__builtin_unreachable();")
	}
	c.order = append(c.order, d)
	c.code[d] = f.sb.String()
	c.state[d] = 2
	return true
}

type fnGen struct {
	c      *compiler
	decl   *syntax.Declaration
	vars   map[*checker.Binding]string
	sb     strings.Builder
	serial int
	result *checker.Type
}

func (f *fnGen) line(indent int, format string, args ...any) {
	f.sb.WriteString(strings.Repeat("\t", indent))
	fmt.Fprintf(&f.sb, format, args...)
	f.sb.WriteByte('\n')
}

func (f *fnGen) tmp() string { f.serial++; return "t" + strconv.Itoa(f.serial) }

func (f *fnGen) info(e *syntax.Expression) *checker.Info {
	info := f.c.program.Info(e)
	if info == nil {
		reject("%s: unchecked expression", e.Pos)
	}
	return info
}

func (f *fnGen) block(stmts []*syntax.Statement, indent int) {
	for _, s := range stmts {
		f.stmt(s, indent)
	}
}

func (f *fnGen) stmt(s *syntax.Statement, in int) {
	switch s.Kind {
	case syntax.KindBind:
		if s.Pattern == nil || s.Pattern.Kind != syntax.KindName {
			reject("%s: destructuring binding", s.Pos)
		}
		b := f.c.program.PatternBinding(s.Pattern)
		if b == nil {
			f.expr(s.Value, in)
			return
		}
		t, ok := f.c.ctype(b.Type)
		if !ok {
			reject("%s: binding of type %v", s.Pos, b.Type)
		}
		v := f.expr(s.Value, in)
		name := fmt.Sprintf("v_%s_%d", sanitize(b.Name), len(f.vars))
		f.vars[b] = name
		f.line(in, "%s %s = %s;", t, name, v)
	case syntax.KindAssign:
		if s.Target != nil {
			f.fieldAssign(s, in)
			return
		}
		b := f.c.program.AssignedBinding(s.Value)
		name, ok := f.vars[b]
		if b == nil || !ok {
			reject("%s: assignment to unsupported binding", s.Pos)
		}
		f.line(in, "%s = %s;", name, f.expr(s.Value, in))
	case syntax.KindCall:
		f.expr(s.Value, in)
	case syntax.KindReturn:
		if s.Value == nil || s.Value.Kind == syntax.KindUnit {
			f.line(in, "return;")
			return
		}
		f.line(in, "return %s;", f.expr(s.Value, in))
	case syntax.KindBreak:
		f.line(in, "break;")
	case syntax.KindContinue:
		f.line(in, "continue;")
	case syntax.KindIf:
		if s.Pattern != nil {
			reject("%s: if let", s.Pos)
		}
		cond := f.expr(s.Value, in)
		f.line(in, "if (%s) {", cond)
		f.block(s.Body, in+1)
		if len(s.Else) > 0 {
			f.line(in, "} else {")
			f.block(s.Else, in+1)
		}
		f.line(in, "}")
	case syntax.KindWhile:
		tick := f.tmp()
		f.line(in, "{ uint32_t %s = 0;", tick)
		f.line(in, "for (;;) {")
		f.line(in+1, "MS_POLL(%s);", tick)
		cond := f.expr(s.Value, in+1)
		f.line(in+1, "if (!(%s)) break;", cond)
		f.block(s.Body, in+1)
		f.line(in, "} }")
	default:
		reject("%s: statement %s", s.Pos, s.Kind)
	}
}

var arithmetic = map[string]string{"+": "add", "-": "sub", "*": "mul", "/": "div", "%": "rem"}
var comparisons = map[string]bool{"<": true, "<=": true, ">": true, ">=": true, "==": true, "!=": true}

// expr emits the statements that compute e in source order and returns an
// operand that is a literal, variable or temporary.
func (f *fnGen) expr(e *syntax.Expression, in int) string {
	info := f.info(e)
	t := info.Type
	switch e.Kind {
	case syntax.KindNumber:
		if strings.HasSuffix(e.Text, "d") {
			reject("%s: Decimal literal", e.Pos)
		}
		if strings.ContainsAny(e.Text, ".eE") {
			v, err := strconv.ParseFloat(strings.ReplaceAll(e.Text, "_", ""), 64)
			if err != nil {
				reject("%s: float literal %q", e.Pos, e.Text)
			}
			lit := strconv.FormatFloat(v, 'g', 17, 64)
			if !strings.ContainsAny(lit, ".eIN") {
				lit += ".0"
			}
			return lit
		}
		return "INT64_C(" + strings.ReplaceAll(e.Text, "_", "") + ")"
	case syntax.KindBool:
		return e.Text
	case syntax.KindName:
		if info.Binding == nil {
			reject("%s: name %s is not a local", e.Pos, e.Text)
		}
		v, ok := f.vars[info.Binding]
		if !ok {
			reject("%s: unknown local %s", e.Pos, e.Text)
		}
		return v
	case syntax.KindUnary:
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && !strings.ContainsAny(e.Right.Text, ".eE") {
			return "(-INT64_C(" + strings.ReplaceAll(e.Right.Text, "_", "") + "))"
		}
		x := f.expr(e.Right, in)
		r := f.tmp()
		switch {
		case e.Text == "not":
			f.line(in, "bool %s = !%s;", r, x)
		case e.Text == "-" && t.ID == "Int":
			f.line(in, "int64_t %s = ms_neg(%s);", r, x)
		case e.Text == "-" && t.ID == "Float":
			f.line(in, "double %s = -%s;", r, x)
		default:
			reject("%s: unary %s", e.Pos, e.Text)
		}
		return r
	case syntax.KindBinary:
		return f.binary(e, in)
	case syntax.KindMember:
		obj, field := f.fieldOf(e, in)
		r := f.tmp()
		f.line(in, "%s %s = %s->f_%s;", f.fieldType(e), r, obj, field)
		return r
	case syntax.KindIndex:
		return f.listGet(f.expr(e.Left, in), f.expr(e.Right, in), f.info(e.Left).Type, in)
	case syntax.KindList:
		return f.listLiteral(e, info, in)
	case syntax.KindCall:
		return f.call(e, info, in)
	}
	reject("%s: expression %s", e.Pos, e.Kind)
	return ""
}

func (f *fnGen) binary(e *syntax.Expression, in int) string {
	if e.Text == "and" || e.Text == "or" {
		r := f.tmp()
		left := f.expr(e.Left, in)
		f.line(in, "bool %s = %s;", r, left)
		if e.Text == "and" {
			f.line(in, "if (%s) {", r)
		} else {
			f.line(in, "if (!%s) {", r)
		}
		right := f.expr(e.Right, in+1)
		f.line(in+1, "%s = %s;", r, right)
		f.line(in, "}")
		return r
	}
	lt := f.info(e.Left).Type
	a := f.expr(e.Left, in)
	b := f.expr(e.Right, in)
	r := f.tmp()
	if comparisons[e.Text] {
		if _, ok := scalar(lt); !ok {
			reject("%s: comparison of %v", e.Pos, lt)
		}
		f.line(in, "bool %s = %s %s %s;", r, a, e.Text, b)
		return r
	}
	switch lt.ID {
	case "Int":
		op, ok := arithmetic[e.Text]
		if !ok {
			reject("%s: Int operator %s", e.Pos, e.Text)
		}
		f.line(in, "int64_t %s = ms_%s(%s, %s);", r, op, a, b)
	case "Float":
		if e.Text != "+" && e.Text != "-" && e.Text != "*" && e.Text != "/" {
			reject("%s: Float operator %s", e.Pos, e.Text)
		}
		f.line(in, "double %s = %s %s %s;", r, a, e.Text, b)
	default:
		reject("%s: operator %s on %v", e.Pos, e.Text, lt)
	}
	return r
}

// fieldOf evaluates the record operand of a field access and returns it with
// the field name.
func (f *fnGen) fieldOf(m *syntax.Expression, in int) (string, string) {
	lt := f.info(m.Left).Type
	r := f.c.record(lt)
	if r == nil {
		reject("%s: member %s on %v", m.Pos, m.Text, lt)
	}
	for _, fld := range r.fields {
		if fld.name == m.Text {
			return f.expr(m.Left, in), m.Text
		}
	}
	reject("%s: unknown field %s", m.Pos, m.Text)
	return "", ""
}

func (f *fnGen) fieldType(m *syntax.Expression) string {
	t, ok := f.c.ctype(f.info(m).Type)
	if !ok || t == "void" {
		reject("%s: field type %v", m.Pos, f.info(m).Type)
	}
	return t
}

func (f *fnGen) fieldAssign(s *syntax.Statement, in int) {
	if s.Target.Kind != syntax.KindMember {
		reject("%s: assignment target %s", s.Pos, s.Target.Kind)
	}
	obj, field := f.fieldOf(s.Target, in)
	f.line(in, "%s->f_%s = %s;", obj, field, f.expr(s.Value, in))
}

func (f *fnGen) recordNew(e *syntax.Expression, info *checker.Info, r *record, in int) string {
	if len(info.Arguments) != len(r.fields) {
		reject("%s: defaulted record fields", e.Pos)
	}
	slot := map[string]int{}
	for i, fld := range r.fields {
		slot[fld.name] = i
	}
	values := make([]string, len(r.fields))
	for _, a := range info.Arguments {
		i, ok := slot[a.Name]
		if !ok {
			reject("%s: record field %s", e.Pos, a.Name)
		}
		values[i] = f.expr(a.Value, in)
	}
	v := f.tmp()
	f.line(in, "%s *%s = ms_ralloc(sizeof *%s);", r.name, v, v)
	for i, fld := range r.fields {
		f.line(in, "%s->f_%s = %s;", v, fld.name, values[i])
	}
	return v
}

func (f *fnGen) listGet(list, index string, lt *checker.Type, in int) string {
	elem, ok := f.c.ctype(lt.Args[0])
	name, _ := f.c.ctype(lt)
	if !ok {
		reject("list element type %v", lt.Args[0])
	}
	r := f.tmp()
	f.line(in, "%s %s = %s_get(%s, %s);", elem, r, strings.TrimSpace(strings.TrimSuffix(name, "*")), list, index)
	return r
}

func (f *fnGen) listLiteral(e *syntax.Expression, info *checker.Info, in int) string {
	name, ok := f.c.ctype(info.Type)
	if !ok {
		reject("%s: list of %v", e.Pos, info.Type)
	}
	base := strings.TrimSpace(strings.TrimSuffix(name, "*"))
	var items []string
	for _, el := range e.Elements {
		items = append(items, f.expr(el, in))
	}
	r := f.tmp()
	f.line(in, "%s *%s = %s_new(%d);", base, r, base, len(items))
	for _, v := range items {
		f.line(in, "%s_append(%s, %s);", base, r, v)
	}
	return r
}

func (f *fnGen) call(e *syntax.Expression, info *checker.Info, in int) string {
	switch {
	case info.Constructor != nil:
		if info.Constructor.Name == "List" && len(info.Arguments) == 0 {
			name, ok := f.c.ctype(info.Type)
			if !ok {
				reject("%s: list of %v", e.Pos, info.Type)
			}
			base := strings.TrimSpace(strings.TrimSuffix(name, "*"))
			r := f.tmp()
			f.line(in, "%s *%s = %s_new(0);", base, r, base)
			return r
		}
		if r := f.c.record(info.Constructor); r != nil {
			return f.recordNew(e, info, r, in)
		}
		reject("%s: constructor %v", e.Pos, info.Constructor)
	case info.Symbol != nil:
		return f.symbolCall(e, info, in)
	case info.Method != nil:
		return f.listMethod(e, info, in)
	}
	reject("%s: call", e.Pos)
	return ""
}

func (f *fnGen) symbolCall(e *syntax.Expression, info *checker.Info, in int) string {
	s := info.Symbol
	if s.Native != "" || s.Decl == nil || s.Kind != "fn" {
		reject("%s: call of %s", e.Pos, s.Name)
	}
	if _, known := f.c.names[s.Decl]; !known {
		reject("%s: call of %s outside the compiled modules", e.Pos, s.Name)
	}
	params := f.c.program.ParameterBindings(s.Decl)
	if len(info.Arguments) != len(params) {
		reject("%s: defaulted arguments", e.Pos)
	}
	slot := map[string]int{}
	for i, p := range params {
		slot[p.Name] = i
	}
	values := make([]string, len(params))
	for _, a := range info.Arguments {
		i, ok := slot[a.Name]
		if !ok {
			reject("%s: argument %s", e.Pos, a.Name)
		}
		values[i] = f.expr(a.Value, in)
	}
	if f.c.state[s.Decl] == 1 {
		f.c.recurses[s.Decl] = true
	} else if !f.c.compile(s.Decl, 0) {
		reject("%s: callee %s is not compiled: %s", e.Pos, s.Name, f.c.reason[s.Decl])
	}
	rt, _ := f.c.ctype(info.Type)
	call := f.c.names[s.Decl] + "(" + strings.Join(values, ", ") + ")"
	if rt == "void" {
		f.line(in, "%s;", call)
		return "0"
	}
	r := f.tmp()
	f.line(in, "%s %s = %s;", rt, r, call)
	return r
}

func (f *fnGen) listMethod(e *syntax.Expression, info *checker.Info, in int) string {
	member := e.Left
	if member.Kind != syntax.KindMember {
		reject("%s: call of a non-member", e.Pos)
	}
	recv := f.info(member.Left).Type
	if recv == nil || recv.Name != "List" || len(recv.Args) != 1 {
		if member.Text == "to_float" && recv != nil && recv.ID == "Int" {
			x := f.expr(member.Left, in)
			r := f.tmp()
			f.line(in, "double %s = (double)%s;", r, x)
			return r
		}
		reject("%s: method %s on %v", e.Pos, member.Text, recv)
	}
	name, ok := f.c.ctype(recv)
	if !ok {
		reject("%s: list of %v", e.Pos, recv.Args[0])
	}
	base := strings.TrimSpace(strings.TrimSuffix(name, "*"))
	list := f.expr(member.Left, in)
	var args []string
	for _, a := range info.Arguments {
		args = append(args, f.expr(a.Value, in))
	}
	switch member.Text {
	case "get":
		if len(args) != 1 {
			reject("%s: get with a default", e.Pos)
		}
		return f.listGet(list, args[0], recv, in)
	case "set":
		f.line(in, "%s_set(%s, %s, %s);", base, list, args[0], args[1])
		return list
	case "append":
		f.line(in, "%s_append(%s, %s);", base, list, args[0])
		return list
	case "length":
		r := f.tmp()
		f.line(in, "int64_t %s = %s->n;", r, list)
		return r
	}
	reject("%s: list method %s", e.Pos, member.Text)
	return ""
}

const prelude = `// Generated by the Manuscript C backend prototype.
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

typedef struct { int code; int64_t a, b; } ms_fault;
static __thread jmp_buf *ms_jmp;
static __thread ms_fault ms_f;
static __thread volatile int *ms_cancel;
static __thread void **ms_arena;
static __thread int64_t ms_arena_n, ms_arena_cap, ms_depth;
#define MS_MAX_DEPTH 200000

enum { MS_OVERFLOW = 1, MS_CANCELLED, MS_DIV, MS_REM, MS_GET, MS_SET, MS_DEPTH };

static __attribute__((noreturn, cold, noinline)) void ms_raise(int code, int64_t a, int64_t b) {
	ms_f.code = code; ms_f.a = a; ms_f.b = b;
	longjmp(*ms_jmp, 1);
}
static inline int64_t ms_add(int64_t a, int64_t b) { int64_t r; if (__builtin_expect(__builtin_add_overflow(a, b, &r), 0)) ms_raise(MS_OVERFLOW, 0, 0); return r; }
static inline int64_t ms_sub(int64_t a, int64_t b) { int64_t r; if (__builtin_expect(__builtin_sub_overflow(a, b, &r), 0)) ms_raise(MS_OVERFLOW, 0, 0); return r; }
static inline int64_t ms_mul(int64_t a, int64_t b) { int64_t r; if (__builtin_expect(__builtin_mul_overflow(a, b, &r), 0)) ms_raise(MS_OVERFLOW, 0, 0); return r; }
static inline int64_t ms_neg(int64_t a) { if (__builtin_expect(a == INT64_MIN, 0)) ms_raise(MS_OVERFLOW, 0, 0); return -a; }
static inline int64_t ms_div(int64_t a, int64_t b) { if (__builtin_expect(b == 0 || (a == INT64_MIN && b == -1), 0)) ms_raise(MS_DIV, a, b); return a / b; }
static inline int64_t ms_rem(int64_t a, int64_t b) { if (__builtin_expect(b == 0, 0)) ms_raise(MS_REM, a, b); if (b == -1) return 0; return a % b; }
static inline void ms_poll(void) { if (__builtin_expect(*ms_cancel != 0, 0)) ms_raise(MS_CANCELLED, 0, 0); }
#define MS_POLL(t) do { if (__builtin_expect(((++(t)) & 63) == 0, 0)) ms_poll(); } while (0)

static void ms_track(void *p) {
	if (ms_arena_n == ms_arena_cap) { ms_arena_cap = ms_arena_cap ? ms_arena_cap * 2 : 64; ms_arena = realloc(ms_arena, ms_arena_cap * sizeof(void *)); }
	ms_arena[ms_arena_n++] = p;
}
static __thread char **ms_chunks;
static __thread int64_t ms_chunk_n, ms_chunk_cap;
static __thread char *ms_bump, *ms_bump_end;
static void *ms_ralloc(size_t n) {
	n = (n + 15) & ~(size_t)15;
	if (__builtin_expect(ms_bump + n > ms_bump_end, 0)) {
		size_t sz = n > 65536 ? n : 65536;
		if (ms_chunk_n == ms_chunk_cap) { ms_chunk_cap = ms_chunk_cap ? ms_chunk_cap * 2 : 16; ms_chunks = realloc(ms_chunks, ms_chunk_cap * sizeof(char *)); }
		ms_bump = malloc(sz); ms_bump_end = ms_bump + sz; ms_chunks[ms_chunk_n++] = ms_bump;
	}
	void *p = ms_bump; ms_bump += n; return p;
}
static void ms_free_all(void) {
	for (int64_t i = 0; i < ms_arena_n; i++) { free(((void **)ms_arena[i])[0]); free(ms_arena[i]); }
	ms_arena_n = 0;
	for (int64_t i = 0; i < ms_chunk_n; i++) free(ms_chunks[i]);
	ms_chunk_n = 0; ms_bump = ms_bump_end = 0;
}

#define MS_LIST(NAME, T) \
typedef struct { T *p; int64_t n, cap; } NAME; \
static NAME *NAME##_new(int64_t cap) { NAME *l = malloc(sizeof *l); l->p = cap ? malloc(cap * sizeof(T)) : 0; l->n = 0; l->cap = cap; ms_track(l); return l; } \
static __attribute__((noinline)) void NAME##_grow(NAME *l) { l->cap = l->cap ? l->cap * 2 : 8; l->p = realloc(l->p, l->cap * sizeof(T)); } \
static inline void NAME##_append(NAME *l, T v) { if (__builtin_expect(l->n == l->cap, 0)) NAME##_grow(l); l->p[l->n++] = v; } \
static __attribute__((noinline, cold)) int64_t NAME##_index(NAME *l, int64_t i, int code) { int64_t j = i < 0 ? i + l->n : i; if (j < 0 || j >= l->n) ms_raise(code, i, l->n); return j; } \
static inline T NAME##_get(NAME *l, int64_t i) { if (__builtin_expect((uint64_t)i < (uint64_t)l->n, 1)) return l->p[i]; return l->p[NAME##_index(l, i, MS_GET)]; } \
static inline void NAME##_set(NAME *l, int64_t i, T v) { if (__builtin_expect((uint64_t)i < (uint64_t)l->n, 1)) { l->p[i] = v; return; } l->p[NAME##_index(l, i, MS_SET)] = v; }

#define MS_ENTER(c) jmp_buf jb; ms_jmp = &jb; ms_cancel = (c); ms_f.code = 0; ms_depth = 0
#define MS_LEAVE() ms_free_all(); return ms_f
`
