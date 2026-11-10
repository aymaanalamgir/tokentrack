CREATE INDEX usage_analytics_tenant_time ON usage.usage_events(organization_id,occurred_at);
CREATE INDEX usage_analytics_user_time ON usage.usage_events(organization_id,user_id,occurred_at);
CREATE INDEX usage_analytics_project_time ON usage.usage_events(organization_id,project_id,occurred_at);
