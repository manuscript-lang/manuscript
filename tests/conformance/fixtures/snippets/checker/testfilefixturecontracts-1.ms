# conform: tags=diagnostics,modules,records,stdlib-testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:12 TestFileFixtureContracts
import TestHooks from "@std/test/test.ms"

type State:
    value: Int
