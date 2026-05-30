# runtime_config

Builds the effective runtime configuration for playbooks and roles from:
- `terraform/config/*.json`
- local generated overrides
- Terraform runtime metadata
- secret backend payloads

This role resolves the Ansible runtime variables used by the playbooks.
