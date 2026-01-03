# gcp_cloudsql (STEP2: DB接続・マイグレーション・Todo CRUD)

FastAPI + PostgreSQL を **Docker / docker-compose** でローカル起動し、**SQLAlchemy(Async) + Alembic + Todo CRUD** まで動かせる構成です（GCP/Cloud Run は考慮しません）。

## 技術スタック

- Python 3.11
- FastAPI
- Uvicorn
- SQLAlchemy 2.x (async)
- asyncpg
- Alembic
- psycopg (alembic用 sync driver)
- PostgreSQL 16
- Docker / docker-compose

## ディレクトリ構成

```text
.
├─ alembic/
│  ├─ env.py
│  └─ versions/
├─ app/
│  ├─ api/
│  │  └─ todos.py
│  ├─ db/
│  │  ├─ base.py
│  │  ├─ models.py
│  │  └─ session.py
│  ├─ schemas/
│  │  └─ todo.py
│  ├─ main.py
│  └─ settings.py
├─ alembic.ini
├─ Dockerfile
├─ docker-compose.yml
├─ requirements.txt
├─ .env
└─ .env.example
```

## 使い方

```bash
cp .env.example .env
docker-compose up --build
```

## マイグレーション（手動）

起動後に別ターミナルで実行します。

```bash
docker-compose exec api alembic upgrade head
```

## ブラウザで確認

- `http://localhost:8000/health`
- `http://localhost:8000/docs`

## STEP4: GCP (Cloud Run + Cloud SQL) へデプロイ（Terraform + Makefile）

前提:

- `gcloud auth login` 済み
- ADC（`application_default_credentials.json`）作成済み
- Project: `lyrical-art-482604-c9`
- Region: `asia-northeast1`

### 1) Terraform init / apply（基盤作成）

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### 2) ソースをデプロイ（build&push → Cloud Run差し替え）

```bash
cd /Users/takadahideaki/Documents/study/gcp_cloudsql
make srcdeploy TAG=v1
```

### 3) URL確認 & 動作確認

```bash
make health
open "$(make -s cloudrun-url)/docs"
```

### 4) マイグレーション（手動・自動実行しない）

Cloud Run で `alembic upgrade` は自動実行しません（STEP5で扱います）。

ローカルから Cloud SQL Auth Proxy を使って実行します（Makefileにまとめています）。

注意: `make alembic` はローカルのPython環境で Alembic を実行するため、事前に依存をインストールしてください（例: `python -m pip install -r requirements.txt`）。\n+Python環境を切り替えている場合は `make alembic PYTHON=...` で明示できます（例: `make alembic PYTHON=.venv/bin/python`）。

```bash
cd /Users/takadahideaki/Documents/study/gcp_cloudsql
make alembic
```

### 5) 削除（課金停止）

```bash
cd terraform
terraform destroy
```

#### destroy が失敗する場合（PostgreSQL: DBが利用中 / roleに依存オブジェクトあり）

Cloud SQL(PostgreSQL) では、**接続中のDBは削除できません**。また、`app` ユーザー（PostgreSQL role）がテーブル等の**所有者**になっている場合、DBや所有物が残っていると role も削除できません。

今回の典型エラー:

- `pq: database "app" is being accessed by other users.`
- `role "app" cannot be dropped because some objects depend on it`

対応（最短）:

- **Cloud Run を先に停止/削除**（すでに `terraform destroy` で Cloud Run は消えているはずです）
- `app` DB への接続を **全て切断**（接続プール/プロキシ/手元の psql 等）
- その後に `terraform destroy` を再実行

管理ユーザー（例: `postgres`）で `postgres` DB に接続できる場合は、以下で強制的に接続を切れます:

```sql
-- postgres DB に接続した状態で実行
REVOKE CONNECT ON DATABASE app FROM PUBLIC;
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'app' AND pid <> pg_backend_pid();
```

その後、`terraform destroy` を再実行してください。
