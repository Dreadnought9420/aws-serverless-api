# Developer entry points. Every target is safe to run repeatedly.
#
#   make check    everything CI runs, locally
#   make plan     plan the workload stack
#   make apply    apply the workload stack

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

TF_DIRS    := bootstrap terraform modules/static_site modules/serverless_api modules/observability modules/cost_guardrails
TEST_DIRS  := modules/static_site modules/serverless_api modules/observability modules/cost_guardrails
STACK_DIR  := terraform
DIAGRAM    := docs/diagrams/architecture.drawio
DRAWIO     ?= drawio

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: check
check: fmt-check validate lint test scan python ## Run every static check and unit test

.PHONY: fmt
fmt: ## Rewrite Terraform files to canonical format
	terraform fmt -recursive

.PHONY: fmt-check
fmt-check: ## Fail if any file is not canonically formatted
	terraform fmt -check -recursive -diff

.PHONY: validate
validate: ## terraform validate every directory
	@for dir in $(TF_DIRS); do \
		echo "==> $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$dir validate; \
	done

.PHONY: lint
lint: ## Run tflint across the repository
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl" --format compact

.PHONY: test
test: ## Run the mocked Terraform unit tests
	@for dir in $(TEST_DIRS); do \
		echo "==> $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$dir test; \
	done

.PHONY: scan
scan: ## Run Checkov and Trivy
	checkov --config-file .checkov.yaml
	trivy config --config trivy.yaml .

.PHONY: python
python: ## Lint and type check the Lambda handler
	ruff check src/api
	ruff format --check src/api
	mypy src/api

.PHONY: docs
docs: ## Regenerate the module README tables with terraform-docs
	@for dir in $(TF_DIRS); do \
		terraform-docs markdown table --output-file README.md --output-mode inject $$dir; \
	done

.PHONY: init
init: ## Initialise the workload stack against the remote backend
	terraform -chdir=$(STACK_DIR) init -backend-config=backend.hcl -input=false

.PHONY: plan
plan: ## Plan the workload stack
	terraform -chdir=$(STACK_DIR) plan -input=false -lock-timeout=5m -out=tfplan

.PHONY: apply
apply: ## Apply the plan produced by `make plan`
	terraform -chdir=$(STACK_DIR) apply -input=false -lock-timeout=5m tfplan

.PHONY: output
output: ## Show the stack outputs
	terraform -chdir=$(STACK_DIR) output

.PHONY: destroy-plan
destroy-plan: ## Show exactly what a destroy would remove. Always run this first.
	terraform -chdir=$(STACK_DIR) plan -destroy -input=false -out=tfdestroy
	terraform -chdir=$(STACK_DIR) show tfdestroy

.PHONY: destroy
destroy: ## Apply the reviewed destroy plan from `make destroy-plan`
	terraform -chdir=$(STACK_DIR) apply -input=false tfdestroy

.PHONY: invalidate
invalidate: ## Invalidate the CloudFront cache
	aws cloudfront create-invalidation \
		--distribution-id "$$(terraform -chdir=$(STACK_DIR) output -raw cloudfront_distribution_id)" \
		--paths '/*'

.PHONY: diagram
diagram: ## Export the architecture diagram to PNG and SVG
	$(DRAWIO) -x -f png -e -s 2 -o docs/diagrams/architecture.drawio.png $(DIAGRAM)
	$(DRAWIO) -x -f svg -e -o docs/diagrams/architecture.svg $(DIAGRAM)

.PHONY: hooks
hooks: ## Install the pre-commit hooks
	pre-commit install
	pre-commit run --all-files
