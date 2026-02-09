// Test Runner

interface TestCase {
  description: string;
  fn: () => Promise<void>;
}

interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
}

const tests: TestCase[] = [];

export function test(description: string, fn: () => Promise<void>): void {
  tests.push({ description, fn });
}

export function getTestCount(): number {
  return tests.length;
}

export function clearTests(): void {
  tests.length = 0;
}

export async function runTests(): Promise<{ passed: number; failed: number }> {
  let passed = 0;
  let failed = 0;

  for (const t of tests) {
    try {
      await t.fn();
      console.log(`✓ ${t.description}`);
      passed++;
    } catch (e) {
      console.error(`✗ ${t.description}`);
      console.error(`  ${e}`);
      failed++;
    }
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  return { passed, failed };
}

export async function runTestsWithResults(): Promise<TestResult[]> {
  const results: TestResult[] = [];

  for (const t of tests) {
    try {
      await t.fn();
      results.push({ name: t.description, passed: true });
    } catch (e: unknown) {
      results.push({ name: t.description, passed: false, error: e instanceof Error ? e.message : String(e) });
    }
  }

  return results;
}
