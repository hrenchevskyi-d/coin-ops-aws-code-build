SHELL := /bin/bash

REPO_ROOT := $(CURDIR)
TF_DIR := $(REPO_ROOT)/terraform
ANSIBLE_DIR := $(REPO_ROOT)/ansible
INVENTORY := $(ANSIBLE_DIR)/inventory
GCP_INVENTORY := $(ANSIBLE_DIR)/inventory/inventory.gcp_compute.yml
LOCALHOST_INVENTORY := $(ANSIBLE_DIR)/inventory/localhost.yml
ENV_FILE := $(REPO_ROOT)/local/generated-env.sh
COMPOSE := docker compose
K8S_ARTIFACTS_DIR := $(ANSIBLE_DIR)/artifacts
K8S_TUNNELED_KUBECONFIG := $(K8S_ARTIFACTS_DIR)/kubeconfig-gcp-k3s-tunneled.yaml
HEADLAMP_START_SCRIPT := $(K8S_ARTIFACTS_DIR)/headlamp-start.sh
VENV_PYTHON := $(REPO_ROOT)/.venv/bin/python

HOST ?=
LIMIT ?=
TF_APPLY_ARGS ?=
TF_DESTROY_ARGS ?=

ENV_PREFIX = source "$(ENV_FILE)" &&
# Run Ansible from the project-local virtualenv when it exists so localhost
# Kubernetes tasks use the same Python environment that holds the kubernetes
# client dependency.
ANSIBLE_ENV = $(ENV_PREFIX) ANSIBLE_CONFIG="$(REPO_ROOT)/ansible.cfg" ANSIBLE_PYTHON_INTERPRETER="$(VENV_PYTHON)"
ANSIBLE_CMD = $(ANSIBLE_ENV)

.PHONY: help \
	local-up local-down local-logs local-ps local-restart local-config \
	tf-check-backend tf-plan tf-apply tf-destroy-compute tf-full-destroy \
	inventory-graph inventory-host ssh-host \
	runtime-config ansible-check provision deploy k3s-cluster k3s-headlamp k3s-homepage k3s-coinops k3s-platform headlamp-start headlamp-token

help:
	@echo "Local development:"
	@echo "  make local-up                - Run local docker compose stack"
	@echo "  make local-down              - Stop local docker compose stack"
	@echo "  make local-logs              - Tail local docker compose logs"
	@echo "  make local-ps                - Show local docker compose services"
	@echo "  make local-restart           - Rebuild and restart local docker compose stack"
	@echo "  make local-config            - Render local docker compose config"
	@echo ""
	@echo "Terraform / infrastructure:"
	@echo "  make tf-check-backend        - Verify backend.active.tf matches clouds.control_plane"
	@echo "  make tf-plan                 - Source generated env and run terraform plan"
	@echo "  make tf-apply                - Source generated env and run terraform apply"
	@echo "  make tf-destroy-compute      - Destroy only compute/runtime artifacts"
	@echo "  make tf-full-destroy         - Run deliberate full destroy helper"
	@echo ""
	@echo "Inventory / SSH:"
	@echo "  make inventory-graph         - Show Ansible inventory graph"
	@echo "  make inventory-host HOST=app-1"
	@echo "                               - Show resolved vars for a specific host"
	@echo "  make ssh-host HOST=coinops-gcp-app-1"
	@echo "                               - SSH using generated terraform ssh_config"
	@echo ""
	@echo "Ansible:"
	@echo "  make runtime-config          - Resolve and print the materialized runtime configuration locally"
	@echo "  make ansible-check           - Run local syntax checks for the main Ansible entrypoints"
	@echo "  make provision               - Run ansible/provision.yml"
	@echo "  make deploy                  - Run ansible/deploy.yml"
	@echo "  make k3s-cluster             - Run ansible/k3s-cluster.yml against GCP dynamic inventory"
	@echo "  make k3s-headlamp            - Run ansible/k3s-headlamp.yml against GCP dynamic inventory"
	@echo "  make k3s-homepage            - Run ansible/k3s-homepage.yml against GCP dynamic inventory"
	@echo "  make k3s-coinops             - Run ansible/k3s-coinops.yml against GCP dynamic inventory"
	@echo "  make k3s-platform            - Run ansible/k3s-platform.yml against GCP dynamic inventory"
	@echo "  make headlamp-start          - Run generated Headlamp access helper"
	@echo "  make headlamp-token          - Print a Headlamp login token"
	@echo ""
	@echo "Optional variables:"
	@echo "  LIMIT=role_app_backend       - Pass --limit to provision/deploy"
	@echo "  TF_APPLY_ARGS='-auto-approve'"
	@echo "  TF_DESTROY_ARGS='-auto-approve'"

local-up:
	$(COMPOSE) up -d --build

local-down:
	$(COMPOSE) down

local-logs:
	$(COMPOSE) logs -f

local-ps:
	$(COMPOSE) ps

local-restart:
	$(COMPOSE) down
	$(COMPOSE) up -d --build

local-config:
	$(COMPOSE) config

tf-check-backend:
	cd "$(TF_DIR)" && bash check-backend.sh

tf-plan:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform plan

tf-apply:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform apply $(TF_APPLY_ARGS)

tf-destroy-compute:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform destroy \
		-target=module.gcp_nat_route \
		-target=module.gcp_instances \
		-target=module.aws_instances \
		-target=module.aws_nat_route \
		-target=module.azure_instances \
		-target=module.azure_nat_route \
		-target=module.local_operator_artifacts \
		$(TF_DESTROY_ARGS)

tf-full-destroy:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && bash full-destroy.sh --yes-really-destroy-stateful $(TF_DESTROY_ARGS)

inventory-graph:
	$(ANSIBLE_CMD) ansible-inventory -i "$(INVENTORY)" --graph

inventory-host:
	@if [ -z "$(HOST)" ]; then echo "HOST is required, for example: make inventory-host HOST=app-1"; exit 1; fi
	$(ANSIBLE_CMD) ansible-inventory -i "$(INVENTORY)" --host "$(HOST)"

ssh-host:
	@if [ -z "$(HOST)" ]; then echo "HOST is required, for example: make ssh-host HOST=coinops-gcp-app-1"; exit 1; fi
	$(ENV_PREFIX) ssh -F "$(TF_DIR)/config/ssh_config" "$(HOST)"

runtime-config:
	$(ANSIBLE_CMD) ansible-playbook -i localhost, -c local "$(ANSIBLE_DIR)/runtime-config.yml"

ansible-check:
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/runtime-config.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/provision.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/k3s-cluster.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/k3s-headlamp.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/k3s-homepage.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/k3s-coinops.yml"
	$(ANSIBLE_ENV) ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local "$(ANSIBLE_DIR)/k3s-platform.yml"

provision:
	$(ANSIBLE_CMD) ansible-playbook -i "$(INVENTORY)" "$(ANSIBLE_DIR)/provision.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

deploy:
	$(ANSIBLE_CMD) ansible-playbook -i "$(INVENTORY)" "$(ANSIBLE_DIR)/deploy.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

k3s-cluster:
	$(ANSIBLE_CMD) ansible-playbook -i "$(LOCALHOST_INVENTORY)" -i "$(GCP_INVENTORY)" "$(ANSIBLE_DIR)/k3s-cluster.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

k3s-headlamp:
	$(ANSIBLE_CMD) ansible-playbook -i "$(LOCALHOST_INVENTORY)" -i "$(GCP_INVENTORY)" "$(ANSIBLE_DIR)/k3s-headlamp.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

k3s-homepage:
	$(ANSIBLE_CMD) ansible-playbook -i "$(LOCALHOST_INVENTORY)" -i "$(GCP_INVENTORY)" "$(ANSIBLE_DIR)/k3s-homepage.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

k3s-coinops:
	$(ANSIBLE_CMD) ansible-playbook -i "$(LOCALHOST_INVENTORY)" -i "$(GCP_INVENTORY)" "$(ANSIBLE_DIR)/k3s-coinops.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

k3s-platform:
	$(ANSIBLE_CMD) ansible-playbook -i "$(LOCALHOST_INVENTORY)" -i "$(GCP_INVENTORY)" "$(ANSIBLE_DIR)/k3s-platform.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

headlamp-start:
	@test -x "$(HEADLAMP_START_SCRIPT)" || (echo "Missing $(HEADLAMP_START_SCRIPT). Run 'make k3s-platform' first."; exit 1)
	"$(HEADLAMP_START_SCRIPT)"

headlamp-token:
	@test -f "$(K8S_TUNNELED_KUBECONFIG)" || (echo "Missing $(K8S_TUNNELED_KUBECONFIG). Run 'make k3s-cluster' first."; exit 1)
	KUBECONFIG="$(K8S_TUNNELED_KUBECONFIG)" kubectl create token headlamp-admin -n kube-system
