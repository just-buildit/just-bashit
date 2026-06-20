SHELL := bash

UV              ?= uv
TESTHELPER_PATH  = test/test_helper
REPORT_PATH      = test-results
ARTIFACT         = just-bashit.tar.gz
BATS            ?= $(shell command -v bats 2>/dev/null || echo test/bats/bin/bats)

.PHONY: all lint test test-fast coverage docs docs-serve clean help

# ── default ───────────────────────────────────────────────────────────────────
all: lint test

# ── lint ──────────────────────────────────────────────────────────────────────
lint:
	$(UV) run pre-commit run --all-files

# ── test ──────────────────────────────────────────────────────────────────────
$(REPORT_PATH):
	mkdir -p $(REPORT_PATH)

test: $(REPORT_PATH)
	$(BATS) \
		--report-formatter junit \
		--output $(REPORT_PATH) \
		--print-output-on-failure \
		test
	tar -czf $(ARTIFACT) src $(REPORT_PATH)
	rm -f $(TESTHELPER_PATH)/bats-*/*.json

test-fast:
	$(BATS) --abort test

# ── docs ──────────────────────────────────────────────────────────────────────
docs:
	$(UV) run zensical build --clean

docs-serve:
	$(UV) run zensical serve

# ── coverage ──────────────────────────────────────────────────────────────────
coverage: $(REPORT_PATH)
	kcov \
		--include-pattern=/src \
		--exclude-pattern=/test \
		$(REPORT_PATH)/coverage \
		$(BATS) test

# ── clean ─────────────────────────────────────────────────────────────────────
clean:
	rm -rf $(ARTIFACT) $(REPORT_PATH) site/
	git -C $(TESTHELPER_PATH)/bats-assert restore .
	git -C $(TESTHELPER_PATH)/bats-support restore .

# ── help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  just-bashit development"
	@echo ""
	@echo "  make               lint then test"
	@echo "  make lint          run pre-commit hooks on all files"
	@echo "  make test          run full bats test suite"
	@echo "  make test-fast     stop on first failure"
	@echo "  make coverage      run kcov coverage report"
	@echo "  make docs          build docs site (zensical)"
	@echo "  make docs-serve    serve docs locally (zensical)"
	@echo "  make clean         remove build artifacts"
	@echo "  make help          show this message"
	@echo ""
