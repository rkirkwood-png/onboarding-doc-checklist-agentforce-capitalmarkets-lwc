# Onboarding Document Checklist - Agentforce LWC for Capital Markets

A Salesforce Lightning Web Component (LWC) for internal onboarding agents to review client-submitted documents from a Case record page, take inline review actions, preview submitted files, and run Einstein AI document analysis using a Prompt Builder Flex Prompt Template.

This repository packages the LWC, Apex controller, custom object metadata, file-upload automation, setup guides, prompt-template instructions, sample data scripts, and test coverage needed to deploy the solution into another Salesforce org.

## What This Includes

- `capDocumentChecklist` LWC for the Case record page.
- `CapDocumentChecklistController` Apex class and tests.
- Custom objects for document types, checklist sections, and checklist items.
- Salesforce Files automation that updates checklist items when files are uploaded.
- Permission set metadata for onboarding admins.
- Prompt Template setup guide for `CAP_Document_Analysis`.
- Anonymous Apex scripts for sample data and ContentDocumentId backfill.
- LWC Jest tests for checklist behavior, AI summary display, single-document analysis, file preview, and record links.

## Key Features

- Two-level accordion: checklist sections grouped under a Case, with individual document items inside each section.
- Submission tracking: required/submitted/not submitted states and per-item lifecycle status.
- Inline review: approve, reject with reason, waive, and save reviewer notes without leaving the page.
- AI analysis: run analysis across all submitted documents or refresh one document at a time.
- Section AI summary: each checklist section can show `NIGO Flag (X/Y)` or `AI Clear (0/Y)`.
- Last analyzed timestamp: the UI shows whether the current page session has run a full analysis.
- File preview modal: resolves the latest `ContentVersion` and renders a Salesforce file rendition in the modal, with full preview and download fallbacks.
- Direct record access: each submitted file row links back to its `Onboarding_Document_Checklist_Item__c` record.

## Data Model

```text
Case
└── Onboarding_Document_Checklist__c
    └── Onboarding_Document_Checklist_Item__c
        ├── Onboarding_Document_Type__c
        └── Salesforce File / ContentDocument
```

### Objects

| Object                                  | Purpose                                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------ |
| `Onboarding_Document_Type__c`           | Reusable document requirement template library.                                            |
| `Onboarding_Document_Checklist__c`      | Section-level checklist header grouped by category for a Case.                             |
| `Onboarding_Document_Checklist_Item__c` | Per-document requirement record that tracks submission, AI analysis, review, and approval. |

### Common Categories

- Legal & Entity
- Compliance & Regulatory
- Authorized Traders
- Financial
- Other

### Checklist Item Statuses

- Not Started
- Pending Review
- Approved
- Rejected
- Expired
- Waived

## Repository Structure

```text
force-app/main/default/
├── classes/
│   ├── CapDocumentChecklistController.cls
│   ├── CapDocumentChecklistControllerTest.cls
│   ├── OnboardingContentDocumentLinkHandler.cls
│   └── OnboardingContentDocumentLinkHandlerTest.cls
├── lwc/capDocumentChecklist/
│   ├── __tests__/capDocumentChecklist.test.js
│   ├── capDocumentChecklist.css
│   ├── capDocumentChecklist.html
│   ├── capDocumentChecklist.js
│   └── capDocumentChecklist.js-meta.xml
├── objects/
│   ├── Onboarding_Document_Checklist__c/
│   ├── Onboarding_Document_Checklist_Item__c/
│   └── Onboarding_Document_Type__c/
├── permissionsets/
│   └── Onboarding_Admin.permissionset-meta.xml
└── triggers/
    └── OnboardingContentDocumentLinkTrigger.trigger

scripts/apex/
├── createSampleData.apex
└── backfillContentDocumentIds.apex

docs/
├── PROMPT_TEMPLATE_SETUP.md
└── superpowers/specs/2026-07-15-cap-document-checklist-design.md
```

## Prerequisites

Before deploying to another org, confirm:

- Salesforce CLI (`sf`) is installed.
- Target org is authenticated with an alias.
- Salesforce org supports the project API version.
- Einstein Generative AI is enabled.
- Prompt Templates are enabled.
- The target user has API access and access to run Prompt Builder / Einstein generation.
- Einstein Flex Credits are available for document analysis.

Authenticate to an org:

```bash
sf org login web --alias MyOnboardingOrg
```

## Deployment

From the project root:

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org MyOnboardingOrg \
  --wait 30
```

Assign the onboarding admin permission set:

```bash
sf org assign permset \
  --name Onboarding_Admin \
  --target-org MyOnboardingOrg
```

If you only need to deploy the latest LWC and Apex changes:

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/CapDocumentChecklistController.cls \
  --source-dir force-app/main/default/classes/CapDocumentChecklistControllerTest.cls \
  --source-dir force-app/main/default/lwc/capDocumentChecklist \
  --target-org MyOnboardingOrg \
  --wait 30
```

## Prompt Template Setup

The Apex controller expects a Prompt Builder Flex Prompt Template with this API name:

```text
CAP_Document_Analysis
```

Required inputs:

| Input                 | API Name                | Source Type   |
| --------------------- | ----------------------- | ------------- |
| Document              | `Document`              | Object / File |
| Document Type Name    | `Document_Type_Name`    | Free Text     |
| Document Instructions | `Document_Instructions` | Free Text     |

Important: for the `Document` merge field, use Record Snapshot so Einstein can access file content and OCR output.

Full instructions are in [`docs/PROMPT_TEMPLATE_SETUP.md`](docs/PROMPT_TEMPLATE_SETUP.md).

## Add the LWC to a Case Page

1. Open a Case record.
2. Click the gear icon and select **Edit Page**.
3. Find the custom component named `capDocumentChecklist`.
4. Drag it onto the Case record page.
5. Save and activate the Lightning page.

The component is exposed only for `lightning__RecordPage` and scoped to the `Case` object.

## Sample Data

Create demo checklist data:

```bash
sf apex run \
  --file scripts/apex/createSampleData.apex \
  --target-org MyOnboardingOrg
```

If files were uploaded before the ContentDocumentLink automation was deployed, backfill checklist items:

```bash
sf apex run \
  --file scripts/apex/backfillContentDocumentIds.apex \
  --target-org MyOnboardingOrg
```

## How File Upload Tracking Works

Salesforce Files create `ContentDocumentLink` records when users upload files to checklist item records. The included trigger and handler detect links to `Onboarding_Document_Checklist_Item__c` records and update:

- `Content_Document_Id__c`
- `Submitted_Date__c`
- `Status__c`

This allows the LWC and Prompt Template invocation to use the stored `ContentDocument` id.

## AI Analysis Flow

1. The agent clicks **Analyze All Documents** or **Analyze This Document**.
2. The LWC calls `analyzeDocuments({ itemIds })`.
3. Apex queries each submitted checklist item.
4. Apex invokes `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`.
5. The Prompt Template analyzes the uploaded Salesforce File.
6. Apex parses `SUMMARY:`, `ISSUES:`, and `STATUS:`.
7. The LWC renders item-level analysis and section-level `NIGO Flag (X/Y)` or `AI Clear (0/Y)` summaries.

Flex credit usage is user-triggered. One submitted document analysis consumes credits when analysis is run.

## File Preview Flow

The checklist item stores a `ContentDocument` id (`069...`). For inline modal previews, Apex resolves it to the latest `ContentVersion` id (`068...`), and the LWC renders a Salesforce rendition URL:

```text
/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=<ContentVersionId>
```

The modal also includes:

- **Open Full Preview**
- **Download**

These fallbacks help with file types or org settings that do not support inline rendition rendering.

## Testing

Install dependencies:

```bash
npm install
```

Run LWC Jest tests:

```bash
npm test
```

Run LWC ESLint:

```bash
npx eslint "force-app/main/default/lwc/**/*.js"
```

Run Apex tests:

```bash
sf apex run test \
  --class-names CapDocumentChecklistControllerTest,OnboardingContentDocumentLinkHandlerTest \
  --target-org MyOnboardingOrg \
  --result-format human
```

## Detailed Documentation

This README consolidates the project Markdown docs. The detailed source docs are still available:

- [`OnboardingLWCSetup.md`](OnboardingLWCSetup.md): LWC feature and setup overview.
- [`ONBOARDING_Object_SETUP.md`](ONBOARDING_Object_SETUP.md): full data model and object setup guide.
- [`GETTING_STARTED.md`](GETTING_STARTED.md): original quick-start guide.
- [`CLIENT_HANDOFF.md`](CLIENT_HANDOFF.md): design decisions and client handoff notes.
- [`docs/PROMPT_TEMPLATE_SETUP.md`](docs/PROMPT_TEMPLATE_SETUP.md): Prompt Builder setup and troubleshooting.
- [`docs/superpowers/specs/2026-07-15-cap-document-checklist-design.md`](docs/superpowers/specs/2026-07-15-cap-document-checklist-design.md): original design spec.

## Known Limitations

- Prompt Template metadata still requires manual setup in the target org.
- AI analysis results are stored client-side in the current session; they are not persisted after page refresh.
- Inline preview depends on Salesforce file rendition support for the uploaded file type.
- If a Salesforce File is deleted, `Content_Document_Id__c` can become stale until the item is updated.

## Recommended Enhancements

- Add persistent AI fields on `Onboarding_Document_Checklist_Item__c`.
- Store analysis timestamp server-side.
- Add validation for stale or deleted file ids.
- Add bulk review actions for operations teams.
- Convert Prompt Template setup to metadata deployment if Salesforce adds stable support.

## License

MIT - free to use, modify, and distribute.
