"use client";
import {useRef,useState} from 'react';
import {useQueryClient} from '@tanstack/react-query';
import {useSession} from '@/components/session-provider';
import {useNotice} from '@/components/ui/notice-provider';
import {api,ApiError} from './api-client';
export function useBudgetMutation(){
 const {me,refreshAccess}=useSession();const client=useQueryClient();const notice=useNotice();const lock=useRef(false);const [pending,setPending]=useState(false);const [error,setError]=useState<string|null>(null);
 async function run(path:string,body:unknown,message:string){
  if(lock.current||!me)return false;lock.current=true;setPending(true);setError(null);const actor=me.user.id;const org=me.organization.id;
  try{await api('budgets/'+path,{method:'POST',body:{budget:body}});await client.invalidateQueries({predicate:q=>{const key=q.queryKey;return (['budgets','analytics'].includes(String(key[0]))&&String(key[1]).startsWith(org+'/'+actor+'/'))||(key[0]===org&&key[1]===actor&&['me/overview','users','projects'].some(p=>String(key[2]).startsWith(p)));}});const channel=new BroadcastChannel('tokentrack-budgets');channel.postMessage({organizationId:org});channel.close();notice(message);return true;
  }catch(e){if(e instanceof ApiError&&[401,403,404].includes(e.status))await refreshAccess();setError(e instanceof Error?e.message:'Budget operation failed');return false;}finally{lock.current=false;setPending(false);}
 }
 return {run,pending,error,clearError:()=>setError(null)};
}
