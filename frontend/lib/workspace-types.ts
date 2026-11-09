export type NavigationItem = { label: string; href: string; icon: string };
export type UnitLink = {
  id: string;
  name: string;
  unit_type: string;
  parent_unit_id: string | null;
};
export type PersonLink = {
  id: string;
  name: string;
  job_title: string;
  can_view?: boolean;
};
export type Person = PersonLink & {
  job_function: string;
  visibility: "self" | "management" | "directory";
  primary_team: UnitLink | null;
  email?: string;
  status?: string;
  memberships?: (UnitLink & { is_primary: boolean; membership_type: string })[];
  managers?: (PersonLink & { relationship_type: string })[];
  projects?: Project[];
  can_view_reporting?: boolean;
  project_role?: string;
  project_assignments?: {
    id: string;
    name: string;
    status: string;
    project_role: string;
  }[];
  relationship_type?: string;
};
export type Organization = {
  id: string;
  name: string;
  slug: string;
  description: string;
  demo: boolean;
  scope?: string;
  employee_count?: number;
  unit_count?: number;
  project_count?: number;
};
export type Access = {
  scope_key: string;
  persona: "leadership" | "manager" | "project_lead" | "employee";
  grants: {
    role: string;
    scope_type: string;
    scope_id: string;
    scope_name: string;
  }[];
  capabilities: string[];
  restricted: string[];
  navigation: NavigationItem[];
  visibility: Record<string, string>;
};
export type Me = { user: Person; organization: Organization; access: Access };
export type Identity = PersonLink & {
  organization: Organization;
  persona: Access["persona"];
  primary_team: string | null;
};
export type Unit = UnitLink & {
  description: string;
  member_count: number;
  subtree_member_count: number;
  roster_visibility: string;
  managers: PersonLink[];
  members?: Person[];
  children?: Unit[];
  projects?: Project[];
  members_meta?: Pagination;
};
export type Project = {
  id: string;
  name: string;
  slug: string;
  description: string;
  status: string;
  contributor_count: number;
  leads: PersonLink[];
  teams: UnitLink[];
  my_role: string | null;
  member_role?: string;
  can_edit: boolean;
  created_by_id?: string | null;
  administrators: PersonLink[];
  restore_status: string;
  permissions: {
    edit: boolean;
    members_manage: boolean;
    ownership_transfer: boolean;
    lifecycle_manage: boolean;
    history: boolean;
  };
  available_statuses: string[];
  members?: Person[];
  members_meta?: Pagination;
  role_assignments?: { role: string; user: PersonLink }[];
};
export type Overview = {
  persona: Access["persona"];
  counts: { label: string; value: number }[];
  units: Unit[];
  people: Person[];
  projects: Project[];
};
export type ReportingContext = {
  person: PersonLink;
  ancestors: (PersonLink & { report_id: string; relationship_type: string })[];
  direct_reports: Person[];
};
export type Pagination = { total: number; limit: number; offset: number };
export type ApiResponse<T> = { data: T; meta?: Pagination };
export type ProjectMembership = {
  id: string;
  user: Person;
  project_role: string;
  joined_at: string;
  left_at: string | null;
  status: string;
  administrator: boolean;
  can_update: boolean;
  can_remove: boolean;
};
export type ProjectGroup = { unit: UnitLink; member_count: number };
