# grc-lab

Compliance-as-code lab. An opinionated OpenTofu module that makes the compliant
path the easy path — assessed honestly against the **FedRAMP Consolidated Rules
for 2026, 20x Class A**.

---

## The finding

This environment satisfies **one of seven** Class A Key Security Indicators
outright. That result is the point of the repo, not an apology for it.

| Grade | Count | Indicators |
|---|---|---|
| Satisfies | 1 | `KSI-IAM-APM` |
| Partial | 3 | `KSI-SVC-SIN`, `KSI-CNA-RNT`, `KSI-CMT-LMC` |
| Not met | 1 | `KSI-IAM-AAM` |
| N/A (lab) | 2 | `KSI-CED-RAT`, `KSI-INR-RIR` |

The infrastructure is not weak. Encryption at rest on every bucket, all four
public-access-block settings enforced with no override path, client-side state
encryption, immutable deployment through version-controlled IaC. Under a
narrative-based framework this passes without much argument.

Three of the seven Class A indicators require their subject to be
**persistently reviewed**. Configuration here is point-in-time. Nothing runs on
a schedule against live resources.

**Infrastructure as Code establishes the condition. It does not establish the
validation.** That gap is the entire reason 20x exists, and finding it in my own
work was more instructive than reading about it.

Full assessment with gaps, evidence commands, and remediation paths:
[`CONTROLS.md`](./CONTROLS.md)

---

## Layout

```
grc-lab/
├── modules/
│   └── compliant-bucket/    # the paved road
├── infra/
│   ├── 00-bootstrap/        # state backend — local state, documented exception
│   ├── 01-first-bucket/     # longhand version, kept as reference
│   └── 02-module-demo/      # remote state, native locking, client-side encryption
├── CONTROLS.md              # CR2026 Class A mapping, version-stamped
└── DECISIONS.md             # accepted risks and rationale
```

### `modules/compliant-bucket`

An S3 bucket that cannot be created non-compliant:

- SSE-S3 encryption at rest
- Versioning enabled
- All four public access block settings
- Mandatory `Environment` and `DataClassification` tags, validated against an
  allowed list

Six lines at the call site produces all of it:

```hcl
module "reports" {
  source = "../../modules/compliant-bucket"

  name                = "grc-lab-reports"
  environment         = "dev"
  data_classification = "confidential"
}
```

---

## Design decisions

### Security controls are not variables

The module exposes no `enable_encryption`, no `enable_versioning`, no
`allow_public_access`.

An optional control is not a control. The moment a security setting becomes a
toggle, it gets toggled — with a good reason, under time pressure, by someone
who intends to turn it back on. A bucket that genuinely needs to be public must
be written longhand, outside the module, where it is loud in code review rather
than quiet in a tfvars file.

### Client-side state encryption, not just `encrypt = true`

The S3 backend's `encrypt = true` is server-side encryption. AWS holds the key.
Any principal with `s3:GetObject` on the state bucket reads plaintext state —
including every sensitive attribute OpenTofu records.

This repo uses OpenTofu's client-side encryption (AES-GCM, `enforced = true`),
so storage access is not secret access. Terraform has no equivalent; this is the
concrete reason for the OpenTofu choice.

Demonstrable in one line:

```bash
aws s3 cp s3://<state-bucket>/02-module-demo/terraform.tfstate - | head -c 200
# {"encrypted_data":"gTx8vQ2mK9...","encryption_version":"v0"}
```

### The mapping is version-stamped and has an expiry

`CONTROLS.md` records the ruleset version, retrieval date, and next review date.

This is not ceremony. The KSI identifier format changed in June 2026 — the
previous `KSI-SVC-03` numbering was replaced by mnemonic identifiers like
`KSI-SVC-SIN` under the Consolidated Rules. A mapping without a version stamp
cannot be checked against anything.

Ruleset changes: [changelog](https://www.fedramp.gov/2026/changelog/) ·
machine-readable: [FedRAMP/rules](https://github.com/FedRAMP/rules)

### Native S3 locking

State locking uses `use_lockfile = true` (S3 conditional writes). No DynamoDB
table. Fewer moving parts, one less service dependency, same concurrency
protection.

---

## Known gaps

Tracked openly in `CONTROLS.md` rather than omitted. The significant ones:

**`KSI-IAM-AAM` — not met.** A hand-created IAM user with long-lived access keys
and `AdministratorAccess`. Deliberately accepted: isolated account, no data of
value, zero-spend budget alarm, and permission-boundary debugging is the most
common reason self-directed labs get abandoned. Remediation is IAM Identity
Center with scoped permission sets and short-lived credentials.

**`KSI-CNA-RNT` — no persistent review.** Public access blocking is correctly
configured and enforced at deploy time. It has been verified twice, by hand.
The indicator requires machine-based resources to be persistently reviewed, and
review has to target running resources rather than the code that produced them —
AWS applies some of these settings by default, so a source review would not
detect divergence.

**`KSI-CMT-LMC` — logged, not monitored.** Git records changes to code. It does
not record changes to the running system, which is the modification that matters.
CloudTrail is not enabled and no drift detection exists.

**Key management.** State encryption uses a PBKDF2 passphrase in a shell
environment variable. Not rotated, not access-controlled, not auditable.
Production equivalent is the `aws_kms` key provider with rotation enabled, which
converts key access from a shared secret into an IAM decision with a CloudTrail
trail.

---

## Implemented but out of scope for Class A

Bucket versioning maps to the RPL (recovery) family. S3 access logging and IaC
scanning map to MLA (monitoring, logging, auditing). Neither family appears in
the Class A ruleset.

They are implemented and documented, and deliberately **not** claimed as Class A
coverage. Knowing which ruleset applies is half of a mapping's value.

---

## Running it

Requires OpenTofu ≥ 1.10, AWS CLI with credentials configured, and an AWS
account you don't mind creating a few S3 buckets in. Everything here is free
tier; `tofu destroy` at the end of each session.

```bash
# 1. state backend (local state by design)
cd infra/00-bootstrap
tofu init && tofu apply
tofu output -raw state_bucket        # paste into the backend block below

# 2. workload
cd ../02-module-demo
# set the bucket name in the backend block — backend config takes no variables
export TF_ENCRYPTION='...'           # see CONTROLS.md
tofu init && tofu apply

# teardown — order matters, bootstrap holds the other state
cd ../02-module-demo && tofu destroy
cd ../00-bootstrap && tofu destroy
```

---

## Roadmap

| Project | Adds | Closes |
|---|---|---|
| 1 · Compliant baseline | Module, remote state, control mapping | ✅ complete |
| 2 · Policy gate | Checkov + custom Rego in CI, keyed to KSI IDs, with tests | Manual scanning |
| 3 · Evidence pipeline | Scheduled collectors, timestamped and hashed output | `CNA-RNT` persistent review |
| 4 · OSCAL | Schema-valid assessment results from live state | Machine-readable packaging |
| 5 · Detection | Drift detection and auto-remediation | `CMT-LMC` monitoring |

---

## A note on method

Assessment grades were argued over, not accepted. The first pass over-claimed in
both directions — an AI-assisted draft applied a "persistently" requirement to
indicators that don't contain the word and used identifiers from the superseded
numbering scheme; my own first pass claimed indicators outside the Class A
ruleset and graded a passkey and a TOTP app as equivalent.

Both directions of error got corrected against the published ruleset. That
process is recorded in `CONTROLS.md` because it is the actual work: a control
mapping is a negotiation between someone who knows the standard and someone who
knows the system, and it is only useful when both sides can lose a point.
