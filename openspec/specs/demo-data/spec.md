# demo-data Specification

## Purpose
This capability covers the synthetic demo dataset that reviewers and the five-minute demo rely on. It must be identical on every machine and every deploy, and safe to load repeatedly.

## Requirements

### Requirement: Synthetic-only demo data
Demo data and automated-test data SHALL contain only invented companies, people, vendors and amounts. They SHALL contain no real customer or employer information.

#### Scenario: Reviewing seeded records
- **WHEN** a reviewer inspects any seeded company, user or vendor
- **THEN** every name and email is fictional, and emails use a reserved domain such as `example.com`

#### Scenario: Test data
- **WHEN** the automated test suite builds records
- **THEN** every generated name and email is fictional, and emails use a reserved domain

### Requirement: Deterministic demo data
Loading demo data SHALL produce the same records, with the same names, emails, roles, vendors, amounts and currencies, on every run and in every environment. Due dates SHALL be fixed day offsets from the date of the first load, so the demo stays current and existing records keep their dates on re-load. This lets documented demo steps refer to exact records. Apart from generated identifiers (UUIDs) and timestamps, demo data SHALL NOT depend on random values.

#### Scenario: Fresh environments match
- **WHEN** demo data is loaded into two empty databases
- **THEN** both contain identical companies and users, and the users listed in the README exist with the documented roles

### Requirement: Documented demo credentials
Every seeded user SHALL be able to sign in with a single documented demo password. Operators SHALL be able to override that password at seed time without changing code.

#### Scenario: Default demo password
- **WHEN** demo data is loaded without an override
- **THEN** every seeded user can sign in with the password documented in the README

#### Scenario: Overridden demo password
- **WHEN** demo data is loaded into an empty database with an operator-supplied password
- **THEN** seeded users sign in with that password, and the documented default is rejected

### Requirement: Idempotent demo data load
Loading demo data again into a database that already holds it SHALL NOT create duplicates and SHALL NOT fail.

#### Scenario: Seed runs twice
- **WHEN** demo data is loaded a second time
- **THEN** the counts of companies and users are unchanged

### Requirement: Demo data loadable in every environment
Demo data SHALL be loadable in development, test and production using only the application's runtime dependencies. Test-only tooling SHALL NOT be required.

#### Scenario: Seeding a deployed instance
- **WHEN** an operator loads demo data on a production deployment
- **THEN** the load succeeds without development or test gems installed
