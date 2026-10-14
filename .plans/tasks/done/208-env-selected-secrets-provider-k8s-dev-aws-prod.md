---
task: 208
title: Env-selected secrets provider — k8s for dev, AWS Secrets Manager for prod
status: done
depends_on: []
---

# 208 — Env-selected secrets provider — k8s for dev, AWS Secrets Manager for prod

**Clone:** `workspace-2/hrms/` (current branch there: `feature/gowtham_HrmsDevConfig`, which
already carries the k8s `.env` merge this task builds on — check `git -C workspace-2/hrms
status -sb` before starting). Backend commands run from `workspace-2/hrms/backend/`.

## Background — what we're copying from Nextenti

The Nextenti Java app (`/home/solo/Nextenti/Nextenti-JavaApp`) picks its secret source from
one env var baked into each image:

| Image | Env baked in | What happens at startup |
|---|---|---|
| `Dockerfile-Dev` | `SPRING_PROFILES_ACTIVE=k8s,dev`, `K8S_SECRETS_PATH=/etc/nextenti/secrets` | `KubernetesSecretsProvider` reads the k8s Secret |
| `Dockerfile-Prod` | `SPRING_PROFILES_ACTIVE=aws,prod`, `AWS_SECRET_NAME=nextenti`, `AWS_REGION=ap-south-1` | `AwsSecretsProvider` calls Secrets Manager `GetSecretValue(AWS_SECRET_NAME)` |
| neither token | — | nothing loaded (logs "no secrets loaded") |

Dispatch lives in `src/main/java/com/nextenti/services/app/config/secrets/SecretsEnvironmentPostProcessor.java`:
`aws` → AWS provider, else `k8s` → k8s provider, else no-op. It runs before any bean is
built, and the secrets it loads take precedence over every other property source (`addFirst`).
The AWS secret is **one flat JSON object of CAPS_UNDERSCORE keys**, and credentials come from
the SDK default chain (env → `~/.aws` → the IAM task/pod role).

HRMS today has only the k8s half, and it isn't explicitly gated:
`backend/app/core/config.py` calls
`app/core/secrets_bootstrap.py:merge_pod_env_into_dotenv(".env", <Settings field names>)`
before `Settings()`, and that runs whenever `KUBERNETES_SERVICE_HOST` is set (see
`docs/secrets-config.md`). Prod (ECS Fargate) currently expects every secret to be injected as
an individual task-definition env var.

## Scope

Add an explicit, env-selected secrets provider to the backend so that:

- **`SECRETS_PROVIDER=k8s`** (dev k8s image) → run the existing `merge_pod_env_into_dotenv`,
  unchanged in behaviour. **Only** in this case.
- **`SECRETS_PROVIDER=aws`** (prod image) → fetch `AWS_SECRET_NAME` from AWS Secrets Manager
  in `AWS_REGION` and load its keys into the process env before `Settings()` is built. **Only**
  in this case.
- **unset / empty** (laptop, docker compose, pytest, Alembic run locally) → do nothing. No
  boto3 call, no `.env` write.
- **any other value** → raise at startup with a clear message naming the bad value (a typo
  must not silently boot prod on dev defaults).

Behaviour to implement:

1. **Dispatcher** — new `load_secrets(known_keys, environ=None)` in
   `app/core/secrets_bootstrap.py` (keep the module; one place for secret loading). Read
   `SECRETS_PROVIDER` from the OS env only (not `.env`/`Settings`), like Nextenti reads
   `SPRING_PROFILES_ACTIVE` straight from `System.getenv`, since `Settings` isn't built yet.
   `config.py` calls `load_secrets(...)` instead of `merge_pod_env_into_dotenv(...)`.
2. **k8s path** — gate `merge_pod_env_into_dotenv` on `SECRETS_PROVIDER=k8s` instead of
   `KUBERNETES_SERVICE_HOST`. Keep the `KUBERNETES_SERVICE_HOST` check too as a second guard
   (k8s selected but not in a pod → WARNING, skip), so a laptop running with the var set never
   rewrites the developer's `.env`.
3. **AWS path** — `fetch_aws_secrets(secret_name, region)`:
   - `boto3.client("secretsmanager", region_name=region, config=botocore.config.Config(
     connect_timeout=5, read_timeout=10, retries={"max_attempts": 3}))` → `get_secret_value(
     SecretId=secret_name)["SecretString"]`. boto3 is already a dependency
     (`pyproject.toml: boto3>=1.35.0`). Credentials come from the default chain: the ECS
     **task role** in prod, never baked-in keys.
   - `SecretString` must parse as a flat JSON object. String values are taken as-is; numbers
     and bools are converted with `str()` (JSON `true` → `"true"`, which pydantic accepts);
     nested objects/arrays → error naming the key.
   - Defaults: `AWS_SECRET_NAME` has **no default**. If it's missing, raise (Nextenti falls back
     to `nextenti`, which would quietly read another app's secret here). `AWS_REGION` defaults
     to `ap-south-1`.
   - Inject every key into `os.environ`, **overriding** any value already there. This matches
     Nextenti's `addFirst` (the secret store beats image `ENV` lines) and makes keys the code
     reads straight from `os.environ` work too (`TRUST_PROXY_HEADERS`, `DEVICE_PUSH_HOST`,
     `ENABLE_BIOMETRIC_RELAY`, `RAILS_DB_*`). Never let the secret overwrite the bootstrap
     keys `SECRETS_PROVIDER`, `AWS_SECRET_NAME`, `AWS_REGION`: skip them with a WARNING.
   - Multi-line values (the `CRYPTO_PRIVATE_KEY` PEM) arrive as JSON strings with `\n`, so they
     go into `os.environ` intact. Nothing is written to `.env` on this path. Prod containers
     are ephemeral, and keeping secrets off disk is the point.
4. **Fail fast in prod (deliberate deviation from Nextenti).** Nextenti's `AwsSecretsProvider`
   swallows every exception and returns an empty map. For HRMS that would boot prod on the
   `Settings` defaults (`secret_key="dev-secret-change-me"`, the localhost `database_url`). So
   on the `aws` path, any failure (no credentials, AccessDenied, ResourceNotFound, timeout,
   bad JSON, empty secret) **raises** with a message naming the secret and the error class.
   The ECS task then fails its health check and the old task keeps serving. The k8s path keeps
   its existing warn-and-continue behaviour, which is safe there because envFrom already put
   every value in the env.
5. **Logging** — `logging.getLogger(__name__)`, `%s` placeholders. INFO
   `"Loaded %d keys from AWS secret %s (%s)"` with the **count, secret name and region only**.
   **Never log key values. Don't log key names at INFO either** (Nextenti logs the key set;
   don't copy that). WARNING/exception on the failure paths. Note: this runs at import of
   `app.core.config`, before `main.py:_setup_logging`, so only WARNING+ reaches stderr via
   logging's last-resort handler. That's fine because the failure path raises anyway.
6. **One fetch per process** — `config.py` is imported once per process, so no cache is
   needed. Uvicorn's `--workers N` would fetch N times, which is acceptable. Alembic
   (`alembic/env.py` imports `app.core.config.settings`) and `scripts/migrate.py` therefore
   pick up the AWS secret automatically when the one-off migrate task runs with
   `SECRETS_PROVIDER=aws`. Verify this; don't add a second code path.

**Not in scope:** Dockerfiles, the k8s manifest, IAM policy, creating the secret in AWS, and the
deployment runbook all belong to
[209](209-dockerfile-prod-aws-secret-and-dev-k8s-provider-wiring.md). Secret rotation
without a restart (values are read once at boot, the same as envFrom today) and a prod
Bitbucket pipeline step (prod deployment is still commented out in `bitbucket-pipelines.yml`)
are also out.

## Files

- `backend/app/core/secrets_bootstrap.py`: add `load_secrets`, `fetch_aws_secrets`, and the
  provider constant `SECRETS_PROVIDER_ENV = "SECRETS_PROVIDER"`; update the module docstring
- `backend/app/core/config.py`: call `load_secrets(...)` in place of the direct
  `merge_pod_env_into_dotenv(...)` call, and update its comment
- `backend/app/tests/modules/test_secrets_bootstrap.py`: extend. Existing tests that rely on
  `KUBERNETES_SERVICE_HOST` alone must now also set `SECRETS_PROVIDER=k8s`
- `backend/.env.example`: document `SECRETS_PROVIDER` (commented out, blank = local)
- `docs/secrets-config.md`: rewrite to cover both providers (see acceptance criteria)
- `docs/deployment-aws.md`: in the "Environment / secrets" section, replace "injected as env
  vars into the ECS task definition" with the single-secret-JSON model, linking
  `secrets-config.md`
- root `CLAUDE.md` → "Cloud setup (AWS)": one line saying prod secrets load from one Secrets
  Manager JSON via `SECRETS_PROVIDER=aws`, linking the doc. **This is the top-level
  `/home/solo/hr-prj/CLAUDE.md`, not the clone's.**

## Acceptance criteria

- [x] `SECRETS_PROVIDER` unset → `load_secrets` makes **no** boto3 call and doesn't touch
      `.env`, even with `KUBERNETES_SERVICE_HOST` set (test: patch `boto3.client` to fail if
      it's called)
- [x] `SECRETS_PROVIDER=k8s` inside a pod → the `.env` merge runs exactly as before (all
      existing `test_secrets_bootstrap.py` cases pass after adding the var); boto3 is not called
- [x] `SECRETS_PROVIDER=k8s` with no `KUBERNETES_SERVICE_HOST` → WARNING, `.env` untouched
- [x] `SECRETS_PROVIDER=aws` happy path (botocore `Stubber`, or a patched client returning
      `{"SecretString": json.dumps({...})}`) → keys land in `os.environ`; a key already in the
      env is overridden; a `CRYPTO_PRIVATE_KEY` PEM with newlines round-trips byte-for-byte;
      `Settings()` built afterwards sees `DATABASE_URL`/`SECRET_KEY` from the secret; `.env`
      isn't written
- [x] `SECRETS_PROVIDER=aws` failures each **raise**: missing `AWS_SECRET_NAME`; `ClientError`
      (`ResourceNotFoundException`, `AccessDeniedException`); `NoCredentialsError`;
      non-JSON `SecretString`; JSON that isn't an object; a nested-object value; an empty
      object
- [x] The secret can't overwrite `SECRETS_PROVIDER`/`AWS_SECRET_NAME`/`AWS_REGION` (skipped with
      a WARNING)
- [x] An unknown `SECRETS_PROVIDER` value (e.g. `aws,prod`, `AWS `) raises a message naming the
      value. Decide and test whether surrounding whitespace and case are normalised
      (recommended: `strip().lower()`, so `AWS` works but `aws,prod` doesn't)
- [x] No test or log line prints a secret value (assert with `caplog` that a sentinel value
      never shows up)
- [x] Tests use `monkeypatch` for every env change, so nothing leaks into `os.environ` for
      later tests
- [x] `uv run pytest app/tests/modules/test_secrets_bootstrap.py` is green, and the full
      `uv run pytest` shows no new failures (baseline from the throwaway-Postgres memory: ~62
      known `status_masters` seed failures)
- [x] `docs/secrets-config.md` covers: the provider table (unset / k8s / aws), the AWS secret's
      JSON shape with an example key list (`DATABASE_URL`, `SECRET_KEY`, `CRYPTO_PRIVATE_KEY`,
      `CORS_ORIGINS`, `PUBLIC_APP_URL`, `SMTP_*`, `ENVIRONMENT`), precedence for each provider,
      fail-fast vs warn-and-continue and why, and how to rotate (update the secret, then force
      a new ECS deployment)

Notes: built on branch `feature/gowtham_AwsSecretsProvider` (off main) in workspace-2/hrms; uncommitted at completion. Secret name `hrms/prod`. Full suite on a throwaway Postgres: 530 failures/errors with and without the change, identical lists (bare create_all DB, no seeds); +22 new tests pass. Alembic `current` and `scripts/migrate.py current` confirmed to go through the AWS loader.

Completed: 2026-10-11
