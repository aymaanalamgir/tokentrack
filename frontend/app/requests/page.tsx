import {Suspense} from 'react';
import {RequestWorkspace} from '@/components/request-workspace';
import {Skeleton} from '@/components/workspace-ui';
export default function RequestsPage(){return <Suspense fallback={<Skeleton label="Loading requests"/>}><RequestWorkspace/></Suspense>;}
