VERSION = 1.11.1
TAG = $(VERSION)
PREFIX = nginx/nginx-ingress
TARGET ?= local

override DOCKER_BUILD_OPTIONS += --build-arg IC_VERSION=$(VERSION)-$(GIT_COMMIT) --build-arg GIT_COMMIT=$(GIT_COMMIT) --build-arg VERSION=$(VERSION)
DOCKER_CMD = docker build $(DOCKER_BUILD_OPTIONS) --target $(TARGET) -f build/Dockerfile -t $(PREFIX):$(TAG) .
PLUS_ARGS = --build-arg PLUS=-plus --secret id=nginx-repo.crt,src=nginx-repo.crt --secret id=nginx-repo.key,src=nginx-repo.key

GIT_COMMIT = $(shell git rev-parse --short HEAD)

export DOCKER_BUILDKIT = 1

.DEFAULT_GOAL:=help

.PHONY: help
help: ## Display this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "; printf "Usage:\n\n    make \033[36m<target>\033[0m [VARIABLE=value...]\n\nTargets:\n\n"}; {printf "    \033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: test lint verify-codegen update-crds debian-image

.PHONY: lint
lint: ## Run linter
	go run github.com/golangci/golangci-lint/cmd/golangci-lint run

.PHONY: test
test: ## Run tests
	GO111MODULE=on go test ./...

.PHONY: verify-codegen
verify-codegen: ## Verify code generation
	./hack/verify-codegen.sh

.PHONY: update-codegen
update-codegen: ## Generate code
	./hack/update-codegen.sh

.PHONY: update-crds
update-crds: ## Update CRDs
	go run sigs.k8s.io/controller-tools/cmd/controller-gen crd:crdVersions=v1 schemapatch:manifests=./deployments/common/crds/ paths=./pkg/apis/configuration/... output:dir=./deployments/common/crds
	@cp -Rp deployments/common/crds/ deployments/helm-chart/crds

.PHONY: certificate-and-key
certificate-and-key: ## Create default cert and key
	./build/generate_default_cert_and_key.sh

.PHONY: build
build: ## Build Ingress Controller binary
	@docker -v || (code=$$?; printf "\033[0;31mError\033[0m: there was a problem with Docker\n"; exit $$code)
ifeq (${TARGET},local)
	@go version || (code=$$?; printf "\033[0;31mError\033[0m: unable to build locally, try using the parameter TARGET=container\n"; exit $$code)
	CGO_ENABLED=0 GO111MODULE=on GOFLAGS='$(GOFLAGS)' GOOS=linux go build -ldflags "-s -w -X main.version=${VERSION} -X main.gitCommit=${GIT_COMMIT}" -o nginx-ingress github.com/nginxinc/kubernetes-ingress/cmd/nginx-ingress
endif

.PHONY: debian-image
debian-image: build ## Create Docker image for Ingress Controller (debian)
	$(DOCKER_CMD) --build-arg BUILD_OS=debian

.PHONY: alpine-image
alpine-image: build ## Create Docker image for Ingress Controller (alpine)
	$(DOCKER_CMD) --build-arg BUILD_OS=alpine

.PHONY: debian-image-plus
debian-image-plus: build ## Create Docker image for Ingress Controller (nginx plus)
	$(DOCKER_CMD) $(PLUS_ARGS) --build-arg BUILD_OS=debian-plus

.PHONY: debian-image-nap-plus
debian-image-nap-plus: build ## Create Docker image for Ingress Controller (nginx plus with nap)
	$(DOCKER_CMD) $(PLUS_ARGS) --build-arg BUILD_OS=debian-plus-ap

.PHONY: openshift-image
openshift-image: build ## Create Docker image for Ingress Controller (openshift)
	$(DOCKER_CMD) --build-arg BUILD_OS=openshift

.PHONY: openshift-image-plus
openshift-image-plus: build ## Create Docker image for Ingress Controller (openshift with plus)
	$(DOCKER_CMD) $(PLUS_ARGS) --build-arg BUILD_OS=openshift-plus

.PHONY: openshift-image-nap-plus
openshift-image-nap-plus: build ## Create Docker image for Ingress Controller (openshift with plus and nap)
	docker build $(DOCKER_BUILD_OPTIONS) --target $(TARGET) $(PLUS_ARGS) --secret id=rhel_license,src=rhel_license -f build/DockerfileWithAppProtectForPlusForOpenShift -t $(PREFIX):$(TAG) .

.PHONY: debian-image-opentracing
debian-image-opentracing: build ## Create Docker image for Ingress Controller (with opentracing)
	$(DOCKER_CMD) --build-arg BUILD_OS=opentracing

.PHONY: debian-image-opentelemetry
debian-image-opentelemetry: build ## Create Docker image for Ingress Controller (with opentelemetry)
	$(DOCKER_CMD) --build-arg BUILD_OS=opentelemetry

.PHONY: debian-image-opentracing-plus
debian-image-opentracing-plus: build ## Create Docker image for Ingress Controller (with opentracing and plus)
	$(DOCKER_CMD) $(PLUS_ARGS) --build-arg BUILD_OS=opentracing-plus

.PHONY: all-images ## Create all the Docker images for Ingress Controller
all-images: debian-image alpine-image debian-image-plus openshift-image debian-image-opentracing debian-image-opentracing-plus openshift-image-plus openshift-image-nap-plus debian-image-nap-plus

.PHONY: push
push: ## Docker push to $PREFIX and $TAG
	docker push $(PREFIX):$(TAG)

.PHONY: clean
clean:  ## Remove nginx-ingress binary
	-rm nginx-ingress

.PHONY: deps
deps: ## Add missing and remove unused modules, verify deps and dowload them to local cache
	@go mod tidy && go mod verify && go mod download

.PHONY: clean-cache
clean-cache: ## Clean go cache
	@go clean -modcache
