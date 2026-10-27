# conform: tags=formatter,modules,parser,records,stdlib-testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:12 TestFileFixtureContracts
from "@std/test.ms" import TestHooks

type State:
    value: Int
