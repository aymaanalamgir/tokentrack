const SCALE=10n**15n;
export function units(value:string):bigint|null {if(!/^(0|[1-9]\d{0,19})(\.\d{1,15})?$/.test(value))return null;const [a,b='']=value.split('.');return BigInt(a)*SCALE+BigInt((b+'0'.repeat(15)).slice(0,15));}
export function decimal(value:bigint){const neg=value<0n;const n=neg?-value:value;const frac=(n%SCALE).toString().padStart(15,'0').replace(/0+$/,'');return `${neg?'-':''}${n/SCALE}${frac?'.'+frac:''}`;}
export function allocationTotal(values:string[]){const numbers=values.map(units);return numbers.some(n=>n===null)?null:numbers.reduce<bigint>((sum,n)=>sum+n!,0n);}
export function operationKey(){const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;const h=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;}
