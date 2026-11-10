const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

const workflow = fs.readFileSync(path.resolve(__dirname, '../../.github/workflows/cicd.yml'), 'utf8');
const due = workflow.split('\n  due:\n')[1].split('\n  rust:\n')[0];
const script = due.match(/        run: \|\n((?:          .*\n|\n)+)/)[1]
  .replace(/^          /gm, '');
const pages = workflow.split('\n  pages:\n')[1].match(/    if: \$\{\{ (.*) \}\}/)[1];

function scheduled({ event = 'schedule', previousSchedule = '', previousManual = '' } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'manuscript-ci-'));
  const output = path.join(directory, 'output');
  try {
    // Model gh's server-side event filter. A partial manual run is newer than the
    // last full scheduled run. The real workflow shell must request schedule only.
    const mock = `gh() {
      local event=''
      while [ "$#" -gt 0 ]; do
        if [ "$1" = --event ]; then shift; event="$1"; fi
        shift
      done
      if [ "$event" = schedule ]; then
        printf '%s\\n' "$PREVIOUS_SCHEDULE"
      else
        printf '%s\\n' "$PREVIOUS_MANUAL"
      fi
    }\n`;
    const result = spawnSync('bash', ['-euo', 'pipefail', '-c', mock + script], {
      encoding: 'utf8',
      env: {
        ...process.env,
        EVENT: event,
        GITHUB_REPOSITORY: 'manuscript-lang/manuscript',
        GITHUB_RUN_ID: '123',
        GITHUB_SHA: 'current',
        GITHUB_OUTPUT: output,
        PREVIOUS_SCHEDULE: previousSchedule,
        PREVIOUS_MANUAL: previousManual,
      },
    });
    assert.equal(result.status, 0, result.stderr || String(result.error || ''));
    return fs.readFileSync(output, 'utf8').trim();
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function deploy({ event = 'workflow_dispatch', platform = 'all', branch = 'main', run = true, cancelled = false } = {}) {
  return vm.runInNewContext(pages, {
    cancelled: () => cancelled,
    needs: { due: { outputs: { run: String(run) } } },
    github: { event_name: event, ref: `refs/heads/${branch}`, event: { repository: { default_branch: 'main' } } },
    inputs: { os: platform },
    format: (pattern, value) => pattern.replace('{0}', value),
  });
}

test('a manual partial run never suppresses the scheduled full matrix', () => {
  assert.equal(scheduled({ previousManual: 'current' }), 'run=true');
  assert.equal(scheduled({ previousSchedule: 'older', previousManual: 'current' }), 'run=true');
});

test('a prior scheduled run at the same commit still avoids duplicate full matrices', () => {
  assert.equal(scheduled({ previousSchedule: 'current', previousManual: 'older' }), 'run=false');
});

test('manual and pull-request runs are never deduplicated', () => {
  for (const event of ['workflow_dispatch', 'pull_request', 'merge_group']) {
    assert.equal(scheduled({ event, previousSchedule: 'current', previousManual: 'current' }), 'run=true');
  }
});

test('Pages deploys only for a main run whose selected platform builds the book', () => {
  for (const platform of ['all', 'linux']) assert.equal(deploy({ platform }), true);
  for (const platform of ['darwin', 'windows']) assert.equal(deploy({ platform }), false);
  assert.equal(deploy({ event: 'schedule', platform: '' }), true);
});

test('Pages does not deploy for pull requests, other branches, skipped or cancelled runs', () => {
  assert.equal(deploy({ event: 'pull_request' }), false);
  assert.equal(deploy({ branch: 'release-fix' }), false);
  assert.equal(deploy({ run: false }), false);
  assert.equal(deploy({ cancelled: true }), false);
});
