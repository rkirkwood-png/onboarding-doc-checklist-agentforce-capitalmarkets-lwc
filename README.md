# Market Axess Onboarding Agent — FlexCard + Agentforce

A Salesforce Financial Services Cloud solution that combines an OmniStudio FlexCard, a custom LWC Agentforce button, an autolaunched Flow, an Einstein Prompt Template, and the Market Axess Onboarding Agent to deliver AI-powered document analysis from a Case record page.

---

## What's Included

| Component | Type | Purpose |
|---|---|---|
| `MADocumentChecklist2` | OmniStudio FlexCard | Renders DocumentChecklistItem rows with status, upload, open, and analyze actions |
| `analyzeDocumentOnboarding` | Lightning Web Component | Button that opens the Agentforce panel and triggers document analysis for a specific item |
| `Onboarding_Document_Checklist_Item_Info_Collection` | Flow (Autolaunched) | Agent action flow — collects document checklist item info and invokes the prompt template |
| `Onboarding_Document_Analysis` | Einstein Prompt Template | Analyzes submitted documents for risk and anomalies using Einstein Generative AI |
| `Market_Axess_Onboarding_Agent` | Bot + BotVersion | Agentforce agent definition — topics and actions must be configured manually in Agent Builder |

---

## Prerequisites

- Salesforce org with **Financial Services Cloud** and **OmniStudio** enabled
- **Agentforce** enabled with Einstein Generative AI and Prompt Templates
- **Salesforce CLI** (`sf`) v2.x — API Version 66.0+
- `DocumentChecklistItem` records linked to Case records via `ParentRecordId`

---

## Step 1 — Clone the Repo

```bash
git clone https://github.com/emma-murray_sfemu/ma-flexcard-agentforce.git
cd ma-flexcard-agentforce

# Authenticate your org
sf org login web --alias my-org

# Confirm authentication
sf org display --target-org my-org
```

---

## Step 2 — Deploy the Flow

```bash
sf project deploy start \
  --source-dir force-app/main/default/flows/Onboarding_Document_Checklist_Item_Info_Collection.flow-meta.xml \
  --target-org my-org
```

---

## Step 3 — Deploy the Prompt Template

```bash
sf project deploy start \
  --source-dir force-app/main/default/genAiPromptTemplates/Onboarding_Document_Analysis.genAiPromptTemplate-meta.xml \
  --target-org my-org
```

> **Note:** After deploying, navigate to **Setup → Prompt Builder**, open `Onboarding_Document_Analysis`, and verify it is **Active**. If not, toggle it active and save.

---

## Step 4 — Deploy the Agent

```bash
sf project deploy start \
  --source-dir force-app/main/default/bots/Market_Axess_Onboarding_Agent \
  --target-org my-org
```

> **Important:** This deploys the agent shell and conversation configuration. Topics and actions must be wired up manually in Agent Builder — see Step 5.

---

## Step 5 — Configure Agent Topics & Actions (Manual)

The `GenAiPlanner` metadata type (agent topics and actions) is not deployable via CLI in API 66.0. Complete these steps in Salesforce Setup.

**Navigate to:** Setup → Agents → Market Axess Onboarding Agent → Open in Agent Builder

### Create the Document Analysis Topic

| Field | Value |
|---|---|
| Topic Label | Document Analysis |
| Topic API Name | `Document_Analysis` |
| Description | Analyzes documents attached to DocumentChecklistItem records for risk, anomalies, and completeness issues |
| Scope | When a user asks to analyze a document or review a document checklist item |

### Add the Document Analysis Action

1. Inside the Document Analysis topic, click **New Action**
2. Set **Action Type** to **Flow**
3. Select **`Onboarding_Document_Checklist_Item_Info_Collection`**
4. Set **Action Label** to `Analyze Document Checklist Item`
5. Map the input: the flow expects a `DocumentChecklistItemId` — instruct the agent to extract it from the user message
6. Add instructions: *"When the user asks to analyze a document and provides a DocumentChecklistItem ID, invoke this action with that ID"*
7. Save and **Activate** the agent

---

## Step 6 — Deploy the LWC

```bash
sf project deploy start \
  --source-dir force-app/main/default/lwc/analyzeDocumentOnboarding \
  --target-org my-org
```

> **Update the Bot ID:** Open `force-app/main/default/lwc/analyzeDocumentOnboarding/analyzeDocumentOnboarding.js` and replace the `BOT_ID` constant with your org's Market Axess Onboarding Agent ID. Find it in **Setup → Agents → Agent Builder URL** (`0Xx...`).

```javascript
const BOT_ID = '0Xxak000003JDz7CAG'; // ← replace with your org's Bot ID
```

---

## Step 7 — Import the FlexCard

1. In Salesforce Setup, navigate to **OmniStudio → FlexCards → Import**
2. Upload `flexcard/MADocumentChecklist2.json`
3. After import, open the card and click **Activate**

---

## Step 8 — Wire the LWC Button into the FlexCard

1. Open `MADocumentChecklist2` in the FlexCard designer
2. In the `ItemRow` block, add a **Custom LWC** element
3. Set **Custom LWC Name** to `analyzeDocumentOnboarding`
4. Add attribute: `recordId` → `{Id}`
5. Save and re-activate the FlexCard

---

## Step 9 — Add the FlexCard to the Case Record Page

1. Open a Case record in Salesforce
2. Gear icon → **Edit Page**
3. Find `MADocumentChecklist2` in the Custom components panel
4. Drag it onto the layout
5. **Save → Activate**

---

## How It Works

1. The FlexCard queries `DocumentChecklistItem` records via DataRaptor, keyed on the Case `recordId`
2. Each row shows document name, type, required/status badges, Upload, Open, and Analyze Document button
3. Clicking **Analyze Document** calls `open()` and `execute()` from `lightning/accApi`, sending:
   `"Analyze this document for DocumentChecklistItem ID <recordId>"`
4. The Market Axess Onboarding Agent receives the message, routes it to the Document Analysis topic, and invokes `Onboarding_Document_Checklist_Item_Info_Collection`
5. The flow fetches the document, calls the `Onboarding_Document_Analysis` prompt template, and writes the AI output back to `Risk_Analysis__c` on the checklist item

---

## Component Inventory

```
ma-flexcard-agentforce/
├── flexcard/
│   └── MADocumentChecklist2.json
├── force-app/main/default/
│   ├── bots/Market_Axess_Onboarding_Agent/
│   │   ├── Market_Axess_Onboarding_Agent.bot-meta.xml
│   │   └── v2.botVersion-meta.xml
│   ├── flows/
│   │   └── Onboarding_Document_Checklist_Item_Info_Collection.flow-meta.xml
│   ├── genAiPromptTemplates/
│   │   └── Onboarding_Document_Analysis.genAiPromptTemplate-meta.xml
│   └── lwc/analyzeDocumentOnboarding/
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
