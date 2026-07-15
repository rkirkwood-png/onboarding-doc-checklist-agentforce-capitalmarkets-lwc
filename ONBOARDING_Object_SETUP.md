# MarketAxess Onboarding Document Checklist — Setup Guide

This guide is a complete, end-to-end reference for standing up the MarketAxess onboarding document checklist data model in a fresh Salesforce org. It is written for a Claude instance (or a developer) that has org access and the SFDX CLI available.

---

## Table of Contents

1. [What You Are Building](#1-what-you-are-building)
2. [Clarifying Questions to Ask First](#2-clarifying-questions-to-ask-first)
3. [Prerequisites and Environment Setup](#3-prerequisites-and-environment-setup)
4. [Data Model Overview](#4-data-model-overview)
5. [Object and Field Definitions](#5-object-and-field-definitions)
   - 5.1 [Onboarding_Document_Type__c](#51-onboarding_document_type__c)
   - 5.2 [Onboarding_Document_Checklist__c](#52-onboarding_document_checklist__c)
   - 5.3 [Onboarding_Document_Checklist_Item__c](#53-onboarding_document_checklist_item__c)
6. [Case Record Type](#6-case-record-type)
7. [Permission Set](#7-permission-set)
8. [Page Layouts](#8-page-layouts)
9. [Flows](#9-flows)
10. [Apex Trigger and Handler](#10-apex-trigger-and-handler)
11. [Deployment Order and CLI Commands](#11-deployment-order-and-cli-commands)
12. [Manual Post-Deployment Steps](#12-manual-post-deployment-steps)
13. [Sample Data (Optional)](#13-sample-data-optional)
14. [Key Design Decisions and Why](#14-key-design-decisions-and-why)
15. [Validation Checklist](#15-validation-checklist)

---

## 1. What You Are Building

This is a custom Salesforce data model that replicates the FSC `DocumentChecklistItem` concept using entirely custom objects. It is designed for customers who do not use Financial Services Cloud.

The use case is firm onboarding for MarketAxess, a bond trading platform. When a new firm onboards, they must submit a set of compliance, legal, financial, and trader documents. This model provides:

- A **template library** of reusable document types (`Onboarding_Document_Type__c`)
- **Section headers** that group document requirements by category under a Case (`Onboarding_Document_Checklist__c`)
- **Individual document requirement records** that track submission, review, and approval per document per firm (`Onboarding_Document_Checklist_Item__c`)

The model hangs off the standard `Case` object using an `Onboarding` record type, giving operations teams a familiar object to work from while adding the document tracking layer on top.

---

## 2. Clarifying Questions to Ask First

Before deploying to any org, confirm the following with the user. The defaults listed are what was originally built for MarketAxess.

| #   | Question                                                                                                              | Default / Original Answer                             |
| --- | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 1   | What is the use case and industry? This determines sample document types and category names.                          | Bond trading platform firm onboarding (MarketAxess)   |
| 2   | What object should document checklists hang off of — Case, Opportunity, Account, or a custom object?                  | Case                                                  |
| 3   | Is Experience Cloud (formerly Community Cloud) in scope? This affects FLS, sharing model, and trigger behavior.       | Not in scope for initial build                        |
| 4   | Which profiles or permission sets need access to this feature?                                                        | System Administrator; Onboarding_Admin permission set |
| 5   | Are there existing Case record types in the org? Retrieve them before deploying to avoid overwriting picklist values. | Assume only the default Master type exists            |

If any answer differs from the default, note which metadata files will need to be adjusted before deployment. Most commonly: if the parent object changes from Case, all lookup field references and the Case record type metadata are irrelevant and should be replaced.

---

## 3. Prerequisites and Environment Setup

### Required tooling

- Salesforce CLI (`sf`) v2.x or later. Verify with `sf --version`.
- Node.js (required by the CLI). Verify with `node --version`.
- An authenticated org alias. The examples below use the alias `marketaxess-demo`.

### Authenticate to the org

```bash
# For a sandbox or scratch org
sf org login web --alias marketaxess-demo

# Verify authentication
sf org display --target-org marketaxess-demo
```

### Project structure

All metadata lives under `force-app/main/default/`. The CLI commands in this guide assume you are running from the SFDX project root (the directory containing `sfdx-project.json`).

```
force-app/main/default/
├── objects/
│   ├── Case/
│   │   ├── recordTypes/
│   │   └── listViews/
│   ├── Onboarding_Document_Type__c/
│   ├── Onboarding_Document_Checklist__c/
│   └── Onboarding_Document_Checklist_Item__c/
├── layouts/
├── flows/
├── triggers/
├── classes/
└── permissionsets/
```

### Retrieve the current Case metadata before touching it

This is critical if the org already has Case record types or picklist customizations. Overwriting them without retrieving first will delete existing values.

```bash
sf project retrieve start \
  --metadata "RecordType:Case.Master" \
  --target-org marketaxess-demo
```

If other record types exist, retrieve them all before deploying.

---

## 4. Data Model Overview

```
Case (record type: Onboarding)
 └── Onboarding_Document_Checklist__c  (1 per category per Case)
      └── Onboarding_Document_Checklist_Item__c  (1 per document per Case)
           └── Onboarding_Document_Type__c  (lookup to template library)
```

- A Case of record type `Onboarding` represents one firm's onboarding engagement.
- Each Case gets several `Onboarding_Document_Checklist__c` records — one per document category (e.g., Legal & Entity, Compliance & Regulatory).
- Each checklist contains multiple `Onboarding_Document_Checklist_Item__c` records — one per individual document requirement.
- `Onboarding_Document_Type__c` is a template library. Items reference types but are independent records; changing a template does not retroactively alter existing items.
- Files (uploaded PDFs, scans, etc.) are attached to Item records via Salesforce Files (`ContentDocument` / `ContentDocumentLink`). An Apex trigger detects the upload and updates the item's status and submission timestamp.

---

## 5. Object and Field Definitions

### 5.1 `Onboarding_Document_Type__c`

**Purpose:** Internal-only template library. Ops or compliance teams define reusable document types here. Items reference these but they are not required — an item can exist without a document type.

**Object metadata file:** `force-app/main/default/objects/Onboarding_Document_Type__c/Onboarding_Document_Type__c.object-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Onboarding Document Type</label>
    <pluralLabel>Onboarding Document Types</pluralLabel>
    <nameField>
        <label>Document Type Name</label>
        <type>Text</type>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ReadWrite</sharingModel>
</CustomObject>
```

**Fields:**

| Field API Name                | Type                 | Details                                                                               |
| ----------------------------- | -------------------- | ------------------------------------------------------------------------------------- |
| Name                          | Standard Text        | Label: Document Type Name                                                             |
| Category__c                   | Picklist             | Values: Legal & Entity, Compliance & Regulatory, Authorized Traders, Financial, Other |
| Description__c                | LongTextArea (32768) | Internal description of what this document type is                                    |
| Instructions_for_Submitter__c | LongTextArea (32768) | Shown to the submitting firm. Plain language instructions.                            |
| Is_Required__c                | Checkbox             | Default: true. Whether this document is always required.                              |
| Sort_Order__c                 | Number (3, 0)        | Controls display order within a category.                                             |
| Allowed_File_Types__c         | Text (255)           | Comma-separated extensions, e.g. `pdf,docx,jpg`.                                      |
| Expiration_Required__c        | Checkbox             | Default: false. Whether submitted documents require an expiration date.               |

**Sample field metadata file — `Category__c`:**

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Category__c</fullName>
    <label>Category</label>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Legal &amp; Entity</fullName><default
        >false</default></value>
            <value><fullName>Compliance &amp; Regulatory</fullName><default
        >false</default></value>
            <value><fullName>Authorized Traders</fullName><default
        >false</default></value>
            <value><fullName>Financial</fullName><default
        >false</default></value>
            <value><fullName>Other</fullName><default>false</default></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

---

### 5.2 `Onboarding_Document_Checklist__c`

**Purpose:** A section/grouping header. One record per category per Case. Provides a rolled-up view of how complete each category is, without requiring a formula or report.

**Object metadata file:** `force-app/main/default/objects/Onboarding_Document_Checklist__c/Onboarding_Document_Checklist__c.object-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Onboarding Document Checklist</label>
    <pluralLabel>Onboarding Document Checklists</pluralLabel>
    <nameField>
        <label>Checklist Name</label>
        <type>Text</type>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ControlledByParent</sharingModel>
</CustomObject>
```

**Fields:**

| Field API Name    | Type                 | Details                                                       |
| ----------------- | -------------------- | ------------------------------------------------------------- |
| Name              | Standard Text        | Label: Checklist Name                                         |
| Case__c           | Lookup → Case        | Required: true. DeleteConstraint: Restrict.                   |
| Account__c        | Lookup → Account     | Not required. Denormalized from Case for reporting.           |
| Category__c       | Picklist             | Same values as `Onboarding_Document_Type__c.Category__c`      |
| Status__c         | Picklist             | Values: Not Started (default), In Progress, Complete, Blocked |
| Assigned_Team__c  | Text (255)           | Which internal team owns this checklist section.              |
| Items_Total__c    | Number (3, 0)        | Populated by Flow — do not edit manually.                     |
| Items_Approved__c | Number (3, 0)        | Populated by Flow — do not edit manually.                     |
| Notes__c          | LongTextArea (32768) | Internal notes for this checklist section.                    |

**`Case__c` field metadata:**

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Case__c</fullName>
    <label>Case</label>
    <type>Lookup</type>
    <referenceTo>Case</referenceTo>
    <relationshipName>Onboarding_Document_Checklists</relationshipName>
    <deleteConstraint>Restrict</deleteConstraint>
    <required>true</required>
</CustomField>
```

**Why `deleteConstraint: Restrict` instead of `SetNull` or `Cascade`?** See [Section 14](#14-key-design-decisions-and-why).

---

### 5.3 `Onboarding_Document_Checklist_Item__c`

**Purpose:** The atomic unit. One record per document requirement per Case. Tracks the full lifecycle from "not started" through submission, review, approval or rejection.

**Object metadata file:** `force-app/main/default/objects/Onboarding_Document_Checklist_Item__c/Onboarding_Document_Checklist_Item__c.object-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Onboarding Document Checklist Item</label>
    <pluralLabel>Onboarding Document Checklist Items</pluralLabel>
    <nameField>
        <label>Item Name</label>
        <type>Text</type>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ControlledByParent</sharingModel>
</CustomObject>
```

**Fields:**

| Field API Name                   | Type                                      | Details                                                                            |
| -------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------- |
| Name                             | Standard Text                             | Label: Item Name                                                                   |
| Case__c                          | Lookup → Case                             | Required: true. DeleteConstraint: Restrict.                                        |
| Account__c                       | Lookup → Account                          | Not required. Denormalized from Case for reporting.                                |
| Onboarding_Document_Checklist__c | Lookup → Onboarding_Document_Checklist__c | Not required (allows orphan items). DeleteConstraint: SetNull.                     |
| Document_Type__c                 | Lookup → Onboarding_Document_Type__c      | Not required. Links item to template.                                              |
| Status__c                        | Picklist                                  | Values: Not Started (default), Pending Review, Approved, Rejected, Expired, Waived |
| Is_Required__c                   | Checkbox                                  | Default: true. Can be unchecked to waive an item without changing status.          |
| Due_Date__c                      | Date                                      | When this document must be submitted.                                              |
| Submitted_Date__c                | DateTime                                  | Set automatically by Apex trigger when a file is uploaded.                         |
| Reviewed_Date__c                 | DateTime                                  | Set manually by reviewer when they approve or reject.                              |
| Reviewer__c                      | Lookup → User                             | Which internal user reviewed this item.                                            |
| Rejection_Reason__c              | LongTextArea (32768)                      | Shown to client on Experience Cloud if status = Rejected.                          |
| Expiration_Date__c               | Date                                      | When the submitted document expires.                                               |
| Notes__c                         | LongTextArea (32768)                      | Internal notes. Not shown to submitter.                                            |
| Content_Document_Id__c           | Text (18)                                 | Stores the Salesforce ID of the uploaded ContentDocument. Set by Apex trigger.     |

**`Status__c` field metadata (full picklist):**

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Status__c</fullName>
    <label>Status</label>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>Not Started</fullName><default
        >true</default></value>
            <value><fullName>Pending Review</fullName><default
        >false</default></value>
            <value><fullName>Approved</fullName><default>false</default></value>
            <value><fullName>Rejected</fullName><default>false</default></value>
            <value><fullName>Expired</fullName><default>false</default></value>
            <value><fullName>Waived</fullName><default>false</default></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

---

## 6. Case Record Type

A dedicated `Onboarding` record type on Case separates onboarding cases from support cases, controls the page layout assignment, and scopes picklist values.

**File:** `force-app/main/default/objects/Case/recordTypes/Onboarding.recordType-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<RecordType xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Onboarding</fullName>
    <active>true</active>
    <businessProcess>Standard Support Process</businessProcess>
    <description>Firm onboarding cases for MarketAxess</description>
    <label>Onboarding</label>
    <picklistValues>
        <picklist>CaseOrigin</picklist>
        <values>
            <fullName>Email</fullName>
            <default>false</default>
        </values>
        <values>
            <fullName>Phone</fullName>
            <default>false</default>
        </values>
        <values>
            <fullName>Website</fullName>
            <default>true</default>
        </values>
    </picklistValues>
    <picklistValues>
        <picklist>Priority</picklist>
        <values>
            <fullName>High</fullName>
            <default>false</default>
        </values>
        <values>
            <fullName>Medium</fullName>
            <default>true</default>
        </values>
        <values>
            <fullName>Low</fullName>
            <default>false</default>
        </values>
    </picklistValues>
    <picklistValues>
        <picklist>Type</picklist>
        <values>
            <fullName>Account Support</fullName>
            <default>true</default>
        </values>
    </picklistValues>
</RecordType>
```

**Important:** `businessProcess` must reference an existing Case business process in the org. `Standard Support Process` exists in all standard orgs. If the org has a different process name, retrieve the existing processes first:

```bash
sf project retrieve start \
  --metadata "BusinessProcess" \
  --target-org marketaxess-demo
```

---

## 7. Permission Set

### Why a permission set is required (not optional)

When you deploy custom fields via the metadata API or SFDX, Salesforce creates the fields in the metadata store but does **not** grant Field-Level Security (FLS) to any profile. The fields exist but are invisible at runtime — forms show blank, queries return null, validation rules referencing them may behave unexpectedly.

The fix is to deploy a Permission Set that explicitly grants read and edit access on every custom field, then assign it to the relevant users. Do not rely on modifying profiles directly — permission sets are additive, portable, and do not require packaging all existing profile permissions.

### What the permission set must include

- Object-level CRUD on all three custom objects
- Field-level read + edit on all custom fields on all three objects
- `recordTypeVisibilities` for `Case.Onboarding` (so assigned users can create Onboarding cases)
- Do **not** include required Lookup fields (like `Case__c`) in `fieldPermissions` — Salesforce rejects them in permission set metadata with an error. Required lookup fields are automatically accessible.

**File:** `force-app/main/default/permissionsets/Onboarding_Admin.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Onboarding Admin</label>
    <hasActivationRequired>false</hasActivationRequired>

    <!-- Object permissions -->
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>true</modifyAllRecords>
        <object>Onboarding_Document_Type__c</object>
        <viewAllRecords>true</viewAllRecords>
    </objectPermissions>
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>true</modifyAllRecords>
        <object>Onboarding_Document_Checklist__c</object>
        <viewAllRecords>true</viewAllRecords>
    </objectPermissions>
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>true</modifyAllRecords>
        <object>Onboarding_Document_Checklist_Item__c</object>
        <viewAllRecords>true</viewAllRecords>
    </objectPermissions>

    <!-- Record type visibility -->
    <recordTypeVisibilities>
        <recordType>Case.Onboarding</recordType>
        <default>false</default>
        <visible>true</visible>
    </recordTypeVisibilities>

    <!-- Field permissions — Onboarding_Document_Type__c -->
    <!-- Omit Case__c and other required lookups — they are not valid here -->
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Category__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Description__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Instructions_for_Submitter__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Is_Required__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Sort_Order__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Allowed_File_Types__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Type__c.Expiration_Required__c</field>
        <readable>true</readable>
    </fieldPermissions>

    <!-- Field permissions — Onboarding_Document_Checklist__c -->
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Account__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Category__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Assigned_Team__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Items_Total__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Items_Approved__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist__c.Notes__c</field>
        <readable>true</readable>
    </fieldPermissions>

    <!-- Field permissions — Onboarding_Document_Checklist_Item__c -->
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Account__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field
    >Onboarding_Document_Checklist_Item__c.Onboarding_Document_Checklist__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Document_Type__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Is_Required__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Due_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Submitted_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Reviewed_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Reviewer__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Rejection_Reason__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Expiration_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Onboarding_Document_Checklist_Item__c.Notes__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field
    >Onboarding_Document_Checklist_Item__c.Content_Document_Id__c</field>
        <readable>true</readable>
    </fieldPermissions>
</PermissionSet>
```

---

## 8. Page Layouts

### 8.1 Case-Onboarding layout

**File:** `force-app/main/default/layouts/Case-Onboarding.layout-meta.xml`

This layout is assigned to the Onboarding record type for the System Administrator profile (and any other profiles via the Page Layout Assignment manual step in Section 12).

Sections and fields:

| Section            | Left Column                                    | Right Column                  |
| ------------------ | ---------------------------------------------- | ----------------------------- |
| Description        | Subject (full width), Description (full width) | —                             |
| Case Information   | CaseNumber, Status, Origin, Priority, Type     | OwnerId, AccountId, ContactId |
| System Information | RecordTypeId, CreatedById, SuppliedEmail       | ClosedDate                    |

Related lists:

- Onboarding Document Checklists (`Onboarding_Document_Checklists__r`)
- Files
- Emails
- Case History

**Note:** The Onboarding Document Checklists related list must be added manually after deployment. See [Section 12](#12-manual-post-deployment-steps).

---

### 8.2 Onboarding Document Checklist layout

**File:** `force-app/main/default/layouts/Onboarding_Document_Checklist__c-Onboarding Document Checklist Layout.layout-meta.xml`

Sections and fields:

| Section               | Left Column                            | Right Column                                                   |
| --------------------- | -------------------------------------- | -------------------------------------------------------------- |
| Checklist Information | Name, Case__c, Account__c, Category__c | Status__c, Assigned_Team__c, Items_Total__c, Items_Approved__c |
| Notes                 | Notes__c (full width)                  | —                                                              |
| System Information    | CreatedById, CreatedDate               | LastModifiedById, LastModifiedDate                             |

Related lists:

- Onboarding Document Checklist Items
- Field History

**Note:** The Onboarding Document Checklist Items related list must be added manually. See [Section 12](#12-manual-post-deployment-steps).

---

### 8.3 Onboarding Document Checklist Item layout

**File:** `force-app/main/default/layouts/Onboarding_Document_Checklist_Item__c-Onboarding Document Checklist Item Layout.layout-meta.xml`

Sections and fields:

| Section              | Left Column                                                    | Right Column                                                              |
| -------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Document Information | Name, Document_Type__c, Status__c, Due_Date__c, Is_Required__c | Case__c, Account__c, Onboarding_Document_Checklist__c, Expiration_Date__c |
| Submission           | Content_Document_Id__c, Submitted_Date__c (full width)         | —                                                                         |
| Rejection Details    | Rejection_Reason__c (full width)                               | —                                                                         |
| Internal Review      | Reviewer__c, Reviewed_Date__c                                  | Notes__c                                                                  |
| System Information   | CreatedById, CreatedDate                                       | LastModifiedById, LastModifiedDate                                        |

Related lists:

- Files
- Field History

---

## 9. Flows

Both flows are Record-Triggered Flows that maintain the rollup counts on `Onboarding_Document_Checklist__c`. These counts exist because Salesforce does not support rollup summary fields on lookup relationships (only master-detail). The flows replicate that behavior.

### 9.1 `Onboarding_Checklist_Rollup_On_Item_Save`

**Trigger object:** `Onboarding_Document_Checklist_Item__c`
**Trigger type:** Record-Triggered Flow (After Save — fires on Create and Update)
**Entry condition:** `Onboarding_Document_Checklist__c IS NOT NULL`
**Run as:** System Context Without Sharing

**Logic:**

1. Get all `Onboarding_Document_Checklist_Item__c` records where `Onboarding_Document_Checklist__c = {triggering record's Onboarding_Document_Checklist__c}` (all siblings including the triggering record).
2. Count total records → assign to variable `varTotal`.
3. Filter the collection to records where `Status__c = 'Approved'` → count → assign to variable `varApproved`.
4. Update the parent `Onboarding_Document_Checklist__c` record: set `Items_Total__c = varTotal` and `Items_Approved__c = varApproved`.

**File:** `force-app/main/default/flows/Onboarding_Checklist_Rollup_On_Item_Save.flow-meta.xml`

---

### 9.2 `Onboarding_Checklist_Rollup_On_Item_Delete`

**Trigger object:** `Onboarding_Document_Checklist_Item__c`
**Trigger type:** Record-Triggered Flow (Before Delete)
**Entry condition:** `Onboarding_Document_Checklist__c IS NOT NULL`
**Run as:** System Context Without Sharing

**Logic:** Identical to the Save flow except:

- Fires Before Delete (the only supported timing for delete triggers in Flow).
- The query for siblings must **exclude** the record being deleted. Filter: `Id != {$Record.Id}` in addition to the checklist ID match.

This prevents the count from including the deleted record, which would leave the rollup one count too high.

**File:** `force-app/main/default/flows/Onboarding_Checklist_Rollup_On_Item_Delete.flow-meta.xml`

---

## 10. Apex Trigger and Handler

### Why Apex instead of Flow here

`ContentDocumentLink` is the junction object Salesforce creates when a file is attached to a record. It cannot be used as a trigger object in Record-Triggered Flows — Salesforce disallows it. An after-insert Apex trigger on `ContentDocumentLink` is the correct approach.

### What the trigger and handler must do

**Trigger file:** `force-app/main/default/triggers/OnboardingContentDocumentLinkTrigger.trigger`

The trigger fires `after insert` on `ContentDocumentLink`. It delegates all logic to the handler class.

```apex
trigger OnboardingContentDocumentLinkTrigger on ContentDocumentLink(
  after insert
) {
  OnboardingContentDocumentLinkHandler.handleAfterInsert(Trigger.new);
}
```

---

**Handler file:** `force-app/main/default/classes/OnboardingContentDocumentLinkHandler.cls`

Write the handler so that it:

1. Collects all `LinkedEntityId` values from the trigger set.
2. Queries `Onboarding_Document_Checklist_Item__c` where `Id IN :linkedEntityIds` to find which linked entities are checklist items.
3. For each `ContentDocumentLink` where `LinkedEntityId` matches a checklist item:
   - Set `Content_Document_Id__c` = the `ContentDocumentId` from the link record.
   - Set `Status__c` = `'Pending Review'`.
   - Set `Submitted_Date__c` = `System.now()`.
4. Collect all items to update into a list and perform a single `update` DML call (bulk-safe — never DML inside a loop).
5. No try/catch needed for the basic case, but add one if the org has strict error handling requirements.

The handler must be a `public class` with a `public static void handleAfterInsert(List<ContentDocumentLink> newLinks)` method signature so it can be called from the trigger.

Write a companion test class `OnboardingContentDocumentLinkHandlerTest` that:

- Creates an Account, a Contact, a Case (Onboarding record type), a Checklist, and a Checklist Item.
- Inserts a `ContentVersion` to simulate a file upload (Salesforce auto-creates the `ContentDocumentLink`).
- Asserts that the Item's `Status__c` is `'Pending Review'` and `Submitted_Date__c` is not null after insert.
- Achieves at least 75% code coverage (aim for 100%).

---

## 11. Deployment Order and CLI Commands

Deploy in this order to avoid dependency failures. Custom objects must exist before permission sets and layouts that reference their fields. Flows must be deployed before they can activate. Apex compiles against the live schema.

### Step 1 — Deploy custom objects and fields

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Onboarding_Document_Type__c \
  --source-dir force-app/main/default/objects/Onboarding_Document_Checklist__c \
  --source-dir force-app/main/default/objects/Onboarding_Document_Checklist_Item__c \
  --target-org marketaxess-demo
```

### Step 2 — Deploy the Case record type

If you retrieved existing Case metadata in Section 3, merge the new record type file into your existing Case object folder, then deploy the entire Case object:

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Case \
  --target-org marketaxess-demo
```

### Step 3 — Deploy the permission set

```bash
sf project deploy start \
  --source-dir force-app/main/default/permissionsets/Onboarding_Admin.permissionset-meta.xml \
  --target-org marketaxess-demo
```

### Step 4 — Deploy page layouts

```bash
sf project deploy start \
  --source-dir force-app/main/default/layouts \
  --target-org marketaxess-demo
```

If the deploy fails with an error about related lists on a new object, remove the related list entries from the layout XML and redeploy. Add them manually afterward (see Section 12).

### Step 5 — Deploy flows

```bash
sf project deploy start \
  --source-dir force-app/main/default/flows \
  --target-org marketaxess-demo
```

### Step 6 — Deploy Apex trigger and classes

```bash
sf project deploy start \
  --source-dir force-app/main/default/triggers/OnboardingContentDocumentLinkTrigger.trigger \
  --source-dir force-app/main/default/classes/OnboardingContentDocumentLinkHandler.cls \
  --source-dir force-app/main/default/classes/OnboardingContentDocumentLinkHandlerTest.cls \
  --target-org marketaxess-demo
```

Verify Apex tests pass:

```bash
sf apex run test \
  --class-names OnboardingContentDocumentLinkHandlerTest \
  --result-format human \
  --target-org marketaxess-demo
```

### Deploy everything at once (if the org is fresh and there are no Case conflicts)

```bash
sf project deploy start \
  --source-dir force-app/main/default \
  --target-org marketaxess-demo
```

Check deployment status:

```bash
sf project deploy report --target-org marketaxess-demo
```

---

## 12. Manual Post-Deployment Steps

The following steps cannot be done via metadata and must be performed by a user in the org UI (or via CLI where noted). Do not skip them — the feature will not work correctly without them.

---

### Step 1 — Assign the permission set to the user

**In the UI:**

1. Go to Setup > Users > [your user].
2. Scroll to the Permission Set Assignments related list.
3. Click Edit Assignments.
4. Move `Onboarding Admin` to the Enabled list and save.

**Via CLI** (faster for automation):

```bash
# First, get the permission set ID
sf data query \
  --query "SELECT Id FROM PermissionSet WHERE Name = 'Onboarding_Admin'" \
  --target-org marketaxess-demo

# Then get the user ID
sf data query \
  --query "SELECT Id FROM User WHERE Username = 'your.user@example.com'" \
  --target-org marketaxess-demo

# Assign it
sf data create record \
  --sobject PermissionSetAssignment \
  --values "PermissionSetId='[PS_ID]' AssigneeId='[USER_ID]'" \
  --target-org marketaxess-demo
```

---

### Step 2 — Assign the Case-Onboarding page layout to the Onboarding record type

1. Go to Setup > Object Manager > Case > Page Layouts > Page Layout Assignment.
2. Click Edit Assignment.
3. Find the row for the Onboarding record type.
4. Set it to `Case-Onboarding` for the System Administrator profile (and any other profiles that need it).
5. Save.

This step cannot be done via metadata without modifying profile files, which risks overwriting other profile settings. Do it manually.

---

### Step 3 — Add related lists to layouts manually

Salesforce rejects related list entries in metadata for newly created objects during the same deploy because the relationship is not yet resolved when the layout metadata is processed. After deploying the objects and layouts, add the related lists through the UI:

**On the Case-Onboarding layout:**

1. Setup > Object Manager > Case > Page Layouts > Case-Onboarding.
2. Click Edit.
3. From the Related Lists palette, drag `Onboarding Document Checklists` onto the layout.
4. Save.

**On the Onboarding Document Checklist layout:**

1. Setup > Object Manager > Onboarding Document Checklist > Page Layouts > Onboarding Document Checklist Layout.
2. Click Edit.
3. From the Related Lists palette, drag `Onboarding Document Checklist Items` onto the layout.
4. Save.

---

### Step 4 — Activate flows

If flows are deployed in inactive state (common on first deploy):

1. Go to Setup > Flows.
2. Find `Onboarding_Checklist_Rollup_On_Item_Save` and click Activate.
3. Find `Onboarding_Checklist_Rollup_On_Item_Delete` and click Activate.

To activate via CLI:

```bash
sf data update record \
  --sobject FlowDefinition \
  --where "DeveloperName='Onboarding_Checklist_Rollup_On_Item_Save'" \
  --values "ActiveVersion=1" \
  --target-org marketaxess-demo
```

Note: The above CLI command works for simple cases. If it fails, activate through the UI.

---

## 13. Sample Data (Optional)

Load this data if you want the org ready for a demo or UAT. All records assume an Account named `Omega, Inc.` exists. Create it first if it does not.

### Create the Account (if needed)

```bash
sf data create record \
  --sobject Account \
  --values "Name='Omega, Inc.'" \
  --target-org marketaxess-demo
```

### Document Type records (10 records across 4 categories)

| Document Type Name           | Category                | Is Required | Expiration Required |
| ---------------------------- | ----------------------- | ----------- | ------------------- |
| Certificate of Incorporation | Legal & Entity          | true        | false               |
| Articles of Organization     | Legal & Entity          | true        | false               |
| Proof of Business Address    | Legal & Entity          | false       | false               |
| KYC/AML Package              | Compliance & Regulatory | true        | true                |
| Beneficial Ownership Form    | Compliance & Regulatory | true        | false               |
| ISDA Master Agreement        | Compliance & Regulatory | true        | true                |
| Government-Issued ID         | Authorized Traders      | true        | true                |
| Trader Authorization Form    | Authorized Traders      | true        | false               |
| Credit Application           | Financial               | true        | false               |
| Financial Statements         | Financial               | true        | false               |

Create these via CLI:

```bash
sf data create record --sobject Onboarding_Document_Type__c \
  --values "Name='Certificate of Incorporation' Category__c='Legal & Entity' Is_Required__c=true Expiration_Required__c=false" \
  --target-org marketaxess-demo
```

Repeat for each record, adjusting the values.

---

### Sample Case

```bash
# Get the Account Id first
sf data query \
  --query "SELECT Id FROM Account WHERE Name = 'Omega, Inc.'" \
  --target-org marketaxess-demo

# Get the Onboarding Record Type Id
sf data query \
  --query "SELECT Id FROM RecordType WHERE SObjectType='Case' AND DeveloperName='Onboarding'" \
  --target-org marketaxess-demo

# Create the Case
sf data create record --sobject Case \
  --values "Subject='Omega, Inc. - Firm Onboarding' AccountId='[ACCOUNT_ID]' RecordTypeId='[RT_ID]' Status='New' Origin='Website'" \
  --target-org marketaxess-demo
```

---

### Checklist sections (4 records, one per category)

Create one `Onboarding_Document_Checklist__c` per category:

- Legal & Entity → Status: In Progress
- Compliance & Regulatory → Status: In Progress
- Authorized Traders → Status: Not Started
- Financial → Status: Complete

```bash
sf data create record --sobject Onboarding_Document_Checklist__c \
  --values "Name='Legal & Entity' Case__c='[CASE_ID]' Account__c='[ACCOUNT_ID]' Category__c='Legal & Entity' Status__c='In Progress'" \
  --target-org marketaxess-demo
```

---

### Checklist Items (10 records with realistic status variation)

| Item Name                    | Category Checklist      | Status         | Notes                                                                                                         |
| ---------------------------- | ----------------------- | -------------- | ------------------------------------------------------------------------------------------------------------- |
| Certificate of Incorporation | Legal & Entity          | Approved       | —                                                                                                             |
| Articles of Organization     | Legal & Entity          | Approved       | —                                                                                                             |
| Proof of Business Address    | Legal & Entity          | Rejected       | Set Rejection_Reason__c: "Document is expired. Please resubmit a utility bill dated within the last 90 days." |
| KYC/AML Package              | Compliance & Regulatory | Pending Review | —                                                                                                             |
| Beneficial Ownership Form    | Compliance & Regulatory | Pending Review | —                                                                                                             |
| ISDA Master Agreement        | Compliance & Regulatory | Not Started    | —                                                                                                             |
| Government-Issued ID         | Authorized Traders      | Not Started    | —                                                                                                             |
| Trader Authorization Form    | Authorized Traders      | Not Started    | —                                                                                                             |
| Credit Application           | Financial               | Approved       | —                                                                                                             |
| Financial Statements         | Financial               | Approved       | —                                                                                                             |

Set the `Document_Type__c` lookup on each item to the corresponding document type record you created above.

---

## 14. Key Design Decisions and Why

### `deleteConstraint: Restrict` on required lookups

Both `Onboarding_Document_Checklist__c.Case__c` and `Onboarding_Document_Checklist_Item__c.Case__c` use `deleteConstraint: Restrict`. This means Salesforce will block a Case deletion if any Checklist or Item records are still linked to it.

The alternatives are `SetNull` (would blank out a required field, causing a validation error anyway) and `Cascade` (would silently delete all document records when a Case is deleted — dangerous for compliance data). `Restrict` is the safe choice: if someone tries to delete a Case with document records, they get a clear error rather than silent data loss.

### FLS is not automatic on metadata API deploys

Salesforce's metadata API creates fields but does not touch Field-Level Security. This is by design — Salesforce does not want a package deploy to automatically expose sensitive fields to all profiles. The result is fields that exist in the schema but are invisible in the UI and return null in queries for users without FLS access. The permission set in Section 7 is the correct fix. Always deploy and assign it before testing.

### ContentDocumentLink cannot be a Flow trigger object

Salesforce explicitly excludes `ContentDocumentLink` from the list of supported trigger objects in Record-Triggered Flows. This is a platform limitation, not a configuration gap. The only way to react to file uploads on a specific record type is via an Apex trigger on `ContentDocumentLink` that checks whether the `LinkedEntityId` is the object you care about.

### Related lists cannot be added to layouts via metadata for newly created objects in the same deploy

When Salesforce processes a page layout during deployment, it validates that the related list references an existing relationship. If the relationship is defined in a custom object that was just created in the same deploy package, the validation can fail because the order of processing is not guaranteed. The safe approach is to omit the related list from the deployed layout and add it manually through the UI after deployment. This is a known Salesforce metadata API limitation.

### Flows instead of roll-up summary fields for checklist counts

`Onboarding_Document_Checklist__c` uses a Lookup relationship (not Master-Detail) to Case, and `Onboarding_Document_Checklist_Item__c` uses a Lookup to the Checklist. Salesforce only supports Roll-Up Summary fields on Master-Detail relationships, not Lookups. The two flows replicate this behavior using a get-records-and-count pattern. The trade-off is eventual consistency on the parent's counts during high-volume operations, but for an onboarding workflow this is acceptable.

### Separate trigger for save vs. delete

A single flow cannot handle both save and delete correctly because the after-save context includes the record being saved (correct for creates and updates) while the before-delete context includes the record being deleted (it should be excluded from the sibling count). Two flows with different filtering logic are cleaner and easier to debug than one flow with branching on `$Record__Prior` vs. `$Record`.

---

## 15. Validation Checklist

Use this checklist to confirm the setup is complete before handing off to the business.

### Metadata deployment

- [ ] All three custom objects deploy without errors
- [ ] Case record type `Onboarding` is active and visible in Setup
- [ ] Permission set `Onboarding_Admin` deployed successfully
- [ ] Both flows deployed and activated
- [ ] Apex trigger and handler deployed; test class achieves 100% coverage
- [ ] Page layouts deployed for all three objects and for Case

### Manual configuration

- [ ] `Onboarding Admin` permission set assigned to at least one user
- [ ] `Case-Onboarding` layout assigned to Onboarding record type for System Administrator
- [ ] `Onboarding Document Checklists` related list added to Case-Onboarding layout
- [ ] `Onboarding Document Checklist Items` related list added to Onboarding Document Checklist layout

### Functional smoke test

- [ ] Create a Case with record type `Onboarding` — confirms record type and layout work
- [ ] Create an `Onboarding_Document_Checklist__c` linked to that Case — confirms lookup FLS
- [ ] Create an `Onboarding_Document_Checklist_Item__c` linked to the Checklist — confirms the Items related list appears
- [ ] Verify `Items_Total__c` on the Checklist increments to 1 — confirms Save flow is active
- [ ] Upload a file to the Item record — confirms Apex trigger fires and sets Status to `Pending Review` and populates `Submitted_Date__c`
- [ ] Delete the Item — verify `Items_Total__c` on the Checklist drops to 0 — confirms Delete flow is active
- [ ] Attempt to delete the Case while Checklist records exist — confirm Salesforce blocks the deletion with a Restrict error
