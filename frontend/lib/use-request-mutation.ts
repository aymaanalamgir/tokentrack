"use client";
import {useRef,useState} from 'react';
import {useQueryClient} from '@tanstack/react-query';
import {useSession} from '@/components/session-provider';
import {useNotice} from '@/components/ui/notice-provider';
import {api,ApiError} from './api-client';

export function useRequestMutation(){
 const {me,refreshAccess}=useSession();const client=useQueryClient();const notice=useNotice();const busy=useRef(false);const [pending,setPending]=useState(false);const [error,setError]=useState<string|null>(null);
 async function run(path:string,body:unknown,message:string,kind:'request'|'request_action'){
  if(!me||busy.current)return false;busy.current=true;setPending(true);setError(null);const identity=`${me.organization.id}/${me.user.id}/`;
  try{await api(`requests${path?'/'+path:''}`,{method:'POST',body:{[kind]:body}});await client.invalidateQueries({predicate:q=>['requests','budgets','analytics'].includes(String(q.queryKey[0]))&&String(q.queryKey[1]).startsWith(identity)});const channel=new BroadcastChannel('tokentrack-financial-workflows');channel.postMessage({organizationId:me.organization.id});channel.close();notice(message);return true;
  }catch(reason){if(reason instanceof ApiError&&[401,403,404].includes(reason.status))await refreshAccess();setError(reason instanceof Error?reason.message:'Request operation failed');return false;}finally{busy.current=false;setPending(false);}
 }
 return {run,pending,error,clearError:()=>setError(null)};
}
