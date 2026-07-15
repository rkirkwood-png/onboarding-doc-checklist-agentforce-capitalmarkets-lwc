# CAP Document Checklist LWC — Design Spec

**Date:** 2026-07-15
**Project:** MarketAxess Client Application Portal (CAP)
**Org Alias:** `MarketAxcess-Onboarding` (trailsignup.cb3e6dace8d50f@salesforce.com)
**API Version:** 66.0

---

## 1. Purpose

The `capDocumentChecklist` Lightning Web Component gives internal MarketAxess onboarding agents a single, structured view of all documents a client has submitted during onboarding. Agents can see submission status, run AI-powered document analysis, review inline, and approve/reject/waive each checklist item without leaving the Case record page.

---

## 2. Data Model

### Object Hierarchy

```
Case
 └── Onboarding_Document_Checklist__c  (one per category, e.g. Legal & Entity)
      └── Onboarding_Document_Checklist_Item__c  (one per document requirement)
           ├── Onboarding_Document_Type__c  (document template — name, instructions)
           └── Content_Document_Id__c  (Id of the uploaded file in Salesforce Files)
```

### Key Object API Names

**Onboarding_Document_Checklist__c**

| Field          | API Name            | Type         |
| -------------- | ------------------- | ------------ |
| Case           | `Case__c`           | Lookup(Case) |
| Category       | `Category__c`       | Picklist     |
| Status         | `Status__c`         | Picklist     |
| Items Approved | `Items_Approved__c` | Number       |
| Items Total    | `Items_Total__c`    | Number       |
| Assigned Team  | `Assigned_Team__c`  | Text         |
| Notes          | `Notes__c`          | TextArea     |

Category picklist values: `Legal & Entity`, `Compliance & Regulatory`, `Authorized Traders`, `Financial`, `Other`
Status picklist values: `Not Started`, `In Progress`, `Complete`, `Blocked`

**Onboarding_Document_Checklist_Item__c**

| Field            | API Name                           | Type                  |
| ---------------- | ---------------------------------- | --------------------- |
| Checklist        | `Onboarding_Document_Checklist__c` | Lookup(Checklist)     |
| Case             | `Case__c`                          | Lookup(Case)          |
| Document Type    | `Document_Type__c`                 | Lookup(Document Type) |
| Uploaded File    | `Content_Document_Id__c`           | Text                  |
| Status           | `Status__c`                        | Picklist              |
| Is Required      | `Is_Required__c`                   | Checkbox              |
| Due Date         | `Due_Date__c`                      | Date                  |
| Expiration Date  | `Expiration_Date__c`               | Date                  |
| Submitted Date   | `Submitted_Date__c`                | DateTime              |
| Reviewer         | `Reviewer__c`                      | Lookup(User)          |
| Reviewed Date    | `Reviewed_Date__c`                 | DateTime              |
| Rejection Reason | `Rejection_Reason__c`              | TextArea              |
| Notes            | `Notes__c`                         | TextArea              |

Item Status picklist values: `Not Started`, `Pending Review`, `Approved`, `Rejected`, `Expired`, `Waived`

**Onboarding_Document_Type__c**

| Field                      | API Name                        | Type     |
| -------------------------- | ------------------------------- | -------- |
| Name                       | `Name`                          | Text     |
| Category                   | `Category__c`                   | Picklist |
| Is Required                | `Is_Required__c`                | Checkbox |
| Instructions for Submitter | `Instructions_for_Submitter__c` | TextArea |
| Allowed File Types         | `Allowed_File_Types__c`         | Text     |
| Sort Order                 | `Sort_Order__c`                 | Number   |
| Expiration Required        | `Expiration_Required__c`        | Checkbox |

---

## 3. Architecture Decision: Two-Level Nested Accordion

Three options were evaluated:

- **A — Flat list:** Simple but unwieldy at 15+ documents across 5 categories
- **B — Tabbed by category:** Focused but prevents seeing the full case at once
- **C — Two-level nested accordion (chosen):** Mirrors the data model, shows overall progress per category, scales well

**Rationale:** The nested accordion maps directly to the Checklist → Item hierarchy and allows agents to see at a glance which categories are complete vs. blocked without scrolling or tab-switching.

---

## 4. UI Layout

### Component Header

- Title: "Document Checklist"
- Subtitle: aggregate progress (e.g. "11 of 18 Items Approved") summed across all checklists
- "⚡ Analyze All Documents" button — disabled if no items have `Content_Document_Id__c` populated

### Top-Level Accordion (per Onboarding_Document_Checklist__c)

Each section header displays:

- Category name
- Progress pill: `X / Y Approved` using `Items_Approved__c` / `Items_Total__c`
- Status badge (color-coded: green=Complete, yellow=In Progress, grey=Not Started, red=Blocked)
- Collapsed by default; expand to show items

### Second-Level Rows (per Onboarding_Document_Checklist_Item__c)

Collapsed row shows:

- Document type name
- `Required` badge (if `Is_Required__c = true`)
- Submission badge: green "● Submitted" if `Content_Document_Id__c` is populated, grey "Not Submitted" if not
- Item status badge
- Red flag icon ⚑ if Agentforce analysis returned `ACTION REQUIRED`

Expanded row shows:

1. **AI Analysis callout** — blue border for `READY FOR REVIEW`, red border for `ACTION REQUIRED`; shows SUMMARY text and ISSUES bullet list. Shows "Not yet analyzed" italic text if analysis hasn't been run.
2. **"View Document" button** — opens document preview modal (only shown if file is uploaded)
3. **Review action buttons:** Approve / Reject / Waive
4. **Rejection Reason textarea** — appears inline when Reject is selected
5. **Notes field** — editable, saves on blur
6. **Metadata row** — Due Date, Submitted Date, Reviewer (read-only)

### Document Preview Modal

- Triggered by "View Document" button
- Renders the uploaded file using Salesforce's `lightning-file-download` or a `lightning-card` wrapping `lightning-formatted-url` pointing to the ContentDocument
- Full-screen overlay; close button dismisses it
- AI analysis remains visible in the LWC behind the modal

---

## 5. Agentforce / Prompt Template Integration

### Decision: User-Driven "Analyze All" (not auto-on-load)

Auto-running analysis on page load was considered but rejected because:

- 10–20 concurrent Einstein API calls on every page open would hurt performance
- Risk of hitting Einstein Flex Credit limits on busy days
- Agents may not always need AI analysis (e.g. re-opening a completed case)

Single "Analyze All" button gives agents control over when to spend flex credits, keeps initial page load fast, and surfaces insights when they're actually needed.

### Prompt Template: CAP_Document_Analysis

**Type:** Flex
**API Name:** `CAP_Document_Analysis`
**Status:** Active in org

**Inputs:**

| Name                  | API Name                | Source Type   | Notes                                                            |
| --------------------- | ----------------------- | ------------- | ---------------------------------------------------------------- |
| Document              | `Document`              | Object (File) | ContentDocumentId; Einstein handles text extraction and OCR      |
| Document Type Name    | `Document_Type_Name`    | Free Text     | From `Onboarding_Document_Type__c.Name`                          |
| Document Instructions | `Document_Instructions` | Free Text     | From `Onboarding_Document_Type__c.Instructions_for_Submitter__c` |

**Prompt Text:**

```
You are an onboarding document reviewer for a financial services firm.
A client has submitted a document during their onboarding process.

Expected Document Type: {!Input:Document_Type_Name}
Submission Instructions: {!Input:Document_Instructions}

Submitted Document:
{!Input:Document}

Analyze the submitted document and respond using ONLY this exact format.
Do not add any other text outside of these three fields:

SUMMARY: [2-3 sentences: what is this document, does it appear to be the correct type, and is the content legible?]

ISSUES: [Bullet list of blank fields, missing signatures, incomplete sections, or illegible areas. Write "None detected." if the document appears complete.]

STATUS: [Write exactly one of: READY FOR REVIEW | ACTION REQUIRED]
```

**Output parsing:** Apex parses the three labelled sections by splitting on `SUMMARY:`, `ISSUES:`, and `STATUS:`. The `STATUS` value drives the flag badge in the LWC.

---

## 6. Apex Controller Design

**Class:** `CapDocumentChecklistController`

### Method 1 — `getChecklistData`

```
@AuraEnabled(cacheable=true)
public static List<ChecklistWrapper> getChecklistData(Id caseId)
```

- Queries all `Onboarding_Document_Checklist__c` for the Case, ordered by `Category__c`
- Sub-queries all child `Onboarding_Document_Checklist_Item__c`, each with related `Onboarding_Document_Type__c` fields
- Returns a list of `ChecklistWrapper` inner classes (serializable for LWC wire)
- Marked `cacheable=true` for wire adapter performance

### Method 2 — `analyzeDocuments`

```
@AuraEnabled
public static Map<Id, AnalysisResult> analyzeDocuments(List<Id> itemIds)
```

- Accepts the list of Item Ids that have `Content_Document_Id__c` populated
- For each item, builds the input map and calls:
  `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('CAP_Document_Analysis', promptInput)`
- Parses each response into an `AnalysisResult` inner class with fields: `summary`, `issues`, `status`, `hasIssues`
- Returns a `Map<Id, AnalysisResult>` keyed by Item Id
- NOT cacheable (Agentforce calls are not idempotent)

### Method 3 — `updateItemReview`

```
@AuraEnabled
public static void updateItemReview(Id itemId, String status, String rejectionReason, String notes)
```

- Updates `Status__c`, `Rejection_Reason__c`, `Notes__c`, `Reviewer__c` (set to `UserInfo.getUserId()`), and `Reviewed_Date__c` on the specified Item
- Throws `AuraHandledException` with a user-friendly message on DML failure

### Test Class: `CapDocumentChecklistControllerTest`

- Minimum 85% code coverage
- Uses `@TestSetup` to create a Case, Checklist, Items, and Document Type records
- Mocks `ConnectApi` calls using a stub or test override pattern for `analyzeDocuments`

---

## 7. LWC Files

| File                                     | Purpose                                             |
| ---------------------------------------- | --------------------------------------------------- |
| `capDocumentChecklist.html`              | Template — two-level accordion markup               |
| `capDocumentChecklist.js`                | Controller — wire, event handlers, state management |
| `capDocumentChecklist.js-meta.xml`       | Metadata — targets `lightning__RecordPage`          |
| `capDocumentChecklist.css`               | Styles — badge colors, callout borders, spacing     |
| `CapDocumentChecklistController.cls`     | Apex — data retrieval, analysis invocation, DML     |
| `CapDocumentChecklistControllerTest.cls` | Apex test — 85%+ coverage                           |

**LWC component path:**
`force-app/main/default/lwc/capDocumentChecklist/`

**Apex path:**
`force-app/main/default/classes/`

---

## 8. Client Sandbox Replication Prerequisites

Before deploying this component to a new sandbox, the following must be in place:

1. **Einstein Generative AI enabled** — Setup → Einstein Setup → turn on Einstein
2. **Prompt Templates enabled** — Setup → Prompt Template Settings → Enable Prompt Templates
3. **Flex Credits allocated** — confirm org has Einstein Flex Credits available
4. **Custom objects deployed** — `Onboarding_Document_Checklist__c`, `Onboarding_Document_Checklist_Item__c`, `Onboarding_Document_Type__c` with all fields listed in Section 2
5. **Prompt Template created** — follow Section 5 to recreate `CAP_Document_Analysis` in the target org (Flex type, three inputs as specified)
6. **Connected App / API access** — `ConnectApi.EinsteinLLM` requires API-enabled profiles; ensure the running user profile has API access
7. **Lightning App Builder** — add `capDocumentChecklist` to the Case record page via Setup → Lightning App Builder

---

## 9. Open Items / Future Enhancements

- Prompt Template to be stored as metadata (`.prompt` file) once Salesforce CLI Prompt Template deployment is stable in API 66+
- Consider caching analysis results back to `Notes__c` or a dedicated field to avoid re-running Einstein on subsequent page visits
- Expiration date alerting (badge or warning when `Expiration_Date__c` is within 30 days)
