# MADocumentChecklist2 FlexCard + Agentforce Button

A Salesforce Financial Services Cloud OmniStudio FlexCard that displays DocumentChecklistItem records on a Case record page, with a custom LWC button that launches the Market Axess Onboarding Agent via the Agentforce Conversation Client API.

---

## What's Included

| Component | Type | Purpose |
|---|---|---|
| `MADocumentChecklist2` | OmniStudio FlexCard | Renders document checklist rows with status, upload, open, and analyze actions |
| `analyzeDocumentOnboarding` | Lightning Web Component | Button that opens the Agentforce panel and triggers document analysis |

---

## Prerequisites

- Salesforce org with **Financial Services Cloud** and **OmniStudio** enabled
- **Agentforce** enabled with the **Market Axess Onboarding Agent** configured
- **Salesforce CLI** (`sf`) v2.x installed and authenticated
- API Version 66.0+
- `DocumentChecklistItem` records with a `ParentRecordId` pointing to a Case

---

## Step 1 — Clone the Repo

```bash
git clone https://github.com/<your-username>/ma-flexcard-agentforce.git
cd ma-flexcard-agentforce

# Authenticate your org
sf org login web --alias my-org

# Confirm authentication
sf org display --target-org my-org
```

---

## Step 2 — Deploy the LWC

```bash
sf project deploy start \
  --source-dir force-app/main/default/lwc/analyzeDocumentOnboarding \
  --target-org my-org
```

> **Important:** After deploying, update the `BOT_ID` constant in `analyzeDocumentOnboarding.js` with your org's Market Axess Onboarding Agent Bot ID. Find it by navigating to **Setup → Agents**, opening the agent in Agent Builder, and copying the ID from the URL (`0Xx...`).

---

## Step 3 — Import the FlexCard

The FlexCard is distributed as a JSON configuration file (`flexcard/MADocumentChecklist2.json`) and must be imported via OmniStudio.

1. In Salesforce Setup, navigate to **OmniStudio → FlexCards**
2. Click **Import**
3. Upload `flexcard/MADocumentChecklist2.json`
4. After import, open the card and click **Activate**

---

## Step 4 — Add the LWC Button to the FlexCard

1. Open `MADocumentChecklist2` in the FlexCard designer
2. In the `ItemRow` block, add a **Custom LWC** element
3. Set **Custom LWC Name** to `analyzeDocumentOnboarding`
4. Add an attribute: `recordId` → `{Id}` (maps the DocumentChecklistItem ID from each row)
5. Save and re-activate the FlexCard

---

## Step 5 — Add the FlexCard to the Case Record Page

1. Open a Case record in Salesforce
2. Click the **Gear icon → Edit Page**
3. Find `MADocumentChecklist2` in the Custom components panel
4. Drag it onto the page layout
5. Click **Save → Activate**

---

## Configuration

### Updating the Bot ID

Open `force-app/main/default/lwc/analyzeDocumentOnboarding/analyzeDocumentOnboarding.js` and replace the `BOT_ID` value:

```javascript
const BOT_ID = '0Xxak000003JDz7CAG'; // ← replace with your org's Bot ID
```

---

## How It Works

1. The FlexCard queries `DocumentChecklistItem` records via a DataRaptor, keyed on `recordId` (the Case ID passed from the record page)
2. Each row renders the document name, type, required/status badges, Upload, Open, and Analyze Document actions
3. Clicking **Analyze Document** calls `open()` and `execute()` from `lightning/accApi`, opening the Agentforce panel and sending: `"Analyze this document for DocumentChecklistItem ID <recordId>"`
4. The Market Axess Onboarding Agent receives the message, extracts the ID, and invokes the configured document analysis flow

---

## Component Inventory

```
ma-flexcard-agentforce/
├── flexcard/
│   └── MADocumentChecklist2.json          ← FlexCard PropertySetConfig
├── force-app/main/default/lwc/
│   └── analyzeDocumentOnboarding/
│       ├── analyzeDocumentOnboarding.html
│       ├── analyzeDocumentOnboarding.js
│       └── analyzeDocumentOnboarding.js-meta.xml
└── sfdx-project.json
```

---

## Related

- [CAP Document Checklist LWC](https://github.com/rkirkwood-png/onboarding-doc-checklist-agentforce-capitalmarkets-lwc) — the custom LWC accordion component this FlexCard complements
- [Agentforce Conversation Client API docs](https://developer.salesforce.com/docs/platform/accsdk/guide/acc-api.html)
- [OmniStudio FlexCards documentation](https://help.salesforce.com/s/articleView?id=sf.os_flexcards.htm)
