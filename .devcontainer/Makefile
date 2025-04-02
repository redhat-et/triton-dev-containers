VARIANTS := triton triton-cpu triton-amd
BASE_DIR := $(CURDIR)

##@ Devcontainer

.PHONY: all generate clean help list

all: generate ## Default: generate all devcontainer.json files

generate: ## Generate all or a specific devcontainer.json file
	@echo "Running generate-devcontainers.sh$(if $(v), for variant '$(v)',)..."
	@./scripts/generate-devcontainers.sh $(v)
	@echo "Devcontainer generation complete."

##@ Utilities

list: ## List all variants
	@echo "Variants:"
	@for v in $(VARIANTS); do echo " - $$v"; done

clean: ## Remove all generated devcontainer.json files
	@for v in $(VARIANTS); do \
	  echo "Removing $$v/devcontainer.json"; \
	  rm -f $(BASE_DIR)/$$v/devcontainer.json; \
	  echo "Removing $$v/user.sh"; \
	  rm -f $(BASE_DIR)/$$v/user.sh; \
	  echo "Removing $$v/postStartCommand.sh"; \
	  rm -f $(BASE_DIR)/$$v/postStartCommand.sh; \
	done

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
