package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

func (c *checker) checkTestFixture(module *syntax.Module) {
	hasTests := false
	for _, d := range module.Declarations {
		if d.Kind == syntax.KindTest {
			hasTests = true
			break
		}
	}
	if !hasTests {
		return
	}
	factory := c.names["make_fixture"]
	if factory == nil || factory.Module != module.File {
		return
	}
	if factory.Kind != syntax.KindFn || factory.Decl == nil || factory.Decl.Constant || len(factory.Variables) != 0 || len(factory.Type.Params) != 0 {
		c.error(factory.Decl.Pos, "type", "make_fixture must be a nongeneric zero-argument function; declare fn make_fixture() ConcreteFixture")
		return
	}
	result := factory.Type.Result
	if result == nil || (result.Kind != syntax.KindRecord && result.Kind != "alternative") || !c.implements(result, standard("TestHooks")) {
		c.error(factory.Decl.Pos, "type", "make_fixture must return a concrete type implementing @std/testing.ms TestHooks; return your fixture type and add impl TestHooks for it")
		return
	}
	c.TestFixtures[module.File] = &TestFixture{Factory: factory, Type: result, Hooks: standard("TestHooks")}
}
