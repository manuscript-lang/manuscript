package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// nativeReceiverAvailable applies explicit requirements on the checked receiver.
// For example, equality search requires Equal, join requires List[String], and
// to_set requires Hashable, without strengthening List's element requirements.
func nativeReceiverAvailable(c *checker, receiver *Type, name string) bool {
	sub := substitution(receiver)
	for _, requirement := range standardReceiverRequirements[receiver.ID+"/"+name] {
		actual := sub[requirement.Variable.ID]
		if requirement.Constraint.Kind == "contract" {
			if !c.satisfies(actual, requirement.Constraint) {
				return false
			}
		} else if !Same(actual, requirement.Constraint) {
			return false
		}
	}
	return true
}

// nativeCallable resolves native operations before generic specialization. Only
// pinned standard declarations introduce method variables; user contracts retain
// their existing nongeneric operation grammar.
func (c *checker) nativeCallable(e *syntax.Expression) *Info {
	member := e
	if e.Kind == syntax.KindApply {
		member = e.Left
	}
	if member.Kind != syntax.KindMember || c.typeExpression(member.Left) != nil {
		return nil
	}
	receiver := c.expression(member.Left, nil)
	if invalidType(receiver.Type) {
		return &Info{Type: primitive("<invalid>")}
	}
	if receiver.Type.Kind == syntax.KindRecord && member.Text != "to_string" {
		for _, field := range Fields(receiver.Type) {
			if field.Name == member.Text {
				return nil
			}
		}
	}
	methods := c.methods(receiver.Type, member.Text)
	// Implementations have already specialized their receiver variables. They
	// dispatch through the contract, rather than native receiver operations.
	if len(methods) != 1 || methods[0].Contract != nil || methods[0].Native == "" || methods[0].Native == "contract" {
		return nil
	}
	m := methods[0]
	info := &Info{Type: m.Type, Method: m, Native: m.Native, NoReturn: receiver.NoReturn}
	setInfo(member, info)
	return info
}

func (c *checker) specializeNativeCall(e *syntax.Expression, info *Info, expected *Type) {
	vars := info.Method.Variables
	context := &callInferenceContext{result: info.Type.Result, expected: expected, pos: e.Pos}
	var supplied []*Type
	if e.Left.Kind == syntax.KindApply {
		supplied = c.resolveArguments(e.Left.Types)
	} else if len(vars) > 0 {
		sub := map[string]*Type{}
		c.inferArguments(functionArguments(e.Args, info.Type.Params), info.Type.Params, vars, sub, context)
		for _, v := range vars {
			supplied = append(supplied, sub[v.ID])
		}
	}
	copy := *info
	if len(vars) > 0 || e.Left.Kind == syntax.KindApply {
		copy.Type = c.specialize(info.Type, vars, supplied, e.Pos, calleeName(e.Left))
	}
	if context.conflict {
		copy.Type.Result = primitive("<invalid>")
	}
	setInfo(e.Left, &copy)
	*info = copy
}
