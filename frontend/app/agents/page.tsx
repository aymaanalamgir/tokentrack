import {Suspense} from 'react';
import {AgentsWorkspace} from '@/components/agents-workspace';
import {Skeleton} from '@/components/workspace-ui';
export default function AgentsPage(){return <Suspense fallback={<Skeleton label="Loading agents"/>}><AgentsWorkspace/></Suspense>}
