# Sistema Solares Environments

## DEV

Developer environment.

Disposable local DBs are allowed.

DEV SQLite files are not customer production.

Do not infer real customer data from repository DB files, generated test DBs, or local dev artifacts.

## LAB / UAT

Testing environment for controlled validation.

Disposable PostgreSQL databases are allowed.

Use this environment to test migrations, cloud authority, reconciliation, idempotency, and outbox behavior before production.

## CUSTOMER CURRENT PRODUCTION

Current production lives on the customer's PC.

Current operational source:

```text
app_local + SQLite sistema_solares.db
```

Migration work must use a verified copy of the customer DB and sidecar files. Do not run uncontrolled migrations against the live customer DB.

## FUTURE CLOUD PRODUCTION

Future production authority:

```text
Dedicated PostgreSQL authoritative DB
```

Backend owns business validation, financial rules, transactions, idempotency, concurrency protection, and permissions.

Local Windows storage becomes cache, offline outbox, device state, config, logs, and support/recovery files.

## Single Company

All environments are for a single company.

Existing `Company`, `companyId`, and `tenantKey` are retained as a fixed namespace until a later approved phase changes them.
