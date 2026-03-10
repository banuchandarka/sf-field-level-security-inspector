# Salesforce Field Level Security Inspector

A Salesforce DX project that helps admins and developers analyze **Field Level Security (FLS)** for a specific user and field.

The app shows:
- Whether the user has **Read** and/or **Edit** access.
- Which source grants the access:
  - Profile
  - Permission Set
  - Permission Set Group
  - Session-Based Permission Set

## Project Definition

This project provides one end-to-end feature:
- **LWC UI**: `fieldPermissionAnalyzer`
- **Apex backend**: `FieldPermissionAnalyzerController`

Main use case:
1. Search and select a user.
2. Select an object.
3. Select a field.
4. Run analysis to see effective access and source-level breakdown.

## Key Components

- `force-app/main/default/lwc/fieldPermissionAnalyzer/`
  - `fieldPermissionAnalyzer.html`: 3-step UI and result table
  - `fieldPermissionAnalyzer.js`: client logic, Apex calls, navigation, error handling
  - `fieldPermissionAnalyzer.css`: component styling
- `force-app/main/default/classes/FieldPermissionAnalyzerController.cls`
  - `searchUsers(searchTerm)`
  - `getAllObjects()`
  - `getObjectFields(objectApiName)`
  - `analyzeFieldPermissions(userId, objectApiName, fieldApiName)`
  - `getUserPermissionSets(userId)` (helper endpoint for assigned permission sets)

## Prerequisites

- Salesforce CLI (`sf`)
- Node.js and npm (for linting and LWC unit tests)
- Access to a Salesforce org (scratch org, sandbox, or dev org)

## Setup

1. Clone the repository.
2. Authenticate to an org:

```bash
sf org login web --alias fls-inspector-org
```

3. Deploy metadata:

```bash
sf project deploy start --target-org fls-inspector-org
```

4. Open the org:

```bash
sf org open --target-org fls-inspector-org
```

## Run the App

The component is exposed to:
- `lightning__AppPage`
- `lightning__HomePage`
- `lightning__Tab`

Use Lightning App Builder (or a Lightning Tab) to place **Field Permission Analyzer** in your org UI.

## Local Quality Commands

```bash
npm install
npm run lint
npm run test:unit
npm run prettier:verify
```

## Notes and Current Scope

- Analysis is based on assigned Profile/Permission Set metadata visible to the running context.
- Results show explicit field permission sources found for the selected field.
- Current repository includes scaffolded LWC tests and no Apex test class yet.

## Project Configuration

- Project name: `sf-field-level-security-inspector`
- Source directory: `force-app`
- Source API version: `66.0`
