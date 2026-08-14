# CAP Document Checklist — Client Handoff & Design Decisions

**Component:** `capDocumentChecklist`
**Org:** MarketAxess CAP (Capital Markets Platform)
**Author:** Ryan Kirkwood
**Date:** 2026-07-15

This document records every non-obvious design decision made during the build so the engineering team can understand the "why" behind each choice and make informed changes.

---

## 1. Architecture Decisions

### 1.1 Single LWC on the Case Record Page

**Decision:** All checklist, item, and review functionality lives in one component (`capDocumentChecklist`) placed on the Case record page.

**Why:** The onboarding agent's workflow is Case-centric. All checklist categories and document items for a client are accessed from the same record. A single Case-scoped component eliminates navigation overhead and keeps the review workflow in context.

**Alternative considered:** Multiple smaller components (one per category). Rejected because coordinating state across siblings (e.g., "Analyze All" across categories) would require either a parent component or a custom LMS channel — unnecessary complexity at this stage.

---

### 1.2 Two-Level Accordion Pattern

**Decision:** Top level = checklist categories, second level = document items per category.

**Why:** Agents work through documents category by category. The accordion collapses completed categories so the agent can focus on what's outstanding. Flat list rendering would require scrolling through all items simultaneously.

**Implementation note:** State is tracked with `_expandedChecklists` (Set of checklist IDs) and `_expandedItems` (Set of item IDs) in the JS controller, not with server-side data. Toggling is purely client-side to avoid round trips.

---

### 1.3 `@wire` for Data Fetching, Imperative Call for DML

**Decision:** `getChecklistData` is a cacheable `@wire` method. `updateItemReview` is an imperative call (not `@wire`).

**Why:** Wire is ideal for read-only data because LWC manages cache and re-rendering automatically. DML operations must be imperative because they need explicit error handling and must trigger `refreshApex` to invalidate the cache after a successful save. Mixing `@wire` with DML actions is the standard LWC pattern.

---

### 1.4 `WITH USER_MODE` and `update as user` in Apex

**Decision:** The SOQL query uses `WITH USER_MODE` and the DML update uses `update as user`.

**Why:** This enforces field-level security and object-level sharing rules based on the running user's profile — the query returns only what the user is allowed to see, and the update respects what fields the user is allowed to write. Without this, a running user with limited permissions could still read or write data via the Apex class if the class runs in system context. Required for org security posture.

---

## 2. Einstein AI Analysis Decisions

### 2.1 User-Triggered "Analyze All" Instead of On-Load

**Decision:** Einstein analysis runs only when the agent clicks "⚡ Analyze All Documents". It does not run automatically on page load.

**Why:** Each document analysis consumes one Einstein Flex Credit. A Case with 13 documents would burn 13 credits every page load. This decision keeps credit consumption user-driven and predictable. The agent opens the Case, reviews status visually, and decides whether to run analysis.

**Trade-off:** Agents see the AI insights 2–5 seconds later than they would on auto-load. Acceptable given the credit cost.

**Future enhancement:** Cache the analysis result in an `AI_Analysis__c` long-text field on the item. On subsequent page loads, show cached results immediately and offer a "Re-analyze" button to refresh stale results. This gives instant insights without recurring credit spend.

---

### 2.2 Flex Prompt Template, Not Flow AI Action

**Decision:** AI invocation uses `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate()` in Apex rather than an Agentforce Flow AI action.

**Why:** The LWC needs to analyze multiple documents in a single button click and map each result back to its source item ID. Flow AI actions are designed for one-at-a-time sequential invocation and can't fan out in parallel within a single LWC event. The Apex approach allows processing all items in a loop and returning a `Map<Id, AnalysisResult>` in one call.

---

### 2.3 File Input → Record Snapshot (Not Content Document ID)

**Decision:** In the Prompt Template, the Document input uses **Record Snapshot** rather than "Content Document ID" as the merge field type.

**Why:** "Content Document ID" passes only the file identifier as a string — Einstein cannot extract file content from a raw ID. **Record Snapshot** tells Einstein to fetch and read the file's actual content, enabling OCR for scanned PDFs and text extraction for Word/Excel documents. This is the correct input type for document analysis use cases.

---

### 2.4 Structured Prompt Output Format

**Decision:** The prompt instructs Einstein to respond using exactly `SUMMARY:`, `ISSUES:`, and `STATUS:` labels.

**Why:** Free-form AI responses are unpredictable. Apex parses the response using `indexOf()` to split on these labels. If Einstein uses different formatting, parsing produces empty strings and the LWC shows blank analysis cards. The prompt explicitly says "Do not add any other text outside of these three fields" to minimize variance.

**Note:** This parsing approach is simple but brittle — if Einstein adds a preamble or trailing text, the labels may still be found with `indexOf`. The `STATUS:` field is restricted to exactly `READY FOR REVIEW` or `ACTION REQUIRED` because the LWC uses string comparison (`status === 'ACTION REQUIRED'`) to set the red flag badge.

---

### 2.5 Prompt Template API Name: `CAP_Document_Analysis`

**Decision:** The Apex class hardcodes the prompt template API name as `CAP_Document_Analysis`.

**Why:** Salesforce CLI does not support deploying Prompt Templates in API version 66.0 — they must be created manually in Setup. The API name is therefore a convention contract between the Apex class and the manually-created template. The name must match exactly. This is documented in `docs/PROMPT_TEMPLATE_SETUP.md`.

---

## 3. Review Workflow Decisions

### 3.1 Inline Rejection Reason, Not a Popup

**Decision:** When the agent clicks "Reject", a textarea expands below the item buttons rather than opening a modal.

**Why:** Modals interrupt workflow and require a separate dismiss action. Inline expansion keeps the agent in context — they can see the document item they're rejecting while typing the reason. The textarea only appears for the specific item being rejected (`_showRejectionFor` Set in the controller).

---

### 3.2 Reviewer and Reviewed Date Set in Apex, Not by the Agent

**Decision:** `Reviewer__c` is set to `UserInfo.getUserId()` and `Reviewed_Date__c` to `System.now()` in the Apex controller, not passed from the LWC.

**Why:** Setting these values on the client side would allow them to be spoofed or manipulated. The server stamps them at the time of the DML call, ensuring the audit trail is accurate regardless of latency or client-side manipulation.

---

### 3.3 Waive Action on All Items

**Decision:** Waive is available as a review action on every document item, not just optional ones.

**Why:** Required documents may still be waived under specific circumstances (e.g., exemptions for certain client types, regulatory edge cases). Restricting Waive to `Is_Required__c = false` items would require Apex enforcement changes later. The onboarding agent is responsible for the appropriateness of a waiver.

---

## 4. Data Model Decisions

### 4.1 Three-Object Model

**Decision:** Three objects: `Onboarding_Document_Type__c` (templates), `Onboarding_Document_Checklist__c` (category-level groups), `Onboarding_Document_Checklist_Item__c` (individual document requirements per Case).

**Why:**

- `Document_Type__c` is a reusable template that carries instructions and sort order. Separating it from the checklist item means updating instructions once updates all future items without touching existing Case data.
- `Checklist__c` (category-level) allows tracking per-category progress (`Items_Approved__c`, `Items_Total__c`, `Status__c`) without querying all items. The LWC uses these summary fields for progress pills.
- `Checklist_Item__c` (per-document per-Case) carries the submission and review lifecycle for each specific document.

---

### 4.2 `Content_Document_Id__c` on the Item

**Decision:** The uploaded file is linked via a text field `Content_Document_Id__c` on the checklist item, not via a standard Salesforce ContentDocumentLink.

**Why:** `ContentDocumentLink` is a junction object that can't be queried in the same SOQL sub-select as custom objects in a single wire-safe query. Storing the Content Document ID directly on the item avoids a second SOQL query or a separate wire to look up associated files. The ID is sufficient to generate a download/preview URL and to pass to the Prompt Template.

**Trade-off:** If the file is deleted from Salesforce, `Content_Document_Id__c` will hold a stale ID. The component should handle this gracefully — the `hasDocument` getter in the JS checks whether the field is populated, but attempting to preview a deleted file will return a 404. A future enhancement could add a validity check.

---

### 4.3 `Case__c` on the Item (Redundant Lookup)

**Decision:** `Onboarding_Document_Checklist_Item__c` has a direct `Case__c` lookup even though the Case can be derived through the parent checklist.

**Why:** Direct lookup improves SOQL performance for bulk operations and reporting. Reports filtering by Case don't need a cross-object filter through the checklist. The sample data script populates this field. The LWC queries through the parent checklist hierarchy (not directly by Case on the item) — the direct Case field is for reporting and list views.

---

## 5. Deployment Decisions

### 5.1 Manual Prompt Template Creation

**Decision:** The prompt template is set up manually via Salesforce Setup UI, not deployed via Salesforce CLI.

**Why:** Prompt Templates are not yet supported as deployable metadata in API version 66.0 via `sf project deploy`. Any future API support will require a `.promptTemplate-meta.xml` format that does not exist yet. Documentation in `docs/PROMPT_TEMPLATE_SETUP.md` provides a reproducible step-by-step guide for any team to create the template from scratch in under 15 minutes.

---

### 5.2 Anonymous Apex for Sample Data

**Decision:** Sample records are created via an Anonymous Apex script rather than Salesforce CLI data import.

**Why:** Anonymous Apex can use server-side logic (maps, loops, ID lookups) that JSON or CSV imports cannot. The script creates parent-child records in the correct order and links them by ID in memory — no separate import templates or data files required. Any team can run `sf apex run --file scripts/apex/createSampleData.apex` and get a fully populated demo Case.

---

## 6. Known Limitations and Recommended Enhancements

| Area                   | Limitation                                             | Recommended Fix                                                   |
| ---------------------- | ------------------------------------------------------ | ----------------------------------------------------------------- |
| AI result persistence  | Results are lost on page reload                        | Add `AI_Analysis__c` long-text field to Item; save after analysis |
| File deletion          | Stale `Content_Document_Id__c` produces 404 on preview | Validate file existence before showing preview button             |
| Bulk review            | Items must be reviewed one at a time                   | Add "Approve All Pending" bulk action button                      |
| Prompt Template deploy | Manual setup required                                  | Monitor Salesforce releases for Prompt Template metadata support  |
| Test coverage          | Einstein API calls not covered by tests                | Use mock for `ConnectApi.EinsteinLLM` in a dedicated test class   |

---

## 7. Relationship Name Note

The SOQL sub-query in `CapDocumentChecklistController.getChecklistData()` uses `Checklist_Items__r` as the child relationship name. This is defined in the field metadata as `<relationshipName>Checklist_Items</relationshipName>` on `Onboarding_Document_Checklist_Item__c.Onboarding_Document_Checklist__c`.

**If deploying to a new org:** After deploying the objects, verify this relationship name via:

```bash
sf sobject describe --sobject Onboarding_Document_Checklist_Item__c --target-org <alias> | grep -i relationship
```

If the org already has this object with a different relationship name, update line 8 of `CapDocumentChecklistController.cls` to match.
