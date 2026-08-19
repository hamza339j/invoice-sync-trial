# RUNBOOK — invoice-sync (engineer-facing)

Short version for application engineers. You do **not** need any secret access
or project role to work with this Job.

## How it's wired

- The Job **`invoice-sync`** runs as its own identity, `invoice-sync-runtime@…`.
- That identity — and only that identity — can read the secret `db-password`.
- You deploy by **merging to `main`**. CI (GitHub Actions) builds the image and
  rolls the Job using keyless auth (Workload Identity Federation). There are no
  keys and no manual `gcloud` deploys from laptops.

## "I get Permission denied on the secret"

You almost never need a new grant. Check, in order:

```bash
# 1. Which identity is the Job running as?
gcloud run jobs describe invoice-sync --region us-central1 \
  --format='value(template.template.serviceAccount)'
# Expect: invoice-sync-runtime@<project>.iam.gserviceaccount.com

# 2. Can that identity read the secret?
gcloud secrets get-iam-policy db-password
# Expect a secretAccessor binding for the runtime SA above.

# 3. Is there an enabled version?
gcloud secrets versions list db-password
```

- Wrong SA on the Job → fix the Job's `service_account` (Terraform: `job.tf`).
- Missing binding → add it in Terraform (`secret.tf`), not by hand, not to your
  user. Open a PR; **do not** ask for `Editor`.

## Deploy a change

Merge to `main`. Watch the run in the repo's **Actions** tab. The workflow builds
`app/`, rolls the image, and executes the Job once — a red run means the deploy
or the Job failed.

## Run the Job manually / read logs

```bash
gcloud run jobs execute invoice-sync --region us-central1 --wait
gcloud run jobs executions list --job invoice-sync --region us-central1
gcloud logging read \
  'resource.type=cloud_run_job AND resource.labels.job_name=invoice-sync AND severity>=ERROR' \
  --limit 20
```

## Add a new secret

PR to Terraform: a `google_secret_manager_secret`, a version, and **one**
`secretmanager.secretAccessor` binding for the Job's runtime SA. Reference it in
`job.tf` as a `secret_key_ref` env var. Never grant secret access to a human or
to CI.

## Alerts

A failed execution emails the platform on-call (Cloud Monitoring alert
`Cloud Run Job invoice-sync failed`). If you get paged, start with the logging
query above; the alert body has the same commands.

## Who to ask

Platform / Cloud Ops (Hamza). For anything that would need a new IAM grant,
open a PR against the Terraform and tag platform — that's faster than a DM and
leaves an audit trail.
