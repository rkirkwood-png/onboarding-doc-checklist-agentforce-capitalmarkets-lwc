@IsTest
private class CapDocumentChecklistControllerTest {
  @TestSetup
  static void setup() {
    // Document types
    Onboarding_Document_Type__c kycType = new Onboarding_Document_Type__c(
      Name = 'KYC Customer Identification Form',
      Category__c = 'Compliance & Regulatory',
      Is_Required__c = true,
      Instructions_for_Submitter__c = 'Please provide a completed KYC form.',
      Sort_Order__c = 1
    );
    Onboarding_Document_Type__c amlType = new Onboarding_Document_Type__c(
      Name = 'Anti-Money Laundering Policy',
      Category__c = 'Compliance & Regulatory',
      Is_Required__c = true,
      Sort_Order__c = 2
    );
    insert new List<Onboarding_Document_Type__c>{ kycType, amlType };

    // Case
    Case testCase = new Case(Subject = 'Test Onboarding Case');
    insert testCase;

    // Checklist
    Onboarding_Document_Checklist__c checklist = new Onboarding_Document_Checklist__c(
      Case__c = testCase.Id,
      Category__c = 'Compliance & Regulatory',
      Status__c = 'In Progress',
      Items_Total__c = 2,
      Items_Approved__c = 0
    );
    insert checklist;

    // Items
    List<Onboarding_Document_Checklist_Item__c> items = new List<Onboarding_Document_Checklist_Item__c>{
      new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklist.Id,
        Case__c = testCase.Id,
        Document_Type__c = kycType.Id,
        Status__c = 'Pending Review',
        Is_Required__c = true,
        Content_Document_Id__c = 'fakeDocId001'
      ),
      new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklist.Id,
        Case__c = testCase.Id,
        Document_Type__c = amlType.Id,
        Status__c = 'Not Started',
        Is_Required__c = true
      )
    };
    insert items;
  }

  // ─── getChecklistData ─────────────────────────────────────────────────────

  @IsTest
  static void testGetChecklistData_returnsChecklists() {
    Case c = [SELECT Id FROM Case LIMIT 1];
    Test.startTest();
    List<Onboarding_Document_Checklist__c> result = CapDocumentChecklistController.getChecklistData(
      c.Id
    );
    Test.stopTest();

    Assert.isTrue(result.size() > 0, 'Should return at least one checklist');
    Assert.isTrue(
      result[0].Checklist_Items__r.size() > 0,
      'Should return child items'
    );
  }

  @IsTest
  static void testGetChecklistData_emptyCaseReturnsEmpty() {
    Case emptyCase = new Case(Subject = 'Empty Case');
    insert emptyCase;

    Test.startTest();
    List<Onboarding_Document_Checklist__c> result = CapDocumentChecklistController.getChecklistData(
      emptyCase.Id
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      result.size(),
      'Should return empty list for case with no checklists'
    );
  }

  // ─── updateItemReview ─────────────────────────────────────────────────────

  @IsTest
  static void testUpdateItemReview_approve() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Status__c = 'Pending Review'
      LIMIT 1
    ];

    Test.startTest();
    CapDocumentChecklistController.updateItemReview(
      item.Id,
      'Approved',
      null,
      'Looks good'
    );
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Status__c, Notes__c, Reviewer__c, Reviewed_Date__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];

    Assert.areEqual('Approved', updated.Status__c);
    Assert.areEqual('Looks good', updated.Notes__c);
    Assert.isNotNull(updated.Reviewer__c);
    Assert.isNotNull(updated.Reviewed_Date__c);
  }

  @IsTest
  static void testUpdateItemReview_reject() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Status__c = 'Pending Review'
      LIMIT 1
    ];

    Test.startTest();
    CapDocumentChecklistController.updateItemReview(
      item.Id,
      'Rejected',
      'Signature missing on page 3',
      null
    );
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Status__c, Rejection_Reason__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];

    Assert.areEqual('Rejected', updated.Status__c);
    Assert.areEqual('Signature missing on page 3', updated.Rejection_Reason__c);
  }

  @IsTest
  static void testUpdateItemReview_notesOnlyDoesNotChangeStatus() {
    Onboarding_Document_Checklist_Item__c item = [
      SELECT Id, Status__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Status__c = 'Pending Review'
      LIMIT 1
    ];
    String originalStatus = item.Status__c;

    Test.startTest();
    CapDocumentChecklistController.updateItemReview(
      item.Id,
      null,
      null,
      'Check expiration date'
    );
    Test.stopTest();

    Onboarding_Document_Checklist_Item__c updated = [
      SELECT Status__c, Notes__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id = :item.Id
    ];

    Assert.areEqual(
      originalStatus,
      updated.Status__c,
      'Status should not change for notes-only update'
    );
    Assert.areEqual('Check expiration date', updated.Notes__c);
  }

  // ─── parseResponse (via analyzeDocuments with mock) ──────────────────────

  @IsTest
  static void testBuildPromptInputs_usesPromptBuilderInputContract() {
    Map<String, ConnectApi.WrappedValue> inputs = CapDocumentChecklistController.buildPromptInputs(
      '069000000000001',
      'Certificate of Incorporation',
      'Upload a current certificate.'
    );

    Assert.isTrue(
      inputs.containsKey('Input:Document'),
      'Document input should use the Prompt Builder Input: prefix'
    );
    Assert.isTrue(
      inputs.containsKey('Input:Document_Type_Name'),
      'Document type input should use the Prompt Builder Input: prefix'
    );
    Assert.isTrue(
      inputs.containsKey('Input:Document_Instructions'),
      'Instructions input should use the Prompt Builder Input: prefix'
    );

    Map<String, String> documentValue = (Map<String, String>) inputs.get(
        'Input:Document'
      )
      .value;
    Assert.areEqual('069000000000001', documentValue.get('id'));
    Assert.areEqual('ContentDocument', documentValue.get('type'));
  }

  @IsTest
  static void testPromptApplicationName_usesRegisteredInvocableApp() {
    Assert.areEqual(
      'PromptTemplateGenerationsInvocable',
      CapDocumentChecklistController.PROMPT_APPLICATION_NAME,
      'Prompt Template invocations must use a registered AI application name'
    );
  }

  @IsTest
  static void testGetFilePreviewInfo_returnsLatestVersion() {
    ContentVersion version = new ContentVersion(
      Title = 'Preview Test',
      PathOnClient = 'PreviewTest.pdf',
      VersionData = Blob.valueOf('preview test content')
    );
    insert version;

    ContentVersion insertedVersion = [
      SELECT Id, ContentDocumentId, FileExtension, Title
      FROM ContentVersion
      WHERE Id = :version.Id
    ];

    Test.startTest();
    CapDocumentChecklistController.FilePreviewInfo result = CapDocumentChecklistController.getFilePreviewInfo(
      insertedVersion.ContentDocumentId
    );
    Test.stopTest();

    Assert.areEqual(
      insertedVersion.ContentDocumentId,
      result.contentDocumentId
    );
    Assert.areEqual(insertedVersion.Id, result.contentVersionId);
    Assert.areEqual('pdf', result.fileExtension);
    Assert.areEqual('Preview Test', result.title);
  }

  @IsTest
  static void testAnalyzeDocuments_skipsItemsWithNoDocument() {
    Onboarding_Document_Checklist_Item__c itemNoDoc = [
      SELECT Id
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Content_Document_Id__c = NULL
      LIMIT 1
    ];

    Test.startTest();
    // Items without Content_Document_Id__c are filtered out — result should be empty
    Map<Id, CapDocumentChecklistController.AnalysisResult> result = CapDocumentChecklistController.analyzeDocuments(
      new List<Id>{ itemNoDoc.Id }
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      result.size(),
      'Items without a document should not be analyzed'
    );
  }
}
