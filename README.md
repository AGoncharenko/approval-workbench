# Approval workbench

Accounts-payable invoice approval workbench (Rails 8.1, Ruby 4.0, PostgreSQL 18). All data is synthetic.

## Local setup

PostgreSQL 18 is expected on `localhost:5433` (override with `PGPORT`).

```sh
bin/rails db:prepare db:seed
bin/dev
bundle exec rspec
```

## Demo accounts

Every seeded account uses the demo password `demo-password-2026`, unless `DEMO_PASSWORD` was set when the seeds were loaded.

| Email | Role | Company |
| --- | --- | --- |
| requester@acme.example.com | requester | Acme Industries |
| approver1@acme.example.com | approver | Acme Industries |
| approver2@acme.example.com | approver | Acme Industries |
| admin@acme.example.com | admin | Acme Industries |
| requester@globex.example.com | requester | Globex Trading |
| approver1@globex.example.com | approver | Globex Trading |
| approver2@globex.example.com | approver | Globex Trading |
| admin@globex.example.com | admin | Globex Trading |
