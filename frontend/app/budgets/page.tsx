import {Suspense} from 'react';
import {BudgetWorkspace} from '@/components/budget-workspace';
import {Skeleton} from '@/components/workspace-ui';
export default function BudgetsPage(){return <Suspense fallback={<Skeleton label="Loading budgets"/>}><BudgetWorkspace/></Suspense>;}
