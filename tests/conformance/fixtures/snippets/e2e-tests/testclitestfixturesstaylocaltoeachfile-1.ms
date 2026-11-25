// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=tests/e2e/test_fixture_test.go:176 TestCLITestFixturesStayLocalToEachFile
import helper from "./other.ms"
// expect-error: MS2002 4:1 cannot find module ./other.ms (looked for other.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
