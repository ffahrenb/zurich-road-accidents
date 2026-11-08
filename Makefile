# Everything runs inside the pinned container image; R is not needed on the host.
#   make build   build the image
#   make run     run the pipeline (tar_make); set ZH_PRIVATE_ACCIDENTS=/path/to/private.csv for Track X
#   make test    testthat suite incl. privacy gate
#   make lint    lintr (R) + sqlfluff (SQL)
#   make site    render the Quarto site to site/_site
#   make hooks   install the privacy pre-commit hook
#   make all     build, lint, test, run, test (privacy gate on fresh outputs), site
IMAGE   ?= localhost/zh-unfaelle:dev
MEMORY  ?= 12g
PODMAN  ?= podman
RUN      = $(PODMAN) run --rm --memory $(MEMORY) -v $(CURDIR):/work:Z

# The private exact-date file is mounted read-only, only for `make run` and only when set on
# the host. label=disable instead of :Z so the host file is not relabelled.
ifdef ZH_PRIVATE_ACCIDENTS
PRIVATE_MOUNT = --security-opt label=disable -v $(ZH_PRIVATE_ACCIDENTS):/private/unfaelle.csv:ro \
                -e ZH_PRIVATE_ACCIDENTS=/private/unfaelle.csv
else
PRIVATE_MOUNT =
endif

.PHONY: all build run test lint lint-r lint-sql site hooks

# test runs twice on purpose: before the pipeline (code) and after it (privacy gate on fresh exports)
all: build lint test
	$(MAKE) run
	$(MAKE) test
	$(MAKE) site

build:
	$(PODMAN) build -t $(IMAGE) -f docker/Containerfile .

run:
	$(RUN) $(PRIVATE_MOUNT) $(IMAGE) Rscript -e 'targets::tar_make()'

test:
	$(RUN) $(IMAGE) Rscript tests/testthat.R

lint: lint-r lint-sql

lint-r:
	$(RUN) $(IMAGE) Rscript tests/lint.R

lint-sql:
	$(RUN) $(IMAGE) sqlfluff lint sql/

site:
	$(RUN) $(IMAGE) quarto render site/

hooks:
	@hooks="$$(git rev-parse --git-path hooks)"; \
	mkdir -p "$$hooks"; \
	ln -sf "$(CURDIR)/tools/privacy-precommit.sh" "$$hooks/pre-commit"; \
	chmod +x tools/privacy-precommit.sh; \
	echo "pre-commit hook installed: $$hooks/pre-commit"
