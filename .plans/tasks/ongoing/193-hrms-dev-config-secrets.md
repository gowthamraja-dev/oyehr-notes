---
task: 193
title: hrms-dev-config — Kubernetes secret merged into .env, copied from Nextenti
status: ongoing
depends_on: []
---

# 193 — hrms-dev-config — Kubernetes secret merged into .env, copied from Nextenti

## Scope

Copy Nextenti's dev-cluster secret setup into HRMS, using the secret name
**`hrms-dev-config`**. At startup the backend reads the secret files Kubernetes mounts,
merges them into the existing `.env`, and the code reads that one merged `.env` as its only
config source.

### Reference pattern — verified in `Nextenti-JavaApp` (07-Oct-26)

`/home/solo/Nextenti/Nextenti-JavaApp/k8s/dev-deployment.yaml`:

```yaml
containers:
  - name: dev-javabackend
    env:
      - { name: SPRING_PROFILES_ACTIVE, value: "k8s,dev" }
    envFrom:
      - secretRef: { name: nextenti-dev-config }
    volumeMounts:
      - { name: app-secrets, mountPath: /etc/nextenti/secrets, readOnly: true }
volumes:
  - name: app-secrets
    secret: { secretName: nextenti-dev-config }
```

- `Dockerfile-Dev` sets `K8S_SECRETS_PATH=/etc/nextenti/secrets`.
- `config/secrets/KubernetesSecretsProvider.java` lists the regular files in
  `K8S_SECRETS_PATH`. Each file's name (CAPS_UNDERSCORE) is the key and its stripped content
  is the value. It skips names starting with `..`, which are the k8s mount symlinks. If the
  path is unset, missing, or can't be read, it returns an empty map and the app still starts.
  A file that can't be read is skipped.
- `config/secrets/SecretsEnvironmentPostProcessor.java` runs this when the `k8s` profile is
  active and adds the result with `addFirst`, so **the secret overrides everything else**.
- The real Secret is never in git. `application-dev.properties` holds only non-secret
  settings, and `.gitignore` has `/secrets/`.

### What HRMS does (decided 07-Oct-26)

Startup flow, run **before** `Settings()` is first built:

1. **Read the mount.** If `K8S_SECRETS_PATH` is set and is a directory, read every regular
   file not starting with `..` into `{KEY: stripped_content}`, the same rules as
   `KubernetesSecretsProvider`. If it's unset or missing, there's nothing to merge.
2. **Read the existing `.env`.** Parse it with `dotenv_values()` (python-dotenv is already
   pulled in by pydantic-settings).
3. **Merge.** Start from the existing `.env` and overlay the secret keys, so **secret wins**
   (matching Java's `addFirst`). Keys that are only in `.env` are kept. New keys from the
   secret are appended.
4. **Write the merged `.env`.** Write it atomically (temp file + `os.replace`) with mode
   `0600`. Put a header comment saying it was generated at startup from
   `K8S_SECRETS_PATH` + `.env`.
5. **Read one source.** `Settings` reads only that merged `.env`, which is the existing
   `model_config.env_file`. There's no second code path for the mount; everything the app
   sees comes through `.env`.

Implement it in `app/core/secrets_bootstrap.py` as `merge_k8s_secrets_into_env(env_path,
secrets_dir) -> list[str]`, which returns the **key names** it merged. Call it once, at the
very top of `app/core/config.py`, before the `settings = Settings()` instance is created, so
every importer, Alembic and the scripts included, sees the merged values. Log
`"Merged %d keys from %s into %s"` plus the key *names* at INFO. **Never log values.**

### Rules that keep this safe
- **The merged `.env` must not go into the repo or the image.** Inside the container it's
  written to a writable path (e.g. `/app/.env`, or an `emptyDir` mounted there if the root
  filesystem is read-only). On a laptop with no `K8S_SECRETS_PATH`, step 1 finds nothing and
  `.env` **is not rewritten at all**, so local dev is unchanged.
- **Don't bake the `.env` into the image.** Check `.dockerignore`. If a base `.env` with
  non-secret defaults is needed in the cluster, ship it as `env.dev` (committed, no secrets)
  and copy it to `.env` before the merge.
- **Real environment variables still beat `.env`**, because that's how pydantic orders them.
  So, **drop `envFrom`** from the HRMS manifest and keep only the volume mount. That way the
  merged `.env` really is the one source, and the ECS path, which injects env vars, keeps
  working untouched.
- **Production is unchanged.** ECS doesn't set `K8S_SECRETS_PATH`, so step 1 is skipped.

### `local.secret.json` — NOT verified yet
The user named `/home/solo/Nextenti/authenticator` as the source, and that repo couldn't be
read during planning. Before building this part, check how authenticator uses it, reading the
loader and template, never the real values. If it's another input, merge it in the same
function (`.env` < `local.secret.json` < k8s secret) rather than adding a second read path.

**Out of scope**
- Real values. The Secret is created out of band:
  `kubectl create secret generic hrms-dev-config --from-env-file=<file not in git>`.
- Prod/ECS changes.
- The top-level `hrms/` clone. All edits go in `workspace-2/hrms/`.

## Open questions
- **Is HRMS dev going onto the same cluster as Nextenti?** That decides the node affinity and
  the registry: `ghcr.io/nt-private` with `github-docker-creds`, or ECR.
- **Health probes:** HRMS has no `/actuator`, so point the probes at its own health route.
- **CI builds:** CI must be able to mint a CodeArtifact token for the `nhforms` install
  during the Docker build.

## Files
- `workspace-2/hrms/infra/k8s/dev-deployment.yaml` — Deployment + Service, mirroring the
  Java one but **volume only, no `envFrom`**. Secret `hrms-dev-config` mounted at
  `/etc/hrms/secrets`, with `K8S_SECRETS_PATH=/etc/hrms/secrets` in `env:`.
- `workspace-2/hrms/infra/k8s/hrms-dev-config.example.env` — key names with
  `<REPLACE_ME>` values.
- `workspace-2/hrms/backend/app/core/secrets_bootstrap.py` — the merge (new).
- `workspace-2/hrms/backend/app/core/config.py` — call the merge before `Settings()`.
- `workspace-2/hrms/.gitignore`, `.dockerignore` — `.env`, `local.secret.json`, `/secrets/`.
- `workspace-2/hrms/backend/app/tests/modules/test_secrets_bootstrap.py`
- `workspace-2/hrms/docs/secrets-config.md` — linked from the "Cloud setup" section of
  CLAUDE.md.

## Acceptance criteria
- [ ] Secret files plus an existing `.env` produce a merged `.env`: keys only in `.env` are
      kept, keys in both take the secret value, keys only in the secret are appended (test).
- [ ] `..data`/`..<timestamp>` entries and subdirectories are ignored, and values are
      stripped (test).
- [ ] With `K8S_SECRETS_PATH` unset or pointing at a missing directory, `.env` is byte-for-byte
      unchanged and startup works (test).
- [ ] With no `.env` but secrets present, a `.env` is created holding the secret keys (test).
- [ ] The written `.env` has mode `0600` and the write is atomic.
- [ ] `Settings()` after the merge returns the secret's values (test).
- [ ] Logs contain key names only, never values (test with `caplog`).
- [ ] `git ls-files` shows no `.env`, `local.secret.json` or real Secret, and the image has
      no baked `.env`.
- [ ] `kubectl apply --dry-run=client -f infra/k8s/` validates.
- [ ] `uv run pytest app/tests/modules/test_secrets_bootstrap.py` passes.
- [ ] `docs/secrets-config.md` is written and linked from CLAUDE.md.

## Progress — 07-Oct-26 (uncommitted, on `feature/gowtham_HrmsDevConfig` off origin/main, in workspace-2)
A dev k8s deployment already existed: `k8s/dev-hrms-backend.yaml`, deployed by
`bitbucket-pipelines.yml`, on the same cluster as Nextenti, using ghcr and `/healthz`. It was
extended rather than adding a new `infra/k8s/` file.
- Done: `app/core/secrets_bootstrap.py`, the hook in `config.py` plus the log in `main.py`,
  the volume in the manifest (`optional: true`, `K8S_SECRETS_PATH=/etc/hrms/secrets`),
  `k8s/hrms-dev-config.example.env`, `docs/secrets-config.md` and the CLAUDE.md link. 18
  tests pass, ruff is clean, and a simulated container start merges as expected.
- Added beyond the plan: the Secret's keys are also exported to `os.environ`, because boto3
  (`AWS_*`), `TRUST_PROXY_HEADERS` and the scripts' `RAILS_DB_*` never read `.env`.
- Not done:
  - `backend/.env` is **tracked in git** and baked into the image (`COPY . .`, no
    `.dockerignore`). Untracking it is a team decision and hasn't been made.
  - The `hrms-dev-config` Secret hasn't been created in the cluster.
  - There's no deploy smoke test.
  - `kubectl --dry-run=client` needs a cluster, so it hasn't been run.
  - `local.secret.json` is still unverified.

## Update — 07-Oct-26: switched to envFrom
The user replaced the volume mount with `envFrom.secretRef: hrms-dev-config` in
`k8s/dev-hrms-backend.yaml` and deleted `k8s/hrms-dev-config.example.env`.
`secrets_bootstrap.py` is now `merge_pod_env_into_dotenv`:
- it runs when `KUBERNETES_SERVICE_HOST` is set;
- it merges env values for `Settings` fields plus keys already in `.env`;
- failures warn instead of raising, since env vars already win.

17 tests pass, and the doc and the CLAUDE.md bullet are rewritten.
Still open: create the Secret before deploying (`secretRef` isn't optional), and
`backend/.env` is still tracked.
