NVIM ?= nvim
DEPS := nvim-lua/plenary.nvim mfussenegger/nvim-dap nvim-neotest/nvim-nio
# Directory holding the dependencies; defaults to lazy.nvim's plugin directory.
export DEPS_DIR NVIM

.PHONY: test deps

test:
	sh scripts/test

deps:
	@mkdir -p .deps
	@for r in $(DEPS); do d=".deps/$${r#*/}"; [ -d "$$d" ] || git clone -q --depth 1 "https://github.com/$$r" "$$d"; done
