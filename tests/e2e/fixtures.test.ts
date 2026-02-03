// E2E tests using .ms fixture files
import { runFixtureTests } from "./fixture-runner";
import * as path from "node:path";

const fixtureDir = path.join(import.meta.dir, "fixtures");

runFixtureTests(fixtureDir, "E2E Fixture Tests");
