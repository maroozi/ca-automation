# Phase 2: Automating Compliance Check and Policy Enforcement

Automate the detection and remediation of compliance drift between Azure RBAC assignments and Conditional Access group membership across High Security subscriptions. The system uses Terraform as the single source of truth for CA group membership, with a scheduled compliance scanner that identifies mismatches and raises pull requests to reconcile state. Remediation is risk-based: low-risk drift is resolved automatically while high-risk or bulk changes require human review.

---

## Automated CA Group Membership Detection

The system automatically detects when a user has Azure RBAC access on a High Security subscription but is not protected by Conditional Access, ensuring no user can access HS resources without CA enforcement.

**Acceptance Criteria**
- Scanner identifies all users with RBAC assignments across all HS subscriptions at subscription, resource group, and resource scope
- Scanner compares RBAC results against live CA group membership
- Any user with RBAC not in the CA group is flagged as non-compliant
- Detection runs without manual intervention

---

## Scheduled Subscription Scanning

Compliance scans run automatically on a schedule so that drift is detected and remediated without relying on manual runs.

**Acceptance Criteria**
- Scanner runs on a defined schedule via pipeline cron trigger
- Scanner can also be triggered manually via pipeline dispatch
- Scan results are written to a JSON artifact and surfaced in the pipeline job summary
- Scanner exits 0 when compliant or auto-remediated, 1 when human action is required, 2 for investigation mode

---

## Drift Detection and Reconciliation

The system detects and reconciles drift between Terraform state and live Azure/Entra ID state, ensuring `members.yml` remains the single source of truth for CA group membership.

**Acceptance Criteria**
- SC-01: User has RBAC but is not in CA group - UPN added to `members.yml`, PR auto-merged, Terraform adds to group
- SC-02: User manually added to CA group outside Terraform - UPN added to `members.yml`, PR auto-merged (if user has RBAC)
- SC-03: User removed from CA group while retaining RBAC - UPN restored in `members.yml`, PR auto-merged, Terraform re-adds to group
- SC-05: User in CA group with no HS RBAC roles - PR raised to remove UPN from `members.yml`, requires human approval
- SC-04: Drift count exceeds bulk threshold - investigation mode, no auto-remediation
- All group membership changes are made exclusively by Terraform, not PowerShell

---

## Risk Based Approval Workflow

Remediation actions are approved automatically or escalated based on risk level so that low-risk drift is resolved without delay while high-risk changes require visibility.

**Acceptance Criteria**
- SC-01, SC-02, SC-03: Auto-merged, no human approval needed, security is maintained or restored
- SC-05: PR raised and left open, human must review before a user is removed from CA protection
- SC-04 (bulk drift): No PRs raised, investigation required before any remediation
- All remediation actions are traceable via pull request history
- PR titles and bodies clearly indicate scenario, user, risk level, and action taken
