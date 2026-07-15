# Prompt Template Setup Guide — CAP Document Analysis

This guide walks you through creating the `CAP_Document_Analysis` Flex Prompt Template in any Salesforce org. The template is invoked by the `capDocumentChecklist` LWC to analyze uploaded onboarding documents using Einstein AI.

---

## Prerequisites

Before creating the template, confirm these are enabled in your org:

1. **Einstein Generative AI**
   - Setup → Einstein Setup → Enable Einstein
   - Requires Einstein Generative AI add-on or Einstein 1 Platform license

2. **Prompt Templates**
   - Setup → search "Prompt Template Settings" → Enable Prompt Templates

3. **Flex Credits**
   - Setup → Einstein Setup → Usage & Credits — confirm Flex Credits are available
   - Each "Analyze All" button click consumes one credit per submitted document

4. **API-enabled profile**
   - The running user profile must have "API Enabled" permission
   - Required for `ConnectApi.EinsteinLLM` Apex calls

---

## Step-by-Step: Create the Template

### 1. Open Prompt Template Builder

Setup → search "Prompt Templates" → click **New Prompt Template**

### 2. Set the template type and name

| Field                | Value                                                                                  |
| -------------------- | -------------------------------------------------------------------------------------- |
| Prompt Template Type | **Flex**                                                                               |
| Prompt Template Name | `CAP Document Analysis`                                                                |
| API Name             | `CAP_Document_Analysis` ← must match exactly                                           |
| Template Description | Analyzes onboarding documents for completeness and flags missing fields or signatures. |

### 3. Add inputs

Click **Add** to add each input. Check **Require when template runs** for all three.

**Input 1 — the document file:**

| Field       | Value      |
| ----------- | ---------- |
| Name        | `Document` |
| API Name    | `Document` |
| Source Type | Object     |
| Object      | File       |

**Input 2 — document type name:**

| Field       | Value                |
| ----------- | -------------------- |
| Name        | `Document Type Name` |
| API Name    | `Document_Type_Name` |
| Source Type | Free Text            |

**Input 3 — submission instructions:**

| Field       | Value                   |
| ----------- | ----------------------- |
| Name        | `Document Instructions` |
| API Name    | `Document_Instructions` |
| Source Type | Free Text               |

Click **Next**.

### 4. Enter the prompt body

In the prompt editor, type the static text first. When you need to insert an input, use the **Insert Resource** button (or type `@` and select the input from the dropdown).

Paste this exactly, inserting each `{!Input:...}` as a resource merge field:

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

For the `{!Input:Document}` merge field, when the dropdown appears, select **Record Snapshot** (not "Content Document ID"). Record Snapshot gives Einstein the full file content including OCR output for scanned images.

### 5. Activate the template

Toggle **Active** to on (blue) at the bottom of the page, then click **Save**.

---

## Verifying the Template Works

To test before deploying the LWC, run this in Anonymous Apex (replacing the IDs):

```apex
// Replace with a real ContentDocumentId from your org
String docId = '069XXXXXXXXXXXX';

Map<String, ConnectApi.WrappedValue> inputs = new Map<String, ConnectApi.WrappedValue>();
ConnectApi.WrappedValue docVal = new ConnectApi.WrappedValue();
docVal.value = docId;
inputs.put('Document', docVal);

ConnectApi.WrappedValue typeVal = new ConnectApi.WrappedValue();
typeVal.value = 'KYC Customer Identification Form';
inputs.put('Document_Type_Name', typeVal);

ConnectApi.WrappedValue instrVal = new ConnectApi.WrappedValue();
instrVal.value = 'Complete all sections including beneficial ownership.';
inputs.put('Document_Instructions', instrVal);

ConnectApi.EinsteinPromptTemplateGenerationsInput input =
    new ConnectApi.EinsteinPromptTemplateGenerationsInput();
input.isPreview = false;
input.inputParams = inputs;
input.additionalConfig = new ConnectApi.EinsteinLLMAdditionalConfigInput();
input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocations';

ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
    ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('CAP_Document_Analysis', input);

System.debug(response.generations[0].text);
```

A successful response will contain `SUMMARY:`, `ISSUES:`, and `STATUS:` sections.

---

## Troubleshooting

| Error                           | Likely Cause                         | Fix                                                           |
| ------------------------------- | ------------------------------------ | ------------------------------------------------------------- |
| `Einstein is not enabled`       | Einstein Generative AI not turned on | Setup → Einstein Setup → Enable                               |
| `PromptTemplate not found`      | API name typo                        | Verify API name is exactly `CAP_Document_Analysis`            |
| `Insufficient Flex Credits`     | Credits exhausted                    | Setup → Einstein Setup → Usage & Credits                      |
| `INVALID_TYPE` on ConnectApi    | API version too low                  | Ensure `apiVersion` is 59.0 or higher in Apex class meta      |
| Template returns garbled output | Scanned image with poor OCR          | Expected behavior — model will note low legibility in SUMMARY |
