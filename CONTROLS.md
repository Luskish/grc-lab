# Control Mapping

**Ruleset:** FedRAMP Consolidated Rules for 2026 — 20x Class A
**Source:** https://www.fedramp.gov/2026/reference/20x/a/key-security-indicators/
**Ruleset launched:** 2026-06-24
**Retrieved:** 2026-08-17
**Next review:** 2026-11-17
**Scope:** `grc-lab` — personal lab environment
**Assessed by:** Shane Liszewski

> This is a self-assessment of a personal lab. It is not an authorization
> artifact and has not been independently reviewed. Grades reflect honest
> partial credit rather than aspirational coverage.

---

## Grading key

| Grade | Meaning |
|---|---|
| **Satisfies** | Implementation fully meets the indicator as written |
| **Partial** | Meets part of the indicator; gap named explicitly |
| **Supports** | Contributes to the capability without meeting the indicator |
| **Not met** | Indicator is in scope and is not satisfied |
| **N/A (lab)** | Indicator applies to organizational processes absent from a personal lab |

---

## Summary

Of the seven Class A Key Security Indicators:

| Grade | Count | Indicators |
|---|---|---|
| Satisfies | 1 | IAM-APM |
| Partial | 3 | SVC-SIN, CNA-RNT, CMT-LMC |
| Not met | 1 | IAM-AAM |
| N/A (lab) | 2 | CED-RAT, INR-RIR |

**Principal finding.** The infrastructure implements correct controls —
encryption at rest, network traffic restriction enforced by a module with
no override, immutable deployment through version-controlled IaC. Three of
the seven Class A indicators (CED-RAT, CNA-RNT, INR-RIR) require the
subject to be **persistently reviewed**. Configuration is point-in-time;
no automated validation runs against live resources. Infrastructure as Code
establishes the condition but does not establish the validation.

**Largest gap.** KSI-IAM-AAM is not met. Access to this environment uses a
hand-created IAM user with long-lived access keys and `AdministratorAccess`.
This was a deliberate tradeoff (see `DECISIONS.md`) with a named remediation
path, not an oversight.

---

## KSI-SVC-SIN — Securing Information

> Information is encrypted or otherwise secured from unwanted access or
> modification.

**Grade:** Partial

**Related SP 800-53 controls:** AC-01, AC-17(02), CP-09(08), SC-08,
SC-08(01), SC-13, SC-20, SC-21, SC-22, SC-23, SC-28, SC-28(01)

### Implementation

**Encryption at rest — S3**
`modules/compliant-bucket/main.tf` provisions
`aws_s3_bucket_server_side_encryption_configuration` with `AES256` (SSE-S3)
on every bucket created through the module. Not exposed as a variable; there
is no supported path to an unencrypted bucket through this module.

**Encryption at rest — state**
`infra/02-module-demo` uses OpenTofu client-side state encryption:
AES-GCM with a PBKDF2-derived key supplied via `TF_ENCRYPTION`, with
`enforced = true`. State is unreadable to any principal holding
`s3:GetObject` on the state bucket without also holding the key. This is
materially stronger than the S3 backend's `encrypt = true`, which is
server-side only.

### Gap

SVC-SIN spans confidentiality **and** integrity across all information
resources, and its control set includes SC-08 / SC-08(01) — protection
of information in transit. This implementation covers encryption at rest
for S3 objects and OpenTofu state only:

- No bucket policy enforcing `aws:SecureTransport`, so TLS is not required
  at the resource level (SC-08)
- Key material for state encryption is a static passphrase in a shell
  environment variable — not managed, rotated, or access-controlled (SC-13)
- Scope is limited to S3 and state; no other information resource types
  exist in this environment

### Remediation

1. Add a bucket policy denying non-TLS requests to `compliant-bucket`
2. Replace the PBKDF2 key provider with `aws_kms`, using a customer-managed
   key with `enable_key_rotation = true` — moves key access from a shared
   secret to an IAM authorization decision with CloudTrail audit trail

### Evidence

```bash
aws s3api get-bucket-encryption --bucket <bucket>
aws s3 cp s3://<state-bucket>/<key>/terraform.tfstate - | head -c 200
```

The second command returns `{"encrypted_data": "..."}` rather than
readable JSON.

**Verified:** 2026-08-17 — manual, point-in-time

---

## KSI-CNA-RNT — Restricting Network Traffic

> Machine-based information resources are persistently reviewed to ensure
> they are appropriately configured to limit inbound and outbound network
> traffic.

**Grade:** Partial

**Related SP 800-53 controls:** AC-17(03), CA-09, CM-07(01), SC-07(05), SI-08

### Implementation

`modules/compliant-bucket/main.tf` provisions
`aws_s3_bucket_public_access_block` with all four settings enabled:

| Setting | Effect |
|---|---|
| `block_public_acls` | Prevents new public ACLs |
| `ignore_public_acls` | Neutralizes existing public ACLs |
| `block_public_policy` | Prevents new public bucket policies |
| `restrict_public_buckets` | Neutralizes existing public policies |

Two settings prevent future misconfiguration; two neutralize prior
misconfiguration. All four are required for complete coverage.

The module exposes no variable to disable this. A non-compliant bucket
cannot be produced through the paved path.

### Gap

Configuration is correct and enforced at deploy time. **The indicator
requires machine-based information resources to be persistently reviewed**,
and no such review exists:

- Validation has been performed twice, manually, by an operator
- No scheduled job evaluates live resource configuration
- Status of the control between reviews is unknown

Per the FedRAMP definition, persistent activities may be irregular and may
include gaps, but must be intentional, documented, and their status always
known. None of those hold here.

Additionally, review must target the **running resources**, not the IaC
that produced them. AWS applies Block Public Access by default on new
buckets; a review of Terraform source would not detect a resource whose
live configuration diverged from code.

### Remediation

Scheduled collector querying live bucket configuration, emitting
timestamped, hashed results keyed to `KSI-CNA-RNT`. Tracked as Project 3.

### Evidence

```bash
aws s3api get-public-access-block --bucket <bucket> \
  --query 'PublicAccessBlockConfiguration'
```

**Verified:** 2026-08-17 — manual, point-in-time

---

## KSI-CMT-LMC — Logging Changes

> Modifications to the cloud service offering are logged and monitored.

**Grade:** Partial

**Related SP 800-53 controls:** AU-02, CM-03, CM-03(02), CM-04(02), CM-06,
CM-08(03), MA-02

### Implementation

**Change execution.** All infrastructure is defined in OpenTofu and applied
through `plan` / `apply`. Changes are made by redeploying version-controlled
definitions rather than by direct console modification.

**Change history.** Full git history of every infrastructure definition,
including `DECISIONS.md` recording accepted risks and rationale.

**Change integrity.** Remote state in S3 with native locking
(`use_lockfile = true`) prevents concurrent modification. Module variable
validation rejects out-of-policy inputs before any API call is made.

**Access logging.** S3 server access logging writes to a separate,
hardened bucket, so an actor compromising the primary bucket cannot erase
the record of their access.

### Gap

Two distinct shortfalls:

**Logging is incomplete.** Git records modifications to *code*. It does not
record modifications to the *running system*. A change made directly in the
AWS console — the modification most relevant to this indicator — leaves no
trace in any log configured here. CloudTrail is not enabled.

S3 access logging captures data-plane object access, not configuration
changes to the offering, and so does not close this gap.

**Monitoring is absent.** The indicator requires modifications to be logged
**and monitored**. No alerting, review, or drift detection exists. Logs that
are generated and never examined satisfy the first verb only.

### Remediation

1. Enable CloudTrail with log file validation
2. Scheduled drift detection comparing live configuration against state
3. Alerting on configuration change events outside the deployment pipeline

### Evidence

```bash
git log --oneline -- infra/ modules/
aws s3api get-bucket-logging --bucket <bucket>
```

**Verified:** 2026-08-17

---

## KSI-IAM-AAM — Automating Account Management

> The lifecycle and privileges of all accounts, roles, and groups are
> securely managed using automation.

**Grade:** ❌ **Not met**

**Related SP 800-53 controls:** AC-02(02), AC-02(03), AC-02(13),
AC-06(07), IA-04(04), IA-12, IA-12(02), IA-12(03), IA-12(05)

### Current state

| Aspect | Implementation |
|---|---|
| Account creation | Manual, via console |
| Credentials | Long-lived IAM access keys, no expiry |
| Privileges | `AdministratorAccess` — unscoped |
| Lifecycle automation | None |
| Rotation | None |
| Just-in-time access | None |

### Rationale

Deliberately accepted for a lab environment. Permission-boundary debugging
is the most common cause of abandonment in self-directed cloud labs, and
this is an isolated account containing no data of value, protected by a
zero-spend budget alarm. Recorded in `DECISIONS.md`.

The tradeoff is documented rather than concealed. This is the single
largest gap in the environment.

### Remediation

Replace the static IAM user with IAM Identity Center: permission sets
scoped to task, short-lived session credentials, and account lifecycle
managed as code rather than through the console.

**Verified:** 2026-08-17

---

## KSI-IAM-APM — Adopting Passwordless Methods

> Secure passwordless methods are used for user authentication and
> authorization when feasible, otherwise strong passwords with
> phishing-resistant MFA is used.

**Grade:** ✅ **Satisfies** (root account)

**Related SP 800-53 controls:** AC-02, AC-03, IA-02, IA-02(01), IA-02(02),
IA-02(08), IA-05, IA-05(01), IA-05(02), IA-05(06), IA-06, IA-08, SC-23

### Implementation

The AWS root account uses a **FIDO2/WebAuthn passkey** as its MFA device.

Phishing resistance derives from FIDO2 origin binding: the authenticator
cryptographically binds the assertion to the requesting origin, so a
credential presented to a proxy or lookalike domain will not validate
against the legitimate relying party.

**This distinction is material and frequently collapsed.** A TOTP
authenticator app is MFA but is **not** phishing-resistant — the shared
secret produces a code that can be relayed by an attacker-in-the-middle in
real time. Recording "MFA enabled" without recording the factor type
produces an unverifiable claim.

Root is used only for account recovery and billing access; daily operations
use a separate IAM principal.

### Scope limitation

This grade covers the root account. The `shane-lab` IAM user authenticates
with a password and has no MFA device registered. The indicator addresses
user authentication generally, and a second identity in this environment
does not meet it.

Tracked under KSI-IAM-AAM remediation — migration to IAM Identity Center
would resolve both.

### Evidence

AWS Console → IAM → Security credentials → MFA devices; device type
reported as passkey / security key rather than authenticator app.

**Verified:** 2026-08-17

---

## KSI-CED-RAT — Reviewing All Training

> The effectiveness of relevant cybersecurity education and training is
> persistently reviewed.

**Grade:** N/A (lab)

**Related SP 800-53 controls:** AT-02, AT-02(02), AT-02(03), AT-03,
AT-03(05), AT-04, CP-03, IR-02, IR-02(03), PS-06, SR-11(01)

Single-operator personal environment. No employees, no training program,
no roles to segment. Not applicable rather than not met — there is no
population to which the indicator applies.

---

## KSI-INR-RIR — Reviewing Incident Response Procedures

> The effectiveness of documented incident response procedures is
> persistently reviewed.

**Grade:** N/A (lab)

**Related SP 800-53 controls:** IR-04, IR-04(01), IR-06, IR-06(01),
IR-06(03), IR-07, IR-07(01), IR-08, IR-08(01), SI-04(05)

No documented incident response procedure exists for this environment, and
none is warranted — no federal information, no users, no availability
commitment. Not applicable rather than not met.

---

## Implemented but out of scope for Class A

These are real controls that map to KSI families outside the Class A
ruleset. They are documented here to prevent them being claimed against
Class A indicators they do not address.

| Control | Implementation | Maps to | Class |
|---|---|---|---|
| Bucket versioning | `aws_s3_bucket_versioning`, status Enabled | RPL family (recovery) | B / C |
| S3 access logging | Separate hardened log bucket, scoped bucket policy | MLA family (monitoring/logging) | B / C |
| Checkov / Trivy scanning | Manual, ad hoc | MLA-EVC (IaC evaluation) | B / C |
| Module variable validation | `validation` blocks on `environment`, `data_classification` | CMT (change testing) | B / C |

Versioning provides ransomware and accidental-deletion recovery and is
demonstrably valuable. It maps to recovery planning, not to any Class A
indicator, and is not claimed as Class A coverage.

---

## Method and provenance

Mapping performed by reading each Class A indicator against the
implementation, assigning a grade, and stating the gap in a single sentence
where the grade was below Satisfies. Where a gap sentence could not be
written cleanly, the requirement was re-read rather than the grade assigned.

NIST SP 800-53 control associations are taken from the published
per-indicator mappings in the CR2026 ruleset reference, not derived
independently.

An initial draft was produced with AI assistance and contained material
errors, all in the direction of over-claiming coverage: incorrect indicator
IDs from the superseded 20xP1 numbering scheme, a boundary control mapped to
an encryption indicator, and a phishing-resistance determination made
without confirming the authenticator factor type. Every mapping in this
document was subsequently verified against the published ruleset and
corrected.

Recorded because the failure mode is instructive: automated and
vendor-supplied control mappings drift optimistic. Verify downward.

---

## Change log

| Date | Change |
|---|---|
| 2026-08-17 | Initial assessment against CR2026 20x Class A |

---

## Review schedule

Reassess on **2026-11-17**, or upon:

- Publication of a new CR ruleset version or KSI changelog entry
- Material change to the environment (new resource types, new principals)
- Migration to IAM Identity Center (resolves IAM-AAM, changes IAM-APM scope)
- Completion of automated evidence collection (changes CNA-RNT grade)

Ruleset changes are tracked at https://www.fedramp.gov/2026/changelog/ and
in machine-readable form at https://github.com/FedRAMP/rules.
