SHELL := /bin/bash

PROJECT_ID ?= lyrical-art-482604-c9
TF_DIR     ?= terraform
TAG        ?= v1
PROXY_PORT ?= 5432
PYTHON     ?= python3

.PHONY: help tf-init tf-apply infra push rollout deploy bootstrap srcdeploy cloudrun-url health alembic

help:
	@echo "make bootstrap TAG=v1      # 基盤(terraform apply) -> push -> 切替(terraform apply)"
	@echo "make deploy TAG=v1         # push -> 切替(terraform apply)"
	@echo "make push TAG=v1           # build&push のみ"
	@echo "make rollout TAG=v1        # イメージ差し替え(terraform apply) のみ（pushしない）"
	@echo "make srcdeploy TAG=v1      # (互換) deploy と同じ"
	@echo "make alembic              # cloud-sql-proxy経由で alembic upgrade head"
	@echo "make health               # Cloud Run /health を curl"
	@echo "make cloudrun-url         # Cloud Run URL を表示"
	@echo "make tf-init              # terraform init"
	@echo "make tf-apply             # terraform apply"

tf-init:
	terraform -chdir=$(TF_DIR) init

tf-apply:
	terraform -chdir=$(TF_DIR) apply

infra:
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) apply

# build&push のみ（Cloud Build）
push:
	set -euo pipefail; \
	IMAGE="$$(terraform -chdir=$(TF_DIR) output -raw image_repository)"; \
	echo "build&push -> $${IMAGE}:$(TAG)"; \
	gcloud builds submit --project $(PROJECT_ID) --tag "$${IMAGE}:$(TAG)" .

# イメージ差し替え(terraform apply) のみ（pushしない）
rollout:
	set -euo pipefail; \
	IMAGE="$$(terraform -chdir=$(TF_DIR) output -raw image_repository)"; \
	echo "update terraform.tfvars container_image -> $${IMAGE}:$(TAG)"; \
	if [[ "$$(uname)" == "Darwin" ]]; then \
	  sed -i '' -E "s#^container_image *= *\\\".*\\\"#container_image = \\\"$${IMAGE}:$(TAG)\\\"#g" "$(TF_DIR)/terraform.tfvars"; \
	else \
	  sed -i -E "s#^container_image *= *\\\".*\\\"#container_image = \\\"$${IMAGE}:$(TAG)\\\"#g" "$(TF_DIR)/terraform.tfvars"; \
	fi; \
	echo "terraform apply"; \
	terraform -chdir=$(TF_DIR) apply -auto-approve; \
	echo "Done. URL=$$(terraform -chdir=$(TF_DIR) output -raw cloud_run_url)"

deploy: push rollout

# 基盤(terraform apply)から、push・切替まで一気通貫
bootstrap: infra deploy

# 互換（既存README/手順用）
srcdeploy: deploy

cloudrun-url:
	terraform -chdir=$(TF_DIR) output -raw cloud_run_url

health:
	set -euo pipefail; \
	URL="$$(terraform -chdir=$(TF_DIR) output -raw cloud_run_url)"; \
	curl -sS "$${URL}/health"; echo

# Cloud Run上で自動実行しない方針のため、ローカルから Cloud SQL Proxy 経由で実行
alembic:
	set -euo pipefail; \
	command -v cloud-sql-proxy >/dev/null 2>&1 || (echo "cloud-sql-proxy が見つかりません。先にインストールしてください。" && exit 1); \
	"$(PYTHON)" -c 'import alembic' >/dev/null 2>&1 || (echo "Pythonから alembic を import できません。まず同じPython環境に依存を入れてください: $(PYTHON) -m pip install -r requirements.txt" && exit 1); \
	CONN="$$(terraform -chdir=$(TF_DIR) output -raw cloudsql_connection_name)"; \
	SECRET_ID="$$(terraform -chdir=$(TF_DIR) output -raw db_password_secret_id)"; \
	echo "[1/3] start cloud-sql-proxy (port $(PROXY_PORT)) -> $${CONN}"; \
	cloud-sql-proxy --port $(PROXY_PORT) "$${CONN}" & \
	PROXY_PID="$$!"; \
	trap 'echo; echo "stopping proxy $$PROXY_PID"; kill $$PROXY_PID >/dev/null 2>&1 || true' EXIT; \
	sleep 2; \
	echo "[2/3] get DB password from Secret Manager"; \
	DB_PASSWORD="$$(gcloud secrets versions access latest --secret="$${SECRET_ID}" --project $(PROJECT_ID))"; \
	echo "[3/3] alembic upgrade head"; \
	export DATABASE_URL="postgresql+psycopg://app:$${DB_PASSWORD}@127.0.0.1:$(PROXY_PORT)/app"; \
	"$(PYTHON)" -c 'from alembic.config import main; main()' upgrade head; \
	echo "Done."


