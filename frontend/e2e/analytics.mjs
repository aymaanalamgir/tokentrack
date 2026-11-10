import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
import {chromium} from 'playwright';
const base=process.env.BASE_URL??'http://localhost:3000';
const output=process.env.SCREENSHOT_DIR??'/tmp/tokentrack-slice6';await mkdir(output,{recursive:true});
const browser=await chromium.launch();const context=await browser.newContext({viewport:{width:1440,height:1100},colorScheme:'dark'});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
async function get(path,status=200){const r=await context.request.get(`${base}/api/core/${path}`);assert.equal(r.status(),status,path);return (await r.json()).data;}
const main=page.locator('main');
async function enter(name){if(await page.getByRole('button',{name:'Switch identity',exact:true}).isVisible()){await page.getByRole('button',{name:'Switch identity',exact:true}).click();await page.getByRole('dialog',{name:'Switch demo identity'}).getByRole('button',{name:`Continue as ${name}`,exact:true}).click();}else await page.getByRole('button',{name:`Continue as ${name}`,exact:true}).click();await main.getByRole('heading',{name:/Organization overview|Team workspace|Project workspace|My workspace/}).waitFor();await page.goto(base+'/analytics');await page.getByTestId('analytics-workspace').waitFor();await page.waitForFunction(()=>document.querySelector('[data-testid="analytics-workspace"]')?.getAttribute('aria-busy')==='false');}
try{
 await page.goto(base);await enter('Olivia Chen');
 const identities=await get('demo/identities');const jordan=identities.find(p=>p.name==='Jordan Lee');const maya=identities.find(p=>p.name==='Maya Chen');const olivia=identities.find(p=>p.name==='Olivia Chen');
 const full=await get('analytics?start=2026-11-01T00%3A00%3A00Z&end=2026-12-11T00%3A00%3A00Z');
 assert(full.summary.events>0);assert(full.summary.unpriced_events>0);assert.equal(full.summary.adjustments,'-0.0065');
 const scaled=v=>{const [a,b='']=v.split('.');return BigInt(a)*10n**15n+BigInt((b+'0'.repeat(15)).slice(0,15))};
 assert.equal(full.timeseries.reduce((n,r)=>n+scaled(r.net_expenditure),0n),scaled(full.summary.net_expenditure));
 assert.equal(full.models.reduce((n,r)=>n+scaled(r.net_expenditure),0n),scaled(full.summary.net_expenditure));
 assert.equal(full.tools.reduce((n,r)=>n+scaled(r.net_expenditure),0n),scaled(full.summary.net_expenditure));
 await page.getByTestId('analytics-chart').waitFor();
 await page.screenshot({path:output+'/leadership-dark.png',fullPage:true});
 const engineering=full.context.units.find(u=>u.name==='Engineering');
 await page.getByLabel('Team filter').selectOption(engineering.id);await page.waitForURL(/organization_unit_id/);await page.waitForFunction(()=>document.querySelector('[data-testid="analytics-workspace"]')?.getAttribute('aria-busy')==='false');
 assert((await get('analytics?organization_unit_id='+engineering.id)).summary.events<full.summary.events);
 const fraud=full.context.projects.find(p=>p.name==='Fraud Detection Platform');
 await page.getByLabel('Project filter').selectOption(fraud.id);await page.waitForURL(/project_id/);
 await page.getByRole('tab',{name:'models',exact:true}).click();await main.getByText('Synthetic demonstration mapping').first().waitFor();
 const project=await get('analytics?project_id='+fraud.id);assert(project.accounts.every(a=>a.purpose==='project'));
 await page.getByLabel('Granularity').selectOption('week');await page.waitForURL(/granularity=week/);await page.getByLabel('Granularity').selectOption('month');await page.waitForURL(/granularity=month/);
 await enter('Marcus Rivera');const manager=await get('analytics');assert(manager.summary.active_users<full.summary.active_users);assert(manager.employees.some(e=>e.id===jordan.id));const managerOlivia=await get('analytics?user_id='+olivia.id);assert(managerOlivia.projects.every(p=>manager.context.projects.some(v=>v.id===p.id)));assert(managerOlivia.summary.events<full.employees.find(e=>e.id===olivia.id).events);
 const unrelated=full.employees.find(e=>!manager.employees.some(m=>m.id===e.id));assert(unrelated);const denied=await context.request.get(base+'/api/core/analytics?user_id='+unrelated.id);assert([200,404].includes(denied.status()));if(denied.status()===200)assert.equal((await denied.json()).data.summary.events,0);await get('analytics?user_id='+maya.id,404);
 await enter('Priya Shah');const lead=await get('analytics');assert(lead.summary.active_users<full.summary.active_users);assert(lead.accounts?.every(a=>a.purpose==='project'));
 await page.getByLabel('Employee filter').selectOption(jordan.id);await page.waitForURL(/user_id/);
 const leadJordan=await get('analytics?user_id='+jordan.id);assert(leadJordan.projects.every(p=>lead.context.projects.some(v=>v.id===p.id)));
 await enter('Jordan Lee');const employee=await get('analytics');assert.equal(employee.employees.length,1);assert.equal(employee.employees[0].id,jordan.id);assert.equal(employee.budget,null);assert.equal(employee.accounts,null);
 await get('analytics?user_id='+olivia.id,404);await get('analytics?organization_unit_id='+engineering.id,404);
 assert.equal((await context.request.get(base+'/api/core/internal/v1/analytics')).status(),404);
 const k=await context.request.post('http://usage-engine:8080/internal/v1/analytics',{data:{}});assert.equal(k.status(),401);
 await page.getByLabel('Project filter').selectOption(fraud.id);await page.waitForURL(/project_id/);await page.waitForFunction(()=>document.querySelector('[data-testid="analytics-workspace"]')?.getAttribute('aria-busy')==='false');await page.screenshot({path:output+'/employee-dark.png',fullPage:true});
 await page.goto(base+'/analytics?start=2020-01-01T00%3A00%3A00Z&end=2020-02-01T00%3A00%3A00Z');await main.getByRole('heading',{name:'No activity in this range'}).waitFor();
 await page.route('**/api/core/analytics*',async route=>{await new Promise(r=>setTimeout(r,500));await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{code:'usage_analytics_unavailable',message:'Usage analytics temporarily unavailable'}})});});
 await page.goto(base+'/analytics?granularity=week');await page.getByLabel('Loading analytics').waitFor();await main.getByRole('alert').waitFor();assert(await main.getByRole('button',{name:'Try again'}).isVisible());
 await page.unroute('**/api/core/analytics*');await main.getByRole('button',{name:'Try again'}).click();await page.getByTestId('analytics-workspace').waitFor();
 await page.getByRole('button',{name:/Switch to light theme/}).click();await page.setViewportSize({width:390,height:844});await page.screenshot({path:output+'/employee-mobile-light.png',fullPage:true});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false);
 assert.deepEqual(errors,[]);console.log('PASS: four persona dashboards, exact correction and dimension reconciliation, team/project/model/employee drill-down, time filters, internal API denial, empty/error/loading, identity cache isolation, dark/light and mobile.');
}finally{await browser.close();}
