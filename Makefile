SHELL := bash

UV              ?= uv
TESTHELPER_PATH  = test/test_helper
REPORT_PATH      = test-results
ARTIFACT         = just-bashit.tar.gz
BATS            ?= $(shell command -v bats 2>/dev/null || echo test/bats/bin/bats)

.PHONY: all lint test test-fast coverage docs docs-serve \
        setup bump-version check-version release-branch tag-release \
        clean help

# ── default ───────────────────────────────────────────────────────────────────
all: lint test

# ── lint ──────────────────────────────────────────────────────────────────────
lint:
	@test -f .git/hooks/pre-commit || pre-commit install
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

# ── setup ─────────────────────────────────────────────────────────────────────
setup:
	$(UV) sync
	pre-commit install

# ── release ───────────────────────────────────────────────────────────────────
bump-version:
ifndef VERSION
	@echo "usage: make bump-version VERSION=<x.y.z>"
	@exit 1
endif
	uvx bump-my-version bump --new-version $(VERSION) --no-commit --no-tag patch
	@echo "Bumped to $(VERSION)"
	@echo "Next: commit, push PR, merge, then:"
	@echo "      git checkout main && git pull && make tag-release VERSION=$(VERSION)"

check-version:
ifndef VERSION
	@echo "usage: make check-version VERSION=<x.y.z>"
	@exit 1
endif
	@GOT=$$(grep '^version = ' pyproject.toml | sed 's/.*"\(.*\)".*/\1/'); \
	 if [ "$$GOT" != "$(VERSION)" ]; then \
	     echo "ERROR: pyproject.toml has $$GOT, expected $(VERSION)"; exit 1; \
	 fi; \
	 echo "Version OK: $(VERSION)"

release-branch:
ifndef VERSION
	@echo "usage: make release-branch VERSION=<x.y.z>"
	@exit 1
endif
	git checkout -b chore/release-$(VERSION) origin/main
	$(MAKE) bump-version VERSION=$(VERSION)
	@echo "  - git commit -am 'chore: release v$(VERSION)', push PR, merge"
	@echo "  - then: git checkout main && git pull && make tag-release"

tag-release:
ifndef VERSION
	@echo "usage: make tag-release VERSION=<x.y.z>"
	@exit 1
endif
	@git fetch origin main
	@CURRENT=$$(git rev-parse HEAD); \
	 ORIGIN=$$(git rev-parse origin/main); \
	 if [ "$$CURRENT" != "$$ORIGIN" ]; then \
	     echo "ERROR: not at origin/main — checkout main and pull first"; \
	     exit 1; \
	 fi
	$(MAKE) check-version VERSION=$(VERSION)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"
	@echo "Tagged v$(VERSION) — release workflow starting on GitHub"

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
	@echo "  make setup         one-time: uv sync + pre-commit install"
	@echo "  make lint          run pre-commit hooks on all files"
	@echo "  make test          run full bats test suite"
	@echo "  make test-fast     stop on first failure"
	@echo "  make coverage      run kcov coverage report"
	@echo "  make docs          build docs site (zensical)"
	@echo "  make docs-serve    serve docs locally (zensical)"
	@echo "  make bump-version VERSION=x.y.z  update version everywhere"
	@echo "  make check-version VERSION=x.y.z verify version matches"
	@echo "  make release-branch VERSION=x.y.z create release branch"
	@echo "  make tag-release VERSION=x.y.z   tag + push to trigger release"
	@echo "  make clean         remove build artifacts"
	@echo "  make help          show this message"
	@echo ""
