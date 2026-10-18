const DAY = 24 * 60 * 60 * 1000;

function selectArtifacts(artifacts, completedRunIds, now = Date.now()) {
  const completed = artifacts.filter((artifact) =>
    completedRunIds.has(artifact.workflow_run?.id) &&
    Number.isFinite(Date.parse(artifact.created_at)),
  );
  const newest = new Map();
  for (const artifact of completed) {
    const key = artifact.name.replace(/[-_][a-f0-9]{40}$/i, '');
    const previous = newest.get(key);
    if (!previous || Date.parse(artifact.created_at) > Date.parse(previous.created_at) ||
        (artifact.created_at === previous.created_at && artifact.id > previous.id)) {
      newest.set(key, artifact);
    }
  }
  return completed.filter((artifact) => {
    const key = artifact.name.replace(/[-_][a-f0-9]{40}$/i, '');
    return now - Date.parse(artifact.created_at) >= DAY || newest.get(key).id !== artifact.id;
  });
}

async function run({ github, context, core, dryRun = true }) {
  const repo = context.repo;
  const artifacts = await github.paginate(github.rest.actions.listArtifactsForRepo, {
    ...repo, per_page: 100,
  });
  const completed = new Set();
  for (const runId of new Set(artifacts.map((artifact) => artifact.workflow_run?.id).filter(Boolean))) {
    try {
      const { data } = await github.rest.actions.getWorkflowRun({ ...repo, run_id: runId });
      if (data.status === 'completed') completed.add(runId);
    } catch (error) {
      core.warning(`Cannot inspect run ${runId}; preserving its artifacts: ${error.message}`);
    }
  }
  const candidates = selectArtifacts(artifacts, completed);
  let removed = 0;
  let bytes = 0;
  for (const artifact of candidates) {
    if (!dryRun) {
      // Recheck immediately before deletion: a completed run may have been rerun.
      const { data } = await github.rest.actions.getWorkflowRun({
        ...repo, run_id: artifact.workflow_run.id,
      });
      if (data.status !== 'completed') continue;
      try {
        await github.rest.actions.deleteArtifact({ ...repo, artifact_id: artifact.id });
      } catch (error) {
        if (error.status !== 404) throw error;
      }
    }
    removed += 1;
    bytes += artifact.size_in_bytes;
    core.info(`${dryRun ? 'Would delete' : 'Deleted'} artifact ${artifact.id}: ${artifact.name}`);
  }
  await core.summary.addHeading('Artifact storage maintenance')
    .addRaw(`${dryRun ? 'Dry run' : 'Cleanup'}: ${removed} artifacts, ${(bytes / 1024 ** 3).toFixed(2)} GiB. ` +
      'Only completed runs are eligible. Release assets and caches are not modified.')
    .write();
}

module.exports = { selectArtifacts, run };
