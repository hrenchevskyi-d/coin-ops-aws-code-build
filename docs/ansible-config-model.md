# Ansible Configuration Model

Ansible is the infrastructure orchestration layer. It configures hosts, renders VM Compose stacks, installs k3s workloads, and materializes runtime settings from Terraform output and cloud secrets.

## Sources of Truth

- `terraform/config/*.json`: platform policy, clouds, networks, instances, DNS, deploy defaults, and secret names.
- `terraform/config/ansible-runtime.json`: generated Terraform metadata consumed by Ansible.
- `ansible/vars/local.generated.json`: optional generated local overrides.
- `ansible/roles/*/defaults/main.yml`: role-local technical defaults.
- selected cloud secret backend: runtime passwords, registry token, Cloudflare token, and Tailscale auth key.

## Runtime Resolution

Every main playbook includes `ansible/roles/runtime_config` in `pre_tasks`. That role merges JSON config, generated metadata, environment overrides, and secrets into flat variables such as `runtime_backend`, `image_tag`, `postgres_runtime_image`, `backend_ip`, `tailscale_auth_key`, and `cloudflare_api_token`.

Keep this merge logic centralized. Do not move platform policy into dynamic inventory or duplicate it inside role tasks.

## Role Patterns

- VM Compose roles use `compose_stack` and templates from `deploy/compose/`.
- k3s roles use reusable helpers such as `k3s_helm_client`, `k3s_ingress_endpoint`, `k3s_acme_cloudflare`, and CNPG roles.
- Runtime SQL is read from `deploy/sql/` and staged by the role that needs it.
- Tailscale and multicloud routing stay explicit host-level concerns.

## Checks

```bash
make runtime-config
make ansible-check
```

For live validation, run the affected playbook against a lab environment and inspect generated artifacts under `ansible/artifacts/`.
