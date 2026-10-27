# conform: tags=diagnostics,modules,records,stdlib-testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:12 TestFileFixtureContracts
from "@std/test.ms" import TestHooks

type State:
    value: Int
