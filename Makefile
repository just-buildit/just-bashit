SHELL := bash

all: lint test

TESTHELPER_PATH = test/test_helper
REPORT_PATH     = test-results
ARTIFACT        = just-bashit.tar.gz
BATS            ?= $(shell command -v bats 2>/dev/null || echo test/bats/bin/bats)

.PHONY: all lint test clean

$(REPORT_PATH):
	mkdir -p $(REPORT_PATH)

lint:
	shellcheck src/*.sh

test: $(REPORT_PATH)
	$(BATS) \
		--report-formatter junit \
		--output $(REPORT_PATH) \
		--print-output-on-failure \
		--show-output-of-passing-tests \
		test
	tar -czf $(ARTIFACT) src $(REPORT_PATH)
	rm -f $(TESTHELPER_PATH)/bats-*/*.json

clean:
	rm -rf $(ARTIFACT) $(REPORT_PATH)
	git -C $(TESTHELPER_PATH)/bats-assert restore .
	git -C $(TESTHELPER_PATH)/bats-support restore .
