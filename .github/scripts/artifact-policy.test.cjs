const assert = require('node:assert/strict');
const test = require('node:test');
const { selectArtifacts, run } = require('./artifact-policy.cjs');
const now = Date.parse('2026-10-19T12:00:00Z');
const artifact = (id, name, hours, runId = id) => ({
  id, name, created_at: new Date(now - hours * 3600000).toISOString(),
  size_in_bytes: 10, workflow_run: { id: runId },
});
test('retains the newest completed artifact and removes superseded copies', () => {
  assert.deepEqual(selectArtifacts([artifact(1, 'windows', 3), artifact(2, 'windows', 1)], new Set([1, 2]), now).map(a => a.id), [1]);
});
test('expires artifacts at 24 hours even without a newer copy', () => {
  assert.deepEqual(selectArtifacts([artifact(1, 'old', 24), artifact(2, 'recent', 23)], new Set([1, 2]), now).map(a => a.id), [1]);
});
test('protects active runs and does not use their uploads to replace completed copies', () => {
  const list = [artifact(1, 'windows', 2), artifact(2, 'windows', 1), artifact(3, 'active', 48)];
  assert.deepEqual(selectArtifacts(list, new Set([1]), now), []);
});
test('groups commit-suffixed artifacts by platform without mixing platforms', () => {
  const list = [artifact(1, `Windows-${'a'.repeat(40)}`, 3), artifact(2, `Windows-${'b'.repeat(40)}`, 1), artifact(3, `macOS-${'c'.repeat(40)}`, 2)];
  assert.deepEqual(selectArtifacts(list, new Set([1, 2, 3]), now).map(a => a.id), [1]);
});
test('handles pagination output order, equal timestamps and invalid metadata conservatively', () => {
  const list = [artifact(3, 'windows', 1), artifact(2, 'windows', 1), { id: 4, name: 'bad', created_at: 'invalid', workflow_run: { id: 4 } }];
  assert.deepEqual(selectArtifacts(list, new Set([2, 3, 4]), now).map(a => a.id), [2]);
});
function fixture(dryRun, rerunning = false) {
  const deleted = [];
  let reads = 0;
  const artifacts = [{ ...artifact(1, 'old', 48), created_at: new Date(Date.now() - 48 * 3600000).toISOString() }];
  const actions = {
    listArtifactsForRepo() {},
    getWorkflowRun: async () => ({ data: { status: rerunning && ++reads > 1 ? 'in_progress' : 'completed' } }),
    deleteArtifact: async (args) => deleted.push(args),
  };
  const summary = { addHeading() { return this; }, addRaw() { return this; }, async write() {} };
  return { deleted, args: { github: { paginate: async () => artifacts, rest: { actions } }, context: { repo: { owner: 'owner', repo: 'repo' } }, core: { info() {}, warning() {}, summary }, dryRun } };
}
test('dry run never deletes and real cleanup uses only the current repository', async () => {
  const dry = fixture(true);
  await run(dry.args);
  assert.equal(dry.deleted.length, 0);
  const real = fixture(false);
  await run(real.args);
  assert.deepEqual(real.deleted, [{ owner: 'owner', repo: 'repo', artifact_id: 1 }]);
});
test('preserves artifacts when their run restarts before deletion', async () => {
  const active = fixture(false, true);
  await run(active.args);
  assert.equal(active.deleted.length, 0);
});
