# TRIAL.md — invoice-sync least-privilege / private-networking fix

Author: Hamza · Role: GCP Platform / Cloud Ops

The engineer asked for two things I won't do — project `Editor`, and a
service-account JSON key in GitHub Secrets. Below is what I did instead, and
why.

---

## 1. Why granting `Editor` is the wrong response, and its blast radius

`roles/editor` is a legacy basic role covering **thousands** of permissions
across almost every service in the project — Secret Manager, Cloud Run, GCS,
Pub/Sub, service accounts, firewall rules, and more. The engineer's actual
problem is *one Job identity can't read one secret*. Editor solves that the way
a master key solves a stuck door.

Blast radius if I grant it:
- The engineer can now read/modify **every** secret, bucket and dataset in the
  project, not just `db-password`.
- Editor includes `iam.serviceAccounts.actAs` / key creation paths, so the
  engineer could impersonate the deployer or runtime SAs and quietly widen
  access further.
- It's granted to a **human on a laptop**. If that laptop is phished, the
  attacker inherits Editor over the whole project.
- It normalizes "unblock = grant basic role," which is how projects rot into
  un-auditable IAM.

The correct fix is a single resource-scoped grant: the Job's runtime SA gets
`roles/secretmanager.secretAccessor` **on `db-password` only**. The engineer
needs *no* new IAM to unblock the deploy.

## 2. Why a JSON key is the wrong CI pattern, and what WIF solves

A downloaded SA JSON key is a **long-lived, exfiltratable credential**. In
GitHub Secrets it sits in a system outside GCP's control; it doesn't expire, it
doesn't rotate, and if it leaks (fork PR, log echo, compromised action) it's
valid until someone remembers to revoke it. Key sprawl is one of the most common
root causes of GCP breaches.

**Workload Identity Federation** removes the key entirely. GitHub already issues
each workflow run a short-lived OIDC token that says "I am run X of repo
`hamza339j/invoice-sync-trial` on branch `main`." GCP is configured to *trust that
token* (scoped by an attribute condition) and exchange it for a **short-lived**
access token to impersonate the deployer SA. Nothing long-lived is ever stored.
If the repo is deleted or the condition changes, access stops immediately — no
key to hunt down.

## 3. Ranked root-cause hypotheses for the secret permission error

`Permission denied on secret projects/.../secrets/db-password`. Most → least
likely, with the first commands I'd run:

1. **The Job runs as the default compute SA (or a wrong SA) with no accessor
   binding.** Most common. Cloud Run defaults to the Compute Engine default SA
   if you don't set one; that SA has no grant on this secret.
   ```
   gcloud run jobs describe invoice-sync --region us-central1 \
     --format='value(template.template.serviceAccount)'
   gcloud secrets get-iam-policy db-password
   ```
2. **Right SA, but no `secretAccessor` grant on the secret** (or granted on the
   wrong resource / project). Same `get-iam-policy` above; confirm the member
   matches the Job's SA exactly.
3. **Secret / version doesn't exist or the reference is wrong** (`latest` with no
   enabled version, or a cross-project secret name typo).
   ```
   gcloud secrets versions list db-password
   ```
4. **Org-policy / VPC-SC boundary blocking Secret Manager egress** (more likely
   in a regulated project than a sandbox). Would show as denied even with IAM in
   place.
   ```
   gcloud logging read 'protoPayload.status.code!=0 AND resource.type="audited_resource" AND protoPayload.serviceName="secretmanager.googleapis.com"' --limit 20
   ```

In this build the fix is #1+#2: a dedicated runtime SA and one resource-scoped
`secretAccessor` binding.

## 4. The IAM model — who deploys, who reads, who runs

| Identity | What it may do | What it may NOT do |
|---|---|---|
| **Runtime SA** `invoice-sync-runtime@` | Read `db-password`; run as the Job | Deploy anything; touch other secrets/resources |
| **Deployer SA** `gh-deployer@` | Deploy/update/run the Job; push images; `actAs` the runtime SA only | Read `db-password`; act as any other SA; edit the project |
| **Human engineer** | Nothing new — reads logs, opens PRs | Read the secret; grant themselves roles |
| **CI (GitHub Actions)** | *Is* the deployer SA, via WIF, short-lived, main-branch only | Hold a key |

Note the deployer **never** gets `secretAccessor`. Cloud Run validates that the
*runtime* SA can read the secret at deploy time, so the deploy path works without
the deployer ever being able to read the value.

**If an engineer's laptop is compromised:** the blast radius is their own
identity — read logs, open PRs. They cannot read `db-password` (only the runtime
SA can, and only from inside the Job), cannot deploy (that path is CI-only via
WIF, keyless), and hold no SA key. Compare to the "grant Editor + JSON key"
world, where a phished laptop is game over for the project.

## 5. VPC egress choice — what it protects, what it doesn't

I used **Direct VPC egress** with `egress = ALL_TRAFFIC` over a subnet with
Private Google Access, and **no Cloud NAT**, rather than a Serverless VPC Access
connector. Justification: for a single Job I get the same private path without
running and patching connector VM instances (the connector is a managed but
still real set of e2-micro VMs), it's cheaper, and it scales with the Job. A
connector is the right call if I needed a shared egress path across many
services or features a connector supports that direct egress doesn't.

**What it protects:** the Job's *egress*. All outbound traffic leaves through my
subnet; with Private Google Access, calls to Google APIs (Secret Manager,
Artifact Registry, Logging) ride Google's private backbone, and with no NAT the
Job has **no route to the public internet** at all. That's a real reduction in
exfiltration surface.

**What it does NOT protect:** the secret itself. Reading `db-password` is an
IAM decision, not a network one — the network path doesn't grant or deny it.
Direct VPC egress also does not, by itself, stop a Google API call from *leaving*
the project's trust boundary; that's what VPC Service Controls do.

**Next for a real PHI path:** (a) a **VPC Service Controls** perimeter around
the project so Secret Manager / GCS can't be reached from outside the perimeter
even with valid IAM; (b) an explicit **egress firewall** allowing only the
Google private CIDRs; (c) CMEK on the secret; (d) restricted `private.googleapis.com`
routing. I skipped these for a sandbox — noted in §8.

## 6. HIPAA / regulated-data posture — what changes if this is PHI-adjacent

- **Refuse:** the Editor grant and the JSON key outright (I already do), plus any
  request to print/echo a secret value into logs or a ticket.
- **Log:** enable **Data Access audit logs** for Secret Manager and Cloud Run so
  every secret access is attributable; ship audit logs to a restricted,
  retention-locked bucket.
- **Isolate differently:** a **VPC-SC perimeter**; **CMEK** on the secret and
  image registry; a dedicated project (not a shared sandbox) under a folder with
  org policies (disable SA key creation org-wide via
  `iam.disableServiceAccountKeyCreation`, restrict external IPs, restrict
  `allUsers`); and a **BAA-covered** service list only.
- **Access model:** break-glass, time-boxed, audited human access — never a
  standing human grant on a PHI secret.

## 7. Resolve independently vs escalate to the Cloud Lead

**Resolve now (done in this PR):** dedicated runtime SA + resource-scoped
`secretAccessor`; WIF for CI; private egress; the failure alert. None of this
needs a decision above my level — it's the standard least-privilege fix and it
unblocks the engineer today.

**Escalate with a recommendation:** whether this workload is genuinely
PHI-adjacent. *Recommendation:* treat it as regulated and move it to a dedicated
project inside a VPC-SC perimeter with Data Access audit logs and CMEK before it
touches anything real. I'd bring that as "here's the plan and cost, approve the
perimeter" — not "what should we do?"

## 8. Time spent and what I intentionally skipped

- **Time:** ~6 hours.
- **Skipped on purpose (sandbox, called out above):** VPC Service Controls
  perimeter, egress firewall rules, CMEK, Data Access audit-log sinks, org
  policies, and a real container image/app. All are the first things I'd add for
  a production PHI path (§5, §6). The build proves the *pattern*; these harden it.

## Links

- Repository: `https://github.com/hamza339j/invoice-sync-trial.git`
- Successful GitHub Actions run (WIF path): `https://github.com/hamza339j/invoice-sync-trial/actions/runs/32265697442`
  alert email arrived at `hamzaafzal9909@gmail.com`.
