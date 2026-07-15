# Onboarding Document Checklist — Agentforce LWC for Capital Markets

A Salesforce Lightning Web Component (LWC) for internal onboarding agents to review client-submitted documents, take inline review actions, and run Einstein AI-powered document analysis — all from the Case record page.

Built for capital markets onboarding workflows. Designed to be cloned and deployed to any Salesforce org with the prerequisites below.

---

## What It Does

- **Two-level accordion** — Case → Checklist categories → Document items
- **Submission status** — shows which documents have been uploaded vs. outstanding
- **Inline review** — Approve, Reject (with reason), or Waive each document item without leaving the page
- **AI Document Analysis** — single "Analyze All Documents" button invokes an Agentforce Flex Prompt Template against every submitted file; results appear inline with a red flag on documents that need attention
- **Document preview modal** — view the uploaded file in a full-screen overlay

---

## Data Model

```
Case
 └── Onboarding_Document_Checklist__c      (grouped by category)
      └── Onboarding_Document_Checklist_Item__c   (one per document requirement)
           ├── Onboarding_Document_Type__c         (document template/instructions)
           └── Content_Document_Id__c              (Id of the uploaded Salesforce File)
```

### Checklist Categories

`Legal & Entity` · `Compliance & Regulatory` · `Authorized Traders` · `Financial` · `Other`

### Checklist Item Statuses

`Not Started` · `Pending Review` · `Approved` · `Rejected` · `Expired` · `Waived`

---

## Prerequisites

| Requirement                      | Notes                                                                 |
| -------------------------------- | --------------------------------------------------------------------- |
| Salesforce org API version 66.0+ | Required for LWC and Apex compatibility                               |
| Einstein Generative AI enabled   | Setup → Einstein Setup → Enable Einstein                              |
| Prompt Templates enabled         | Setup → Prompt Template Settings                                      |
| Einstein Flex Credits            | Required for AI document analysis                                     |
| Salesforce CLI (`sf`)            | [Install guide](https://developer.salesforce.com/tools/salesforcecli) |

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/<your-username>/onboarding-doc-checklist-agentforce-capitalmarkets-lwc.git
cd onboarding-doc-checklist-agentforce-capitalmarkets-lwc
```

### 2. Authenticate your org

```bash
sf org login web --alias MyOnboardingOrg
```

### 3. Deploy objects and code

```bash
sf project deploy start --target-org MyOnboardingOrg
```

This deploys:

- All 3 custom objects with their fields
- `CapDocumentChecklistController` Apex class + test
- `capDocumentChecklist` LWC

### 4. Create the Prompt Template

Follow the step-by-step guide: **[docs/PROMPT_TEMPLATE_SETUP.md](docs/PROMPT_TEMPLATE_SETUP.md)**

> The template must be created manually in Setup — Salesforce CLI does not yet support Prompt Template deployment in API 66.0.

### 5. Load sample data (no files required)

```bash
sf apex run --file scripts/apex/createSampleData.apex --target-org MyOnboardingOrg
```

Creates 13 document items across 5 checklist categories on a new Case with realistic mixed statuses. The Debug Log prints the new Case Id.

### 6. Add the component to the Case record page

1. Open the Case record created in Step 5
2. Gear icon → **Edit Page**
3. Find `capDocumentChecklist` in the custom components panel
4. Drag it onto the page layout and click **Save** → **Activate**

---

## File Structure

```
force-app/main/default/
├── lwc/capDocumentChecklist/
│   ├── capDocumentChecklist.html          # Two-level accordion template
│   ├── capDocumentChecklist.js            # Controller — wire, events, state
│   ├── capDocumentChecklist.css           # SLDS-compatible styles
│   └── capDocumentChecklist.js-meta.xml  # Targets lightning__RecordPage (Case)
├── classes/
│   ├── CapDocumentChecklistController.cls
│   └── CapDocumentChecklistControllerTest.cls
└── objects/
    ├── Onboarding_Document_Checklist__c/
    ├── Onboarding_Document_Checklist_Item__c/
    └── Onboarding_Document_Type__c/

scripts/apex/createSampleData.apex    # Demo record generator
docs/PROMPT_TEMPLATE_SETUP.md         # Prompt template setup guide
docs/superpowers/specs/               # Full design spec
```

---

## Apex Controller Methods

| Method                                                     | Notes                                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------------------ |
| `getChecklistData(caseId)`                                 | Wire-compatible; returns checklists + items for the Case                 |
| `analyzeDocuments(itemIds)`                                | Invokes Flex Prompt Template per item; returns `Map<Id, AnalysisResult>` |
| `updateItemReview(itemId, status, rejectionReason, notes)` | Updates item status, reviewer, reviewed date, and notes                  |

---

## AI Analysis — How It Works

1. Agent clicks **⚡ Analyze All Documents**
2. LWC calls `analyzeDocuments()` with all item Ids that have an uploaded file
3. Apex invokes `CAP_Document_Analysis` Flex Prompt Template via `ConnectApi.EinsteinLLM`
4. Einstein reads each file (text extraction + OCR for scanned images) and returns `SUMMARY`, `ISSUES`, and `STATUS`
5. Items with `STATUS: ACTION REQUIRED` show a red flag badge

**Flex credit usage:** One credit per document, only when the button is clicked — not on page load.

---

## Running Tests

```bash
sf apex run test --class-names CapDocumentChecklistControllerTest --target-org MyOnboardingOrg --result-format human
```

---

## Extending This Component

**New categories:** Add picklist values to `Category__c` on both checklist objects — the LWC renders categories dynamically.

**Cache AI results:** Add an `AI_Analysis__c` long text area to `Onboarding_Document_Checklist_Item__c` and persist results after the first run to avoid re-spending credits on repeat page visits.

**Expiration alerts:** Add a computed `isNearExpiry` property in `_mapItem()` in the JS controller checking `Expiration_Date__c` within 30 days.

---

## License

MIT — free to use, modify, and distribute.
