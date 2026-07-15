// ─────────────────────────────────────────────────────────────────────────────
// backfillContentDocumentIds.apex
//
// One-time fix for items that had files uploaded before the
// OnboardingContentDocumentLinkTrigger was deployed.
//
// Run via: sf apex run --file scripts/apex/backfillContentDocumentIds.apex --target-org <alias>
// ─────────────────────────────────────────────────────────────────────────────

// Get all items that are missing Content_Document_Id__c
Set<Id> itemIdsNeedingFix = new Map<Id, Onboarding_Document_Checklist_Item__c>(
    [SELECT Id FROM Onboarding_Document_Checklist_Item__c WHERE Content_Document_Id__c = null]
).keySet();

if (itemIdsNeedingFix.isEmpty()) {
    System.debug('✅ All items already have Content_Document_Id__c populated. Nothing to fix.');
    return;
}

System.debug('Found ' + itemIdsNeedingFix.size() + ' items with no Content_Document_Id__c. Checking for linked files...');

// Find ContentDocumentLinks for those items — take the most recent file per item
List<ContentDocumentLink> links = [
    SELECT ContentDocumentId, LinkedEntityId, SystemModstamp
    FROM ContentDocumentLink
    WHERE LinkedEntityId IN :itemIdsNeedingFix
    ORDER BY SystemModstamp DESC
];

// Map: item ID → most recent ContentDocument ID (first wins because we sorted DESC)
Map<Id, String> itemToDocId = new Map<Id, String>();
for (ContentDocumentLink cdl : links) {
    if (!itemToDocId.containsKey(cdl.LinkedEntityId)) {
        itemToDocId.put(cdl.LinkedEntityId, String.valueOf(cdl.ContentDocumentId));
    }
}

if (itemToDocId.isEmpty()) {
    System.debug('ℹ️  No ContentDocumentLinks found for any of the items. Files may not have been uploaded yet.');
    return;
}

List<Onboarding_Document_Checklist_Item__c> toUpdate = new List<Onboarding_Document_Checklist_Item__c>();
for (Id itemId : itemToDocId.keySet()) {
    toUpdate.add(new Onboarding_Document_Checklist_Item__c(
        Id = itemId,
        Content_Document_Id__c = itemToDocId.get(itemId),
        Submitted_Date__c = System.now(),
        Status__c = 'Pending Review'
    ));
}

update toUpdate;
System.debug('✅ Backfilled Content_Document_Id__c on ' + toUpdate.size() + ' items.');
