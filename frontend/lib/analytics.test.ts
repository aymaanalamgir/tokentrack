import test from 'node:test';
import assert from 'node:assert/strict';
import {money,presetRange,tokens} from './analytics';
test('decimal presentation rounds subcent and negative values without float accumulation',()=>{assert.equal(money('0.1065'),'$0.1065');assert.equal(money('-0.0065'),'-$0.0065');assert.equal(money('999999999999999999.99999'),'$1,000,000,000,000,000,000.0000');assert.equal(money('0.000000000000001'),'$0.0000');});
test('date presets use UTC and explicit complete calendar boundaries',()=>{assert.deepEqual(presetRange('7','2026-12-10T00:00:00Z'),['2026-12-03T00:00:00.000Z','2026-12-10T00:00:00.000Z']);assert.deepEqual(presetRange('previous','2026-12-10T00:00:00Z'),['2026-11-01T00:00:00.000Z','2026-12-01T00:00:00.000Z']);});
test('cached input is not counted twice in total tokens',()=>{assert.equal(tokens({input_tokens:'100000',output_tokens:'10000',cached_input_tokens:'20000'} as Parameters<typeof tokens>[0]),110000);});
