# Spec Delta

## Purpose

This capability covers how the workbench is built, deployed (a hosted Render preview plus a local Docker Compose fallback), observed, verified and rolled back, so reviewers and operators can reproduce and trust a running instance.

## ADDED Requirements

### Requirement: Health check reflects dependencies
The system SHALL expose an unauthenticated health endpoint. It SHALL return 200 only when the application can query its primary database, and 503 otherwise. The response SHALL contain no data beyond the status.

#### Scenario: Healthy instance
- **WHEN** the app and database are up
- **THEN** the health endpoint returns 200

#### Scenario: Database unreachable
- **WHEN** the database is unreachable
- **THEN** the health endpoint returns 503, and the deploy tooling doesn't route traffic to that instance

### Requirement: No secrets in the repository
The repository SHALL NOT contain credentials, registry tokens, database passwords, signing keys or the Rails master key. Deploy secrets SHALL be entered in the hosting platform's secret settings, never in versioned files.

#### Scenario: Secret scan of the repository
- **WHEN** the repository is inspected
- **THEN** `config/master.key` and any `.env` file are git-ignored, and the deployment Blueprint declares secrets only as values to be entered on the platform, never with their values

### Requirement: Self-provisioning hosted preview
The hosted preview SHALL be fully described by a versioned infrastructure file. A deploy SHALL apply pending migrations and load demo data automatically when the app starts, with no interactive shell or manual step. Platform limits that affect reviewers SHALL be documented: sleeping when idle, cold-start delay, database expiry and the absence of backups.

#### Scenario: First deploy from the Blueprint
- **WHEN** an operator creates the services from the versioned Blueprint and enters the required secrets
- **THEN** the app starts, migrates, loads demo data, and the health endpoint returns 200, with no further commands

#### Scenario: Redeploy keeps data
- **WHEN** a new version is deployed onto an existing database
- **THEN** only pending migrations run, demo data isn't duplicated, and audit history is preserved

#### Scenario: Waking from idle
- **WHEN** the preview receives a request after sleeping
- **THEN** it serves the request after the documented cold-start delay, with the same data as before it slept

### Requirement: Reproducible local deployment
A reviewer SHALL be able to start the production-mode app with a single documented command, with no registry account, cloud account or provided secret. The started app SHALL hold the demo data.

#### Scenario: Compose fallback
- **WHEN** a reviewer runs the documented compose command on a clean machine with Docker
- **THEN** the app is served locally in production mode with seeded demo data, and the health endpoint returns 200

### Requirement: Safe roll forward and roll back
Deploys SHALL switch traffic only after the new version passes its health check. Schema migrations SHALL be backward-compatible with the previous app version, so rolling back the app doesn't require rolling back the schema.

#### Scenario: Failed health check on deploy
- **WHEN** a new version fails its health check during deploy
- **THEN** traffic stays on the previous version

#### Scenario: Roll back after a bad release
- **WHEN** an operator rolls back to the previous deploy using the documented platform rollback
- **THEN** the previous version serves traffic against the current schema without errors

### Requirement: Traceable, privacy-safe logs
Every request log line SHALL carry a request id. Logs of authenticated requests SHALL carry the user id and company id. Passwords, session tokens and idempotency keys SHALL NOT appear in logs.

#### Scenario: Tracing an approval
- **WHEN** an operator searches logs for the request id of an approval
- **THEN** they find the request with its user id, company id and response status

#### Scenario: Sign-in logged
- **WHEN** a user signs in
- **THEN** the logged parameters show the password as filtered

### Requirement: Continuous verification
Every push and pull request SHALL run the full automated spec suite against PostgreSQL, plus style and security checks. A failure in any of them SHALL fail the build.

#### Scenario: Failing spec
- **WHEN** a commit breaks a spec
- **THEN** the CI run fails and identifies the failing spec
