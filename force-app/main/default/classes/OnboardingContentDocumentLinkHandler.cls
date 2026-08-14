public with sharing class OnboardingContentDocumentLinkHandler {
  public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
    Set<Id> linkedEntityIds = new Set<Id>();
    for (ContentDocumentLink cdl : newLinks) {
      linkedEntityIds.add(cdl.LinkedEntityId);
    }

    // Only process links where the linked entity is a Checklist Item
    Map<Id, Onboarding_Document_Checklist_Item__c> itemMap = new Map<Id, Onboarding_Document_Checklist_Item__c>(
      [
        SELECT Id, Status__c, Content_Document_Id__c, Submitted_Date__c
        FROM Onboarding_Document_Checklist_Item__c
        WHERE Id IN :linkedEntityIds
        WITH USER_MODE
      ]
    );

    if (itemMap.isEmpty()) {
      return;
    }

    List<Onboarding_Document_Checklist_Item__c> toUpdate = new List<Onboarding_Document_Checklist_Item__c>();

    for (ContentDocumentLink cdl : newLinks) {
      if (!itemMap.containsKey(cdl.LinkedEntityId)) {
        continue;
      }
      Onboarding_Document_Checklist_Item__c item = itemMap.get(
        cdl.LinkedEntityId
      );
      item.Content_Document_Id__c = String.valueOf(cdl.ContentDocumentId);
      item.Submitted_Date__c = System.now();
      // Only move to Pending Review if the item hasn't already been reviewed
      if (item.Status__c == 'Not Started' || item.Status__c == 'Rejected') {
        item.Status__c = 'Pending Review';
      }
      toUpdate.add(item);
    }

    if (!toUpdate.isEmpty()) {
      update as user toUpdate;
    }
  }
}
