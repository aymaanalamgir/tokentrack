// Slice 9B browser workflow: efficiency comparison, evidence-backed insights, drill-down, scoped identities.
import assert from 'node:assert/strict';import {mkdir} from 'node:fs/promises';import {chromium} from 'playwright';
const base=process.env.BASE_URL??'http://localhost:3000';const out=process.env.SCREENSHOT_DIR??'/tmp/tokentrack-slice9b';await mkdir(out,{recursive:true});
const browser=await chromium.launch();const context=await browser.newContext({viewport:{width:1440,height:1050},colorScheme:'dark'});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));const main=page.locator('main');
async function get(path,status=200){const response=await context.request.get(base+'/api/core/'+path);assert.equal(response.status(),status,`${path}: ${await response.text()}`);return status===200?(await response.json()).data:null;}
const idle=()=>page.waitForFunction(()=>document.querySelector('[data-testid="agents-workspace"]')?.getAttribute('aria-busy')==='false');
async function open(query){await page.goto(base+'/agents'+query);await page.getByTestId('agents-workspace').waitFor();await idle();}
async function enter(name){if(await page.getByRole('button',{name:'Switch identity',exact:true}).isVisible()){await page.getByRole('button',{name:'Switch identity',exact:true}).click();await page.getByRole('dialog',{name:'Switch demo identity'}).getByRole('button',{name:'Continue as '+name,exact:true}).click();}else await page.getByRole('button',{name:'Continue as '+name,exact:true}).click();await main.getByRole('heading',{name:/Organization overview|Team workspace|Project workspace|My workspace/}).waitFor();}
const units=value=>{const [w,f='']=String(value).replace('-','').split('.');return (String(value).startsWith('-')?-1n:1n)*BigInt(w+(f+'0'.repeat(15)).slice(0,15));};
const agent=(report,key)=>report.agents.find(a=>a.agent_key===key);const findings=(report,key)=>report.insights.filter(i=>i.agent_id===agent(report,key)?.id).map(i=>i.type).sort();
try{
  // 1-4: leadership opens Agents, moves to Efficiency and compares periods.
  await page.goto(base);await enter('Olivia Chen');await open('');assert.equal(await page.getByTestId('agents-workspace').getAttribute('data-tab'),'overview');
  await page.getByRole('tab',{name:'Efficiency'}).click();await page.waitForURL(/tab=efficiency/);await page.getByTestId('efficiency-view').waitFor();await idle();
  const full=await get('agents/insights');
  assert.deepEqual([full.current_period,full.comparison_period],[{start:'2026-11-26T00:00:00Z',end:'2026-12-10T00:00:00Z'},{start:'2026-11-12T00:00:00Z',end:'2026-11-26T00:00:00Z'}]);
  assert.equal(await page.getByTestId('current-period').innerText(),'2026-11-26 → 2026-12-10');assert.equal(await page.getByTestId('comparison-period').innerText(),'2026-11-12 → 2026-11-26');
  await page.getByTestId('synthetic-badge').waitFor();assert.match(await page.getByTestId('coverage-badge').innerText(),/Partial cost/);
  for(const period of ['baseline','current'])assert.equal(full.agents.reduce((sum,a)=>sum+units(a[period].corrected_modeled_cost),0n),units(full.summary[period].corrected_modeled_cost),`${period} agent costs reconcile to the total`);
  await page.screenshot({path:out+'/efficiency-leadership-dark.png',fullPage:true});
  await page.getByLabel('Comparison window').selectOption('week');await page.waitForURL(/compare=week/);await idle();const week=await get('agents/insights?compare=week');
  assert.deepEqual([week.current_period.start,week.comparison_period.start,week.partial_current_period,week.comparison_basis],['2026-12-07T00:00:00Z','2026-11-30T00:00:00Z',true,'equivalent_elapsed_portion']);await main.getByText('Partial current period',{exact:true}).waitFor();
  const month=await get('agents/insights?compare=month');assert.equal(month.summary.baseline.runs,0);assert.equal(month.insights.filter(i=>i.percent_change==='Infinity').length,0);assert(month.agents.every(a=>a.evidence_state!=='sufficient'),'a month with no recorded baseline asserts nothing');
  await page.getByLabel('Comparison window').selectOption('previous_period');await page.waitForFunction(()=>!location.search.includes('compare='));await idle();
  // Scenario expectations from the deterministic fixture.
  assert.deepEqual(findings(full,'pr-review-assistant'),['retry_increase']);assert.deepEqual(findings(full,'test-triage-agent'),['success_rate_decline']);assert.deepEqual(findings(full,'release-notes-writer'),['cost_per_success_increase','output_token_spike']);
  assert.deepEqual(findings(full,'support-summarizer'),['cost_per_success_increase','model_cost_concentration']);assert.deepEqual(findings(full,'docs-indexer'),[],'more runs at stable efficiency is not flagged');assert(agent(full,'docs-indexer').current.runs>2*agent(full,'docs-indexer').baseline.runs);
  assert.deepEqual(findings(full,'legacy-migration-helper'),['cost_per_success_increase','input_token_spike','pricing_coverage_gap']);assert.equal(full.insights.find(i=>i.agent_id===agent(full,'legacy-migration-helper').id&&i.type==='cost_per_success_increase').evidence_quality,'incomplete_cost_data');
  assert.deepEqual(findings(full,'incident-scribe'),[]);assert.equal(agent(full,'incident-scribe').evidence_state,'insufficient_data');
  // 8: corrected cost per success and the correction itself come from the Rails ledger.
  assert.equal(agent(full,'docs-indexer').current.adjustments,'-0.00707');assert.equal(units(agent(full,'docs-indexer').current.corrected_modeled_cost),units(agent(full,'docs-indexer').current.original_modeled_cost)-units('0.00707'));
  await page.getByRole('button',{name:'Cost drivers for Support Summarizer'}).click();const split=page.getByTestId('decomposition');await split.waitFor();await split.getByText('Associated changes (not exact causes)').waitFor();await split.getByText('anthropic/claude-sonnet-4-6').first().waitFor();
  const d=agent(full,'support-summarizer').decomposition;assert.equal(units(d.exact.volume_effect)+units(d.exact.per_run_cost_effect),units(d.cost.delta));
  // 5-7: inspect the retry anomaly, open its supporting runs, verify recorded attempts.
  await page.getByRole('tab',{name:'Insights'}).click();await page.waitForURL(/tab=insights/);await page.getByTestId('insights-view').waitFor();await idle();
  assert.match(await page.getByTestId('insight-summary').innerText(),new RegExp(`^${full.summary.requiring_attention} findings require attention`));
  await page.getByLabel('Insight type filter').selectOption('retry_increase');await page.waitForURL(/insight_type=retry_increase/);await idle();
  const retry=full.insights.find(i=>i.type==='retry_increase'&&i.agent_name==='PR Review Assistant');const card=page.getByTestId('insight').filter({hasText:'PR Review Assistant'});await card.waitFor();
  assert.match(await card.innerText(),/Retry rate increased 19\.0 percentage points \(4\.8% to 23\.8%\)/);assert.equal(await card.getByTestId('evidence-quality').innerText(),'Sufficient evidence');await card.getByText('Inspect recent provider-error and timeout patterns',{exact:false}).waitFor();
  await card.getByRole('button',{name:'Show evidence'}).click();await card.getByTestId('insight-evidence').waitFor();await card.getByText('Also observed in the same periods (not causes)').waitFor();await page.screenshot({path:out+'/insights-retry-evidence-dark.png',fullPage:true});
  await card.getByRole('link',{name:'View supporting runs'}).click();await page.waitForURL(/tab=executions.*retried=true/);await idle();
  const supporting=await get(`agents?agent_id=${retry.agent_id}&start=${encodeURIComponent(retry.drilldown.start)}&end=${encodeURIComponent(retry.drilldown.end)}&retried=true&limit=100`);
  assert.equal(supporting.runs.total,retry.evidence.current.retried_runs);assert.equal(supporting.runs.total,40);assert(supporting.runs.rows.every(r=>r.attempts>1&&r.retries>=1&&r.attempt_records.length===r.attempts));
  assert.equal(supporting.runs.rows.reduce((n,r)=>n+r.retries,0),Number(retry.evidence.current.retries));await main.getByText(`${supporting.runs.total} runs`,{exact:true}).waitFor();
  // 9-10: open the associated agent from Efficiency and read its suggested investigation.
  await open('?tab=efficiency');await page.getByTestId('agent-comparison').locator('tr',{hasText:'Test Triage Agent'}).getByRole('button',{name:'findings'}).click();await page.waitForURL(/tab=insights.*agent_id=/);await idle();
  assert.equal(await page.getByTestId('insight').count(),1);await page.getByTestId('insight').getByText('Review the failed and cancelled runs in this period',{exact:false}).waitFor();
  await open('?tab=insights&insight_type=model_cost_concentration');const model=page.getByTestId('insight').filter({hasText:'Support Summarizer'});await model.getByRole('button',{name:'Show evidence'}).click();assert.match(await model.getByTestId('rate-scenario').innerText(),/Hypothetical rate-only comparison[\s\S]*Not a forecast of savings/);
  await open('?tab=insights&agent_id='+agent(full,'incident-scribe').id);await page.getByTestId('not-compared').getByText('Insufficient data',{exact:true}).waitFor();await main.getByText('No findings for this scope and period').waitFor();
  // Empty range, then error state.
  await open('?tab=insights&start=2026-10-01T00%3A00%3A00Z&end=2026-10-05T00%3A00%3A00Z');await main.getByText('No findings for this scope and period').waitFor();
  // 11-12: manager sees only permitted findings; privileged data is never shown while the new identity loads.
  await enter('Marcus Rivera');await open('?tab=insights');const manager=await get('agents/insights');
  assert(manager.summary.current.runs<full.summary.current.runs);assert(manager.agents.every(a=>full.agents.some(f=>f.id===a.id)));assert(manager.agents.length<full.agents.length);assert.equal(manager.scope.persona,'manager');
  assert.match(await page.getByTestId('insight-summary').innerText(),new RegExp(`^${manager.summary.requiring_attention} findings? requires? attention`));assert.equal(await page.getByTestId('insight').count(),manager.insights.length);
  for(const a of manager.agents)assert(units(a.current.corrected_modeled_cost)<=units(agent(full,a.agent_key).current.corrected_modeled_cost));
  // 13-14: employee sees only their own executions; unrelated agents, people and projects are denied.
  await enter('Jordan Lee');await open('?tab=insights');const employee=await get('agents/insights');assert.equal(employee.scope.persona,'employee');assert(employee.summary.current.runs<manager.summary.current.runs);
  assert.equal(agent(employee,'support-summarizer'),undefined);assert.equal(agent(employee,'release-notes-writer'),undefined);assert(agent(employee,'pr-review-assistant').current.runs<agent(full,'pr-review-assistant').current.runs);
  await get('agents/insights?agent_id='+agent(full,'support-summarizer').id,404);const identities=await get('demo/identities');await get('agents/insights?user_id='+identities.find(p=>p.name==='Olivia Chen').id,404);await get('agents/insights?compare=decade',400);
  assert.equal(await page.getByTestId('insight').count(),employee.insights.length);assert(!(await main.innerText()).includes('Support Summarizer'));
  assert.equal((await context.request.get(base+'/api/core/internal/v1/agent-insights')).status(),404);for(const path of ['agent-insights','agent-cohort'])assert.equal((await context.request.post('http://usage-engine:8080/internal/v1/'+path,{data:{}})).status(),401);
  // Responsive light theme.
  await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:/Switch to light theme/}).click();await page.screenshot({path:out+'/insights-employee-mobile-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'insights fit a phone');
  await page.getByRole('tab',{name:'Efficiency'}).click();await page.getByTestId('efficiency-view').waitFor();await idle();await page.screenshot({path:out+'/efficiency-employee-mobile-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'efficiency fits a phone');
  await page.setViewportSize({width:820,height:1100});await page.screenshot({path:out+'/efficiency-employee-tablet-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'efficiency fits a tablet');
  await page.route('**/api/core/agents/insights*',route=>route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'Agent analytics is unavailable. Retry shortly; no estimated totals are substituted.'}})}));await open('?tab=insights&severity=critical').catch(()=>{});await main.getByRole('alert').waitFor();await page.unroute('**/api/core/agents/insights*');await main.getByRole('button',{name:'Try again'}).click();await page.getByTestId('insights-view').waitFor();
  // 15: budgets and requests still load for this identity.
  for(const [path,heading] of [['/budgets',/budget/i],['/requests',/request/i]]){await page.goto(base+path);await main.getByRole('heading',{name:heading}).first().waitFor();}
  assert.deepEqual(errors,[]);console.log(`PASS: efficiency comparison (previous/week/month), ${full.insights.length} leadership findings, retry drill-down verified against ${supporting.runs.total} supporting runs, corrected cost and exact cost split, hypothetical scenario labelling, sparse/empty/error states, manager (${manager.agents.length} agents) and employee (${employee.agents.length} agents) scope isolation, internal route denial, mobile/tablet themes, budgets and requests intact.`);
}catch(error){await page.screenshot({path:out+'/failure.png',fullPage:true}).catch(()=>{});console.log('Browser errors:',errors);throw error;}finally{await browser.close();}
