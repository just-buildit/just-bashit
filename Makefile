all : lint test

MAKEHOME := $(CURDIR)
ARTIFACT = just-bashit.tar.gz
TESTHELPER_PATH = test/test_helper
REPORT_PATH = test-results
SONARQUBE_PATH = ./gcovr
TOJUNIT = $(TESTHELPER_PATH)/checkstyle2junit.xslt
.PHONY : lint
lint : test
	shellcheck -f checkstyle src/*.sh | \
		xmlstarlet tr $(TOJUNIT) > $(REPORT_PATH)/shellcheck.xml

$(REPORT_PATH) :
	mkdir -p $(REPORT_PATH)

# Use kcov to run bats and compute coverage
.PHONY: test
test : $(REPORT_PATH) 
	kcov \
		--dump-summary \
		--include-pattern=/src \
		--exclude-pattern=/test \
		$(REPORT_PATH)/coverage \
		./test/bats/bin/bats test
	mkdir -p $(SONARQUBE_PATH)
	cp $(REPORT_PATH)/coverage/bats.*/sonarqube.xml \
		$(SONARQUBE_PATH)/sonarqube-report.xml
	tar -cvzf $(ARTIFACT) src $(REPORT_PATH)
	rm -f $(TESTHELPER_PATH)/bats-*/*.json

# Remove test & build artifacts and restore helpers
clean : 
	rm -rf $(ARTIFACT) $(REPORT_PATH) $(SONARQUBE_PATH)
	git -C $(TESTHELPER_PATH)/bats-assert restore .
	git -C $(TESTHELPER_PATH)/bats-support restore .