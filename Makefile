all: lint test

TESTHELPER_PATH = test/test_helper
REPORT_PATH     = test-results
ARTIFACT        = just-bashit.tar.gz

.PHONY: all lint test clean

$(REPORT_PATH):
	mkdir -p $(REPORT_PATH)

lint:
	shellcheck src/*.sh

test: $(REPORT_PATH)
	kcov \
		--dump-summary \
		--include-pattern=/src \
		--exclude-pattern=/test \
		$(REPORT_PATH)/coverage \
		bats test
	bats --report-formatter junit --output $(REPORT_PATH) test
	tar -czf $(ARTIFACT) src $(REPORT_PATH)
	rm -f $(TESTHELPER_PATH)/bats-*/*.json

test-bats: $(REPORT_PATH)
	bats --report-formatter junit --output $(REPORT_PATH) test

clean:
	rm -rf $(ARTIFACT) $(REPORT_PATH)
	git -C $(TESTHELPER_PATH)/bats-assert restore .
	git -C $(TESTHELPER_PATH)/bats-support restore .
