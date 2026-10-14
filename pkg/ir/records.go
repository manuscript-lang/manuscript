package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

// Record retains main's typed record layout and the runtime Struct ABI.
// Standard/generic records continue through their existing Record boundary.
type Record struct {
	Name, Key string
	Fields    []RecordField
}
type RecordField struct {
	Name, Primitive string
	Type            *checker.Type
}

func (r *Record) Field(name string) *RecordField {
	for i := range r.Fields {
		if r.Fields[i].Name == name {
			return &r.Fields[i]
		}
	}
	return nil
}

type FieldUse struct {
	Record   *Record
	Field    *RecordField
	Receiver Edge
}

func (p *Program) resolveRecords() {
	p.Records = map[string]*Record{}
	p.Fields = map[*syntax.Expression]*FieldUse{}
	for _, module := range p.checked.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindRecord {
				continue
			}
			s := p.checked.Symbol(module.File, d.Name)
			if s == nil || s.Type == nil || s.Native != "" || len(s.Variables) != 0 || strings.HasPrefix(s.Type.ID, "@std/") {
				continue
			}
			r := &Record{Name: "record_" + s.ID, Key: checker.TypeKey(s.Type)}
			for _, f := range checker.Fields(s.Type) {
				r.Fields = append(r.Fields, RecordField{Name: f.Name, Primitive: Primitive(f.Type), Type: f.Type})
			}
			p.Records[r.Key] = r
			p.RecordOrder = append(p.RecordOrder, r)
		}
	}
	resolve := func(e *syntax.Expression) {
		if e == nil || e.Kind != syntax.KindMember {
			return
		}
		left := p.checked.Info(e.Left)
		if left == nil {
			return
		}
		r := p.Records[checker.TypeKey(left.Type)]
		if r == nil {
			return
		}
		if f := r.Field(e.Text); f != nil {
			p.Fields[e] = &FieldUse{Record: r, Field: f, Receiver: Use(p.checked, e.Left, nil)}
		}
	}
	for e := range p.checked.Expressions() {
		resolve(e)
	}
	for _, module := range p.checked.Modules {
		for _, d := range module.Declarations {
			syntax.Visitor{Statement: func(s *syntax.Statement) { resolve(s.Target) }}.Walk(d)
		}
	}
}
