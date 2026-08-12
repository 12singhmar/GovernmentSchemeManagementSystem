# Government Scheme Management System

An Oracle SQL database project that models the workflow for administering public-benefit schemes: citizen registration, eligibility checks, applications, officer decisions, fund disbursements, audit history, and reporting.

The repository also includes a standalone browser prototype of an officer portal. It is a front-end demonstration only; it is not connected to the database.

> **Academic project notice:** the system, schemes, people, identifiers, and financial details in this repository are fictional demonstration data. This is not an official government service and must not be used to process personal information.

## Highlights

- normalized Oracle schema with primary keys, foreign keys, constraints, and checks
- eligibility rules and scheme fund-pool tracking
- PL/SQL procedures/functions for applications, approvals, benefits, and reporting
- triggers for application audit history, fund updates, and duplicate-application checks
- 30 example queries covering operational reporting and analytics
- responsive officer-portal UI prototype

## Repository contents

| File | Description |
| --- | --- |
| `GSMS_ORACLE_FINAL.sql` | Main Oracle SQL/PLSQL script: schema, seed data, business logic, demo flow, and queries. |
| `index.html` | Standalone officer-portal interface prototype. Open directly in a browser. |

## Run the database project

### Prerequisites

- Oracle Database XE, Oracle Live SQL, or another Oracle environment with PL/SQL support
- A database user with permission to create tables, sequences/identity columns, triggers, procedures, and views

### Steps

1. Create a new schema/user for the project rather than using a shared production schema.
2. Open `GSMS_ORACLE_FINAL.sql` in Oracle SQL Developer, SQLcl, or Oracle Live SQL.
3. Enable `DBMS Output` in SQL Developer if you want to see the demonstration messages.
4. Run the script from top to bottom in a fresh schema.
5. Review the final query sections for example operational and analytical reports.

The script is designed as a complete academic demonstration. Re-running it in the same schema without first dropping existing objects may cause “already exists” errors.

## Browser prototype

Open `index.html` in a modern browser. It is intentionally kept separate from the SQL project so the UI can be shown without installing a backend.

The portal demonstrates navigation, role-based screens, filters, forms, status indicators, and reporting views. The data shown in it is local, fictional demo data.

## Design notes

The database models these main relationships:

```text
Department → Scheme → Scheme eligibility rules / fund pool
Citizen → Application → Officer decision → Fund disbursement
Application → Application audit log
Citizen → Citizen documents
```

Business rules are enforced at more than one layer: table constraints protect data shape, PL/SQL captures workflow logic, and triggers record or react to important status and payment events.

## Future improvements

- split the SQL script into schema, seed-data, stored-program, and reporting files
- connect the browser prototype to a REST backend
- add authentication and role-based authorization in the application layer
- add repeatable schema setup/teardown scripts and test data
- never store real government IDs, bank details, or citizen records in source control
