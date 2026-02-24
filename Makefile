BATS := bats

.PHONY: test test-unit test-integration

test: test-unit test-integration

test-unit:
	$(BATS) tests/unit/

test-integration:
	$(BATS) tests/integration/
