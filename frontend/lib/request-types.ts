export type RequestCapabilities={approve:boolean;reject:boolean;escalate:boolean;cancel:boolean};
export type RequestEvent={id:string;type:string;actor:{id:string;name:string};previous_status:string|null;new_status:string|null;reason:string;metadata:Record<string,unknown>;created_at:string};
export type FinancialRequest={
 id:string;request_type:'personal_allowance'|'project_funding'|'team_funding';status:'pending'|'approved'|'rejected'|'cancelled';
 requester:{id:string;name:string};target:{id:string;name:string}|null;target_account:{id:string;name:string}|null;source_account:{id:string;name:string}|null;
 month:string;currency:string;amount_semantics:string;current_amount_snapshot:string;source_available_snapshot:string|null;requested_amount:string;difference:string;
 reason:string;submitted_at:string;resolved_at:string|null;assigned_approver:{id:string;name:string}|null;routing_reason:string;escalated_at:string|null;
 execution:{transaction_id?:string;revision_id?:string};capabilities:RequestCapabilities;events?:RequestEvent[];
};
export type FundingOption={id:string;name:string;account_id:string;funding:string;expenditure:string;available:string};
export type RequestReport={
 month:string;my_requests:FinancialRequest[];pending_review:FinancialRequest[];history:FinancialRequest[];
 meta:{limit:number;offset:number;my_total:number;review_total:number;history_total:number};
 options:{allowance:{current_ceiling:string;revision_id:string}|null;projects:FundingOption[];units:FundingOption[];sources:{id:string;name:string;purpose:string;available:string}[];requesters:{id:string;name:string}[]};
 filters:Record<string,string>;
};
