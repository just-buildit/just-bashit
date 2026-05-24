SHELL := bash

all: lint test

TESTHELPER_PATH = test/test_helper
REPORT_PATH     = test-results
ARTIFACT        = just-bashit.tar.gz
BATS            ?= $(shell command -v bats 2>/dev/null || echo test/bats/bin/bats)

.PHONY: all lint test coverage clean

$(REPORT_PATH):
	mkdir -p $(REPORT_PATH)

lint:
	shellcheck src/*.sh

test: $(REPORT_PATH)
	$(BATS) \
		--report-formatter junit \
		--output $(REPORT_PATH) \
		--print-output-on-failure \
		test
	tar -czf $(ARTIFACT) src $(REPORT_PATH)
	rm -f $(TESTHELPER_PATH)/bats-*/*.json

coverage: $(REPORT_PATH)
	for f in test/*.bats; do \
		kcov --collect-only \
			--include-pattern=/src \
			--exclude-pattern=/test \
			$(REPORT_PATH)/coverage \
			$(BATS) "$$f" >/dev/null 2>&1 || true; \
	done
	kcov --report-only \
		--include-pattern=/src \
		--exclude-pattern=/test \
		$(REPORT_PATH)/coverage

clean:
	rm -rf $(ARTIFACT) $(REPORT_PATH)
	git -C $(TESTHELPER_PATH)/bats-assert restore .
	git -C $(TESTHELPER_PATH)/bats-support restore .
