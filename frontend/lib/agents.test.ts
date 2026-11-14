import assert from 'node:assert/strict';
import test from 'node:test';
import {agentTab,agentsPath,changeLabel,insightsPath,metricChange,metricLabel,supportingRunsHref} from './agents';

test('each endpoint receives only its own filters and never the client tab',()=>{
  const search=new URLSearchParams('tab=insights&start=2026-11-26T00:00:00Z&end=2026-12-10T00:00:00Z&compare=week&severity=warning&outcome=failure&retried=true&offset=25&agent_id=abc');
  assert.equal(agentsPath(search),'agents?start=2026-11-26T00%3A00%3A00Z&end=2026-12-10T00%3A00%3A00Z&agent_id=abc&outcome=failure&retried=true&offset=25');
  assert.equal(insightsPath(search),'agents/insights?start=2026-11-26T00%3A00%3A00Z&end=2026-12-10T00%3A00%3A00Z&compare=week&agent_id=abc&severity=warning');
  assert.equal(agentsPath(new URLSearchParams('tab=overview')),'agents');
  assert.equal(insightsPath(new URLSearchParams('')),'agents/insights');
});
test('a half-specified range is dropped rather than sent as an invalid insight request',()=>{
  assert.equal(insightsPath(new URLSearchParams('start=2026-11-26T00:00:00Z&compare=month')),'agents/insights?compare=month');
});
test('unknown tabs fall back to overview',()=>{
  assert.equal(agentTab(new URLSearchParams('tab=efficiency')),'efficiency');
  assert.equal(agentTab(new URLSearchParams('tab=admin')),'overview');
  assert.equal(agentTab(new URLSearchParams('')),'overview');
});
test('metric labels format by unit and keep missing values explicit',()=>{
  assert.equal(metricLabel('21.25','percent'),'21.3%');
  assert.equal(metricLabel('0.089423828409091','usd'),'$0.0894');
  assert.equal(metricLabel('-0.0565','usd'),'-$0.0565');
  assert.equal(metricLabel('45355.1786','tokens'),'45,355');
  assert.equal(metricLabel('41.5','seconds'),'41.5s');
  assert.equal(metricLabel(null,'usd'),'N/A');
});
test('changes never render an infinite percentage',()=>{
  assert.equal(changeLabel({delta:'13.25',percent_change:'165.6'},'percent'),'+13.3 pts');
  assert.equal(changeLabel({delta:'0.0471',percent_change:'111.4'},'usd'),'+111.4%');
  assert.equal(changeLabel({delta:'5',percent_change:null},'tokens'),'no baseline');
  assert.equal(changeLabel({delta:'0',percent_change:null},'usd'),'no change');
  assert.equal(changeLabel({delta:null,percent_change:null},'usd'),'no comparison');
  assert.equal(changeLabel(null,'usd'),'no comparison');
  assert.deepEqual(metricChange('0','12'),{baseline:'0',current:'12',delta:'12',percent_change:null});
  assert.deepEqual(metricChange(null,'12'),{baseline:null,current:'12',delta:null,percent_change:null});
  assert.equal(changeLabel(metricChange('100','160'),'tokens'),'+60.0%');
});
test('insight drill-down links carry the authorized run filters to the executions tab',()=>{
  assert.equal(supportingRunsHref({agent_id:'a1',start:'2026-11-26T00:00:00Z',end:'2026-12-10T00:00:00Z',retried:'true'}),'/agents?tab=executions&agent_id=a1&start=2026-11-26T00%3A00%3A00Z&end=2026-12-10T00%3A00%3A00Z&retried=true');
});
