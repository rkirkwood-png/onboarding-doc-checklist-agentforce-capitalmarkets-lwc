@IsTest
private class OnboardingContentDocumentLinkHandlerTest {
  @TestSetup
  static void setup() {
    Case c = new Case(
      Subject = 'Test Onboarding Case',
      Status = 'New',
      Origin = 'Web'
    );
    insert c;

    Onboarding_Document_Checklist__c checklist = new Onboarding_Document_Checklist__c(
      Name = 'Legal & Entity',
      Case__c = c.Id,
      Category__c = 'Legal & Entity',
      Status__c = 'Not Started'
    );
    insert checklist;

    Onboarding_Document_Checklist_Item__c item = new Onboarding_Document_Checklist_Item__c(
      Name = 'Certificate of Incorporation',
      Case__c = c.Id,
      Onboarding_Document_Checklist__c = checklist.Id,
      Status__c = 'Not Started',
      Is_Required__c = true
    );
    insert item;
  }

  @IsTest
  static void testFileUploadSetsContentDocumentIdAndStatus() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      LIMIT 1
    ];

    Test.startTest();
    ContentVersion cv = new ContentVersion(
      Title = 'Test Document',
      PathOnClient = 'test.pdf',
      VersionData = Blob.valueOf('Test file content'),
      FirstPublishLocationId = item.Id
    );
    insert cv;
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Id, Status__c, Content_Document_Id__c, Submitted_Date__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];

    Assert.areEqual(
      'Pending Review',
      updated.Status__c,
      'Status should be Pending Review after file upload'
    );
    Assert.isNotNull(
      updated.Content_Document_Id__c,
      'Content_Document_Id__c should be populated after upload'
    );
    Assert.isNotNull(
      updated.Submitted_Date__c,
      'Submitted_Date__c should be set after upload'
    );
  }

  @IsTest
  static void testFileUploadOnRejectedItemResetsStatus() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      LIMIT 1
    ];
    item.Status__c = 'Rejected';
    update item;

    Test.startTest();
    ContentVersion cv = new ContentVersion(
      Title = 'Resubmitted Document',
      PathOnClient = 'resubmit.pdf',
      VersionData = Blob.valueOf('Resubmission content'),
      FirstPublishLocationId = item.Id
    );
    insert cv;
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Status__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];
    Assert.areEqual(
      'Pending Review',
      updated.Status__c,
      'Rejected item should move to Pending Review on resubmission'
    );
  }

  @IsTest
  static void testFileUploadOnApprovedItemDoesNotChangeStatus() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      LIMIT 1
    ];
    item.Status__c = 'Approved';
    update item;

    Test.startTest();
    ContentVersion cv = new ContentVersion(
      Title = 'Additional Document',
      PathOnClient = 'additional.pdf',
      VersionData = Blob.valueOf('Additional content'),
      FirstPublishLocationId = item.Id
    );
    insert cv;
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Status__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];
    Assert.areEqual(
      'Approved',
      updated.Status__c,
      'Approved item status should not be overwritten by a new file upload'
    );
  }

  @IsTest
  static void testFileUploadOnCaseDoesNotAffectItems() {
    Case c = [SELECT Id FROM Case LIMIT 1];
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id, Status__c, Content_Document_Id__c
      FROM Onboarding_Document_Checklist_Item__c
      LIMIT 1
    ];

    Test.startTest();
    // Upload a file directly to the Case, not to the Item
    ContentVersion cv = new ContentVersion(
      Title = 'Case-level Document',
      PathOnClient = 'case_doc.pdf',
      VersionData = Blob.valueOf('Case level content'),
      FirstPublishLocationId = c.Id
    );
    insert cv;
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c unchanged = [
      SELECT Status__c, Content_Document_Id__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];
    Assert.areEqual(
      'Not Started',
      unchanged.Status__c,
      'Item status should not change when file is uploaded to the Case'
    );
    Assert.isNull(
      unchanged.Content_Document_Id__c,
      'Content_Document_Id__c should remain null when file is on the Case'
    );
  }
}
