---
task: 209
title: Dockerfile-Prod (AWS secret) + dev k8s image wiring + IAM/secret runbook
status: done
depends_on: [208]
---

# 209 — Dockerfile-Prod (AWS secret) + dev k8s image wiring + IAM/secret runbook

**Clone:** `workspace-2/hrms/` (check `git -C workspace-2/hrms status -sb` first).

## Background

[208](208-env-selected-secrets-provider-k8s-dev-aws-prod.md) adds the backend switch:
`SECRETS_PROVIDER=k8s` runs the k8s `.env` merge, `SECRETS_PROVIDER=aws` loads one JSON secret
from AWS Secrets Manager, and unset does nothing. This task bakes the right value into each
image, the same way Nextenti does:

```dockerfile
# Nextenti-JavaApp/Dockerfile-Dev
ENV SPRING_PROFILES_ACTIVE=k8s,dev
ENV K8S_SECRETS_PATH=/etc/nextenti/secrets

# Nextenti-JavaApp/Dockerfile-Prod
ENV SPRING_PROFILES_ACTIVE=aws,prod
ENV AWS_SECRET_NAME=nextenti
ENV AWS_REGION=ap-south-1
ENV SERVER_PORT=80
```

Current HRMS state:
- `backend/Dockerfile-Dev`: built by `bitbucket-pipelines.yml` (the "Build & push backend"
  step), deployed to k8s via `k8s/dev-hrms-backend.yaml` (envFrom `dev-hrms-backend-config`
  ConfigMap + `hrms-dev-config` Secret). It listens on port 80 and has no secrets-related `ENV`.
- `backend/Dockerfile`: the generic/local image on port 8000.
- There's no `backend/.dockerignore`, so `COPY . .` bakes `backend/.env` into the image (the
  dev k8s merge relies on that, see `docs/secrets-config.md`).
- There's no prod image and no prod pipeline step (that section of `bitbucket-pipelines.yml`
  is commented out).

## Scope

1. **`backend/Dockerfile-Dev`**: add `ENV SECRETS_PROVIDER=k8s ENVIRONMENT=development`.
   Without the first one, 208's explicit gate turns the k8s merge **off** in dev, so this
   change must ship in the same deploy as 208 (or 208 merges first and this follows straight
   after). Nothing else changes.
2. **New `backend/Dockerfile-Prod`**: the same build steps as `Dockerfile-Dev` (python:3.14.6-slim,
   uv, the WeasyPrint system libraries, `vendor/` nhforms wheel, `uv sync --frozen
   --no-install-project`), plus:
   ```dockerfile
   ENV SECRETS_PROVIDER=aws \
       AWS_SECRET_NAME=hrms/prod \
       AWS_REGION=ap-south-1 \
       ENVIRONMENT=production
   RUN rm -f .env .env.* .crypto_key.pem   # prod must not ship dev config or the dev RSA key
   EXPOSE 80
   CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80", "--proxy-headers", "--forwarded-allow-ips", "*"]
   ```
   - `AWS_SECRET_NAME` is `hrms/prod` (confirmed 11-Oct-26). It's a name, not a secret, so it
     belongs in the image, as with Nextenti.
   - Remove `.env` in the prod image only. A `.dockerignore` would break the dev k8s merge,
     which needs the baked `.env`.
   - Don't bake AWS access keys in, and don't pass them as env. The ECS **task role** supplies
     credentials.
   - Check whether `--proxy-headers` is right behind the ALB (TLS terminates upstream per root
     CLAUDE.md). If it isn't needed, drop it and note why in the PR.
3. **k8s manifest**: no functional change. Optionally add `SECRETS_PROVIDER: "k8s"` to the
   `dev-hrms-backend-config` ConfigMap as belt-and-braces (env from a ConfigMap overrides the
   image `ENV`, and both say `k8s`).
4. **Runbook** (append to `docs/secrets-config.md` under an "AWS (prod)" section, and to
   `docs/deployment-aws.md`):
   - Create the secret once, as **one flat JSON object** (keys = `Settings` field names in
     CAPS, plus any directly-read env keys such as `TRUST_PROXY_HEADERS`):
     ```bash
     aws secretsmanager create-secret --region ap-south-1 --name hrms/prod \
       --secret-string file:///secure/place/hrms-prod-secret.json
     # PEM in JSON: newlines as \n — e.g. build the file with
     # jq -n --rawfile pem crypto_key.pem --arg db "$DATABASE_URL" '{CRYPTO_PRIVATE_KEY:$pem, DATABASE_URL:$db, ...}'
     ```
   - Rotate with `aws secretsmanager put-secret-value ...`, then `aws ecs update-service
     --force-new-deployment` (values are read once at boot).
   - **ECS task role** IAM policy (the *task* role, not the execution role, because the app
     calls the API itself):
     ```json
     {"Effect":"Allow","Action":"secretsmanager:GetSecretValue",
      "Resource":"arn:aws:secretsmanager:ap-south-1:<acct>:secret:hrms/prod-*"}
     ```
     Add `kms:Decrypt` on the key **only** if the secret uses a customer-managed KMS key.
   - Remove the per-key `secrets:`/`environment:` entries for those keys from the ECS task
     definition, or leave them knowing the Secrets Manager values override them (208 injects
     with override).
   - The migrations one-off task uses the same image and task role, so it gets
     `DATABASE_URL` the same way.

**Not in scope:** the backend loader and its tests ([208](208-env-selected-secrets-provider-k8s-dev-aws-prod.md)),
a prod build/deploy step in `bitbucket-pipelines.yml` or Terraform for the secret/role
(raise as a new task if wanted), and the frontend (Amplify keeps using `NEXT_PUBLIC_*`
build env).

## Files

- `backend/Dockerfile-Dev`: add `ENV SECRETS_PROVIDER=k8s ENVIRONMENT=development`
- `backend/Dockerfile-Prod`: new
- `k8s/dev-hrms-backend.yaml`: optional ConfigMap key
- `docs/secrets-config.md`, `docs/deployment-aws.md`: runbook sections

## Acceptance criteria

- [x] `docker build -f backend/Dockerfile-Prod backend/` succeeds locally. Use a distinct
      tag, and don't `compose up` (see the root CLAUDE.md Docker note about clashing with the
      `hrms/` stack)
- [x] `docker run --rm <prod-img> sh -c 'ls -a /code | grep -E "^\.env|crypto_key" || echo clean'`
      prints `clean`
- [x] `docker run --rm <prod-img> env | grep -E 'SECRETS_PROVIDER|AWS_SECRET_NAME|AWS_REGION|ENVIRONMENT'`
      shows `aws` / `hrms/prod` / `ap-south-1` / `production`
- [x] Running the prod image with **no AWS credentials** exits non-zero at startup with an
      error that names the secret. It must not boot on dev defaults (this proves 208's
      fail-fast through the real image)
- [x] Running the prod image with credentials that can read a test secret (a throwaway secret
      such as `hrms/ws2-test`, passed via `-e AWS_SECRET_NAME=...` and an `~/.aws` mount, then
      deleted afterwards) boots, `GET /healthz` returns 200, and the INFO line reports the
      key count. If no AWS access is available in-session, mark this as needing the user to
      run it rather than skipping it silently
- [x] `docker run --rm <dev-img> env | grep SECRETS_PROVIDER` shows `k8s`; the dev image is
      otherwise byte-for-byte the same in behaviour (k8s merge still runs in the cluster after
      deploy: check `/code/.env` in the pod has the merged marker, per `docs/secrets-config.md`)
- [x] The runbook in `docs/secrets-config.md` and `docs/deployment-aws.md` covers creating the
      secret, the JSON/PEM format, task-role IAM, rotation, and the migrate task

## Progress notes (11-Oct-26)

Built on `feature/gowtham_AwsSecretsProvider` in workspace-2/hrms, with 208. Not committed yet.

Deviations from the scope above, all deliberate:
- **No `RUN rm -f .env`.** `COPY . .` would already have put `.env` in a layer, and `rm`
  doesn't remove it from that layer. Used `backend/Dockerfile-Prod.dockerignore` (BuildKit
  per-Dockerfile ignore) instead, plus a guard step that fails the build if `.env`/`.pem`/`.venv`
  reach the context. Verified: a `docker save` scan of every layer has no `.env`/pem/`.venv`
  (control file found), and building without the ignore file fails at the guard.
- **No `--proxy-headers --forwarded-allow-ips "*"` in CMD.** uvicorn 0.51 already defaults to
  proxy headers. With `*` it takes the **left-most**, client-controlled X-Forwarded-For entry
  (checked: `"6.6.6.6, 203.0.113.9"` → `6.6.6.6`), which would let a client spoof activity-log
  `login_ip` and get past iclock's TRUST_PROXY_HEADERS check. Documented instead: set
  `FORWARDED_ALLOW_IPS=<VPC CIDR>` as a task-definition env var (the CIDR form gives the real
  client).
- **k8s ConfigMap not changed.** The image is the single source for `SECRETS_PROVIDER`, as in
  Nextenti.
- **"INFO line reports the key count" isn't achievable as written.** It's logged at import,
  before `_setup_logging`, so it isn't printed. Re-adding a post-setup replay would undo
  commit 1ca307e (which removed exactly that for the k8s merge), so it was left out and
  documented. Fail-fast means a serving task has loaded its secret.

Happy path verified **against a local moto Secrets Manager emulator, not real AWS**: the real
prod image plus a throwaway Postgres returned `/healthz` 200 with `DATABASE_URL` from the
secret (the default localhost URL can't work in the container), and `/api/v1/public/crypto-key`
served the public half of the PEM stored in the secret.

Open (needs the user):
1. Real AWS: create `hrms/prod` (or a throwaway secret), give a role read access, run the
   prod image with those credentials, then `GET /healthz`.
2. After the dev deploy: confirm the k8s merge still runs in the pod (`/code/.env` has the
   merged marker). This needs 208 and 209 deployed together.

The two open items (real-AWS boot; dev-pod .env merge after deploy) were confirmed done by the user on 2026-10-11.

Completed: 2026-10-11
