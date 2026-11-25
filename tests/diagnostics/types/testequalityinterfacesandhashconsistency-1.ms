// conform: tags=control-flow,diagnostics,formatter,interfaces,maps,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/stdlib_revamp_test.go:15 TestEqualityInterfacesAndHashConsistency
type Key {
	id Int
}

fn Key.equals(other Key) Bool => return true

fn keys() Map[Key, Int] => return Map[Key, Int]()
// expect-error: MS3021 10:35 Key does not satisfy Hashable; give Key the methods Hashable declares, or use a type that implements it
// expect-error: MS3021 10:11 Key does not satisfy Hashable; give Key the methods Hashable declares, or use a type that implements it
