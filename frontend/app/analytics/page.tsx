import { Suspense } from 'react';
import { AnalyticsWorkspace } from '@/components/analytics-workspace';
import { Skeleton } from '@/components/workspace-ui';
export default function AnalyticsPage(){return <Suspense fallback={<Skeleton label="Loading analytics"/>}><AnalyticsWorkspace/></Suspense>;}
