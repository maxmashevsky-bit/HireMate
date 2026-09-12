.PHONY: bootstrap build test lint verify source-check
bootstrap:
	./scripts/bootstrap.sh
build:
	./scripts/build.sh
test:
	./scripts/test.sh
lint:
	./scripts/lint.sh
verify:
	./scripts/verify.sh
source-check:
	./scripts/verify.sh --source-only
