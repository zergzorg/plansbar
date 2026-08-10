import { scanPlansRoot } from './planScanner.js';
import { homedir } from 'node:os';
import path from 'node:path';

const root = process.env.PLANSBAR_ROOT ?? path.join(homedir(), 'Code');
const staleDays = Number(process.env.PLANSBAR_STALE_DAYS ?? 30);
const snapshot = scanPlansRoot({ root, staleDays });

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(snapshot, null, 2));
} else {
  console.log(`PlansBar Dashboard scan`);
  console.log(`Root: ${snapshot.root}`);
  console.log(`Generated: ${snapshot.generatedAt}`);
  console.log(
    `Repos: ${snapshot.totals.repositories}, tasks: ${snapshot.totals.total}, active: ${snapshot.totals.active}, backlog: ${snapshot.totals.backlog}, completed: ${snapshot.totals.completed}`
  );
  console.log(
    `Health: stale active ${snapshot.totals.stale_active}, metadata issues ${snapshot.totals.metadata_issues}, validation issues ${snapshot.totals.validation_issues}, completion issues ${snapshot.totals.completion_issues}`
  );

  for (const repo of snapshot.repositories) {
    console.log(
      `- ${repo.name}: active ${repo.counts.active}, backlog ${repo.counts.backlog}, completed ${repo.counts.completed}, open steps ${repo.active_open_steps}`
    );
  }
}
