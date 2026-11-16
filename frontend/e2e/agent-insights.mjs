// Agent efficiency workflow on Northline Financial: period comparison, evidence-backed insights, drill-down, scoped identities.
// Expectations come from the deterministic demo workload (seed 42): the Fraud Triage Agent's retry rate and the
// Reconciliation Agent's success rate drift from September 2026, so Sep–Oct compared with Jul–Aug shows both.
import assert from 'node:assert/strict';import {mkdir} from 'node:fs/promises';import {chromium} from 'playwright';
const base=process.env.BASE_URL??'http://localhost:3000';const out=process.env.SCREENSHOT_DIR??'/tmp/tokentrack-slice9b';await mkdir(out,{recursive:true});
const browser=await chromium.launch();const context=await browser.newContext({viewport:{width:1440,height:1050},colorScheme:'dark'});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));const main=page.locator('main');
async function get(path,status=200){const response=await context.request.get(base+'/api/core/'+path);assert.equal(response.status(),status,`${path}: ${await response.text()}`);return status===200?(await response.json()).data:null;}
const idle=()=>page.waitForFunction(()=>document.querySelector('[data-testid="agents-workspace"]')?.getAttribute('aria-busy')==='false');
async function open(query){await page.goto(base+'/agents'+query);await page.getByTestId('agents-workspace').waitFor();await idle();}
async function enter(name){if(await page.getByRole('button',{name:'Switch identity',exact:true}).isVisible()){await page.getByRole('button',{name:'Switch identity',exact:true}).click();await page.getByRole('dialog',{name:'Switch demo identity'}).getByRole('button',{name:'Continue as '+name,exact:true}).click();}else await page.getByRole('button',{name:'Continue as '+name,exact:true}).click();await main.getByRole('heading',{name:/Organization overview|Team workspace|Project workspace|My workspace/}).waitFor();}
const units=value=>{const [w,f='']=String(value).replace('-','').split('.');return (String(value).startsWith('-')?-1n:1n)*BigInt(w+(f+'0'.repeat(15)).slice(0,15));};
const day=86400000;const span=p=>Date.parse(p.end)-Date.parse(p.start);
const agent=(report,key)=>report.agents.find(a=>a.agent_key===key);const findings=(report,key)=>report.insights.filter(i=>i.agent_id===agent(report,key)?.id).map(i=>i.type).sort();
const RANGE='start=2026-09-01T00%3A00%3A00Z&end=2026-11-01T00%3A00%3A00Z';
try{
  // Leadership (CFO) opens Agents, moves to Efficiency and compares the default periods.
  await page.goto(base);await enter('Gabriel Moreau');await open('');assert.equal(await page.getByTestId('agents-workspace').getAttribute('data-tab'),'overview');
  await page.getByRole('tab',{name:'Efficiency'}).click();await page.waitForURL(/tab=efficiency/);await page.getByTestId('efficiency-view').waitFor();await idle();
  const latest=await get('agents/insights');
  assert.equal(latest.current_period.end,'2026-11-01T00:00:00Z','defaults to the end of recorded data');assert.equal(latest.comparison_period.end,latest.current_period.start);assert.equal(span(latest.current_period),span(latest.comparison_period));
  assert.equal(await page.getByTestId('current-period').innerText(),`${latest.current_period.start.slice(0,10)} → ${latest.current_period.end.slice(0,10)}`);
  await page.getByTestId('synthetic-badge').waitFor();assert.match(await page.getByTestId('coverage-badge').innerText(),/Partial cost/);
  for(const period of ['baseline','current'])assert.equal(latest.agents.reduce((sum,a)=>sum+units(a[period].corrected_modeled_cost),0n),units(latest.summary[period].corrected_modeled_cost),`${period} agent costs reconcile to the total`);
  await page.screenshot({path:out+'/efficiency-leadership-dark.png',fullPage:true});
  await page.getByLabel('Comparison window').selectOption('week');await page.waitForURL(/compare=week/);await idle();const week=await get('agents/insights?compare=week');
  assert.equal(Date.parse(week.current_period.start)-Date.parse(week.comparison_period.start),7*day);assert.equal(new Date(week.current_period.start).getUTCDay(),1,'weeks start on Monday');
  if(week.partial_current_period){assert.equal(week.comparison_basis,'equivalent_elapsed_portion');await main.getByText('Partial current period',{exact:true}).waitFor();}
  const month=await get('agents/insights?compare=month');assert.deepEqual([month.current_period.start,month.comparison_period.start],['2026-10-01T00:00:00Z','2026-09-01T00:00:00Z']);assert.equal(month.insights.filter(i=>i.percent_change==='Infinity').length,0);
  await page.getByLabel('Comparison window').selectOption('previous_period');await page.waitForFunction(()=>!location.search.includes('compare='));await idle();
  // Two months with drift against the two before.
  const full=await get('agents/insights?'+RANGE);assert.deepEqual(full.comparison_period,{start:'2026-07-02T00:00:00Z',end:'2026-09-01T00:00:00Z'});
  assert(findings(full,'fraud-triage-agent').includes('retry_increase'));assert(findings(full,'reconciliation-agent').includes('success_rate_decline'));assert.deepEqual(findings(full,'code-review-agent'),['pricing_coverage_gap'],'stable agents only show their cost-coverage gap');
  assert(full.insights.filter(i=>i.type==='pricing_coverage_gap').every(i=>i.evidence_quality==='incomplete_cost_data'),'unpriced self-hosted usage is reported, never estimated');
  for(const period of ['baseline','current'])assert.equal(full.agents.reduce((sum,a)=>sum+units(a[period].corrected_modeled_cost),0n),units(full.summary[period].corrected_modeled_cost));
  await open('?tab=efficiency&'+RANGE);await page.getByRole('button',{name:'Cost drivers for Reconciliation Agent'}).click();const split=page.getByTestId('decomposition');await split.waitFor();await split.getByText('Associated changes (not exact causes)').waitFor();
  const d=agent(full,'reconciliation-agent').decomposition;assert.equal(units(d.exact.volume_effect)+units(d.exact.per_run_cost_effect),units(d.cost.delta));
  // Inspect the retry anomaly, open its supporting runs, verify recorded attempts.
  await page.getByRole('tab',{name:'Insights'}).click();await page.waitForURL(/tab=insights/);await page.getByTestId('insights-view').waitFor();await idle();
  assert.match(await page.getByTestId('insight-summary').innerText(),new RegExp(`^${full.summary.requiring_attention} findings require attention`));
  await page.getByLabel('Insight type filter').selectOption('retry_increase');await page.waitForURL(/insight_type=retry_increase/);await idle();
  const retry=full.insights.find(i=>i.type==='retry_increase'&&i.agent_name==='Fraud Triage Agent');const card=page.getByTestId('insight').filter({hasText:'Fraud Triage Agent'});await card.waitFor();
  assert.match(await card.innerText(),/Retry rate increased 10\.7 percentage points \(12\.2% to 23\.0%\)/);assert.equal(await card.getByTestId('evidence-quality').innerText(),'Sufficient evidence');await card.getByText('Inspect recent provider-error and timeout patterns',{exact:false}).waitFor();
  await card.getByRole('button',{name:'Show evidence'}).click();await card.getByTestId('insight-evidence').waitFor();await card.getByText('Also observed in the same periods (not causes)').waitFor();await page.screenshot({path:out+'/insights-retry-evidence-dark.png',fullPage:true});
  await card.getByRole('link',{name:'View supporting runs'}).click();await page.waitForURL(/tab=executions.*retried=true/);await idle();
  const supporting=await get(`agents?agent_id=${retry.agent_id}&start=${encodeURIComponent(retry.drilldown.start)}&end=${encodeURIComponent(retry.drilldown.end)}&retried=true&limit=100`);
  assert.equal(supporting.runs.total,retry.evidence.current.retried_runs);assert(supporting.runs.total>0);assert(supporting.runs.rows.every(r=>r.attempts>1&&r.retries>=1&&r.attempt_records.length===r.attempts));
  if(supporting.runs.total<=100)assert.equal(supporting.runs.rows.reduce((n,r)=>n+r.retries,0),Number(retry.evidence.current.retries));await main.getByText(`${supporting.runs.total} runs`,{exact:true}).waitFor();
  // Open the success-rate finding from Efficiency.
  await open('?tab=efficiency&'+RANGE);await page.getByTestId('agent-comparison').locator('tr',{hasText:'Reconciliation Agent'}).getByRole('button',{name:'findings'}).click();await page.waitForURL(/tab=insights.*agent_id=/);await idle();
  await page.getByTestId('insight').filter({hasText:'Success rate fell 16.9 percentage points'}).getByText('Review the failed and cancelled runs in this period',{exact:false}).waitFor();
  // Empty range.
  await open('?tab=insights&start=2020-01-01T00%3A00%3A00Z&end=2020-01-05T00%3A00%3A00Z');await main.getByText('No findings for this scope and period').waitFor();
  // Manager sees only permitted agents and findings; informational findings start collapsed.
  await enter('Elliot Brandt');await open('?tab=insights&'+RANGE);const manager=await get('agents/insights?'+RANGE);
  assert(manager.summary.current.runs<full.summary.current.runs);assert(manager.agents.every(a=>full.agents.some(f=>f.id===a.id)));assert.equal(manager.scope.persona,'manager');
  assert.match(await page.getByTestId('insight-summary').innerText(),new RegExp(`^${manager.summary.requiring_attention} findings? requires? attention`));const managerInfo=manager.insights.filter(i=>i.severity==='info').length;assert.equal(await page.getByTestId('insight').count(),manager.insights.length-(managerInfo&&managerInfo<manager.insights.length?managerInfo:0),'informational findings start collapsed');if(managerInfo&&managerInfo<manager.insights.length){await page.getByRole('button',{name:/Show \d+ informational finding/}).click();assert.equal(await page.getByTestId('insight').count(),manager.insights.length);}
  for(const a of manager.agents)assert(units(a.current.corrected_modeled_cost)<=units(agent(full,a.agent_key).current.corrected_modeled_cost));
  // Employee sees only their own executions; agents, people and projects outside the scope are denied.
  await enter('Hana Takeda');await open('?tab=insights&'+RANGE);const employee=await get('agents/insights?'+RANGE);assert.equal(employee.scope.persona,'employee');assert(employee.summary.current.runs<=manager.summary.current.runs);
  assert(employee.agents.every(a=>a.current.runs+a.baseline.runs<=agent(full,a.agent_key).current.runs+agent(full,a.agent_key).baseline.runs));
  const hidden=full.agents.find(a=>!employee.agents.some(e=>e.id===a.id));if(hidden)await get(`agents/insights?agent_id=${hidden.id}&${RANGE}`,404);
  const identities=await get('demo/identities');await get('agents/insights?user_id='+identities.find(p=>p.name==='Gabriel Moreau').id,404);await get('agents/insights?compare=decade',400);
  assert.equal((await context.request.get(base+'/api/core/internal/v1/agent-insights')).status(),404);for(const path of ['agent-insights','agent-cohort'])assert.equal((await context.request.post('http://usage-engine:8080/internal/v1/'+path,{data:{}})).status(),401);
  // Responsive light theme.
  await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:/Switch to light theme/}).click();await page.screenshot({path:out+'/insights-employee-mobile-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'insights fit a phone');
  await page.getByRole('tab',{name:'Efficiency'}).click();await page.getByTestId('efficiency-view').waitFor();await idle();await page.screenshot({path:out+'/efficiency-employee-mobile-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'efficiency fits a phone');
  await page.setViewportSize({width:820,height:1100});await page.screenshot({path:out+'/efficiency-employee-tablet-light.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'efficiency fits a tablet');
  await page.route('**/api/core/agents/insights*',route=>route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'Agent analytics is unavailable. Retry shortly; no estimated totals are substituted.'}})}));await open('?tab=insights&severity=critical').catch(()=>{});await main.getByRole('alert').waitFor();await page.unroute('**/api/core/agents/insights*');await main.getByRole('button',{name:'Try again'}).click();await page.getByTestId('insights-view').waitFor();
  // Budgets and requests still load for this identity.
  for(const [path,heading] of [['/budgets',/budget/i],['/requests',/request/i]]){await page.goto(base+path);await main.getByRole('heading',{name:heading}).first().waitFor();}
  assert.deepEqual(errors,[]);console.log(`PASS: efficiency comparison (previous/week/month), ${full.insights.length} findings for Sep–Oct, retry drill-down verified against ${supporting.runs.total} supporting runs, exact cost split, sparse/empty/error states, manager (${manager.agents.length} agents) and employee (${employee.agents.length} agents) scope isolation, internal route denial, mobile/tablet themes, budgets and requests intact.`);
}catch(error){await page.screenshot({path:out+'/failure.png',fullPage:true}).catch(()=>{});console.log('Browser errors:',errors);throw error;}finally{await browser.close();}
