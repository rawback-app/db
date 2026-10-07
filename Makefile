# Local build and smoke test. DOCKER=podman works for every target.
DOCKER   ?= docker
IMAGE    ?= rawback-db:dev
NAME     ?= rawback-db
PORT     ?= 5432
PASSWORD ?= postgres

.PHONY: build test run stop psql

build:
	$(DOCKER) build -t $(IMAGE) .

test: build
	DOCKER=$(DOCKER) test/smoke.sh $(IMAGE)

run: build
	$(DOCKER) run -d --name $(NAME) --shm-size=256m \
		-e POSTGRES_PASSWORD=$(PASSWORD) \
		-p 127.0.0.1:$(PORT):5432 \
		-v $(NAME)-data:/var/lib/postgresql \
		$(IMAGE)

stop:
	$(DOCKER) rm -f $(NAME)

psql:
	$(DOCKER) exec -it $(NAME) psql -U postgres
