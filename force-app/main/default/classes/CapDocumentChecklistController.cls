public with sharing class CapDocumentChecklistController {
  @TestVisible
  private static final String PROMPT_APPLICATION_NAME = 'PromptTemplateGenerationsInvocable';

  // ─── Data retrieval ───────────────────────────────────────────────────────

  @AuraEnabled(cacheable=true)
  public static List<Onboarding_Document_Checklist__c> getChecklistData(
    Id caseId
  ) {
    return [
      SELECT
        Id,
        Category__c,
        Status__c,
        Items_Approved__c,
        Items_Total__c,
        Assigned_Team__c,
        Notes__c,
        (
          SELECT
            Id,
            Status__c,
            Is_Required__c,
            Content_Document_Id__c,
            Due_Date__c,
            Expiration_Date__c,
            Submitted_Date__c,
            Reviewed_Date__c,
            Rejection_Reason__c,
            Notes__c,
            Document_Type__r.Name,
            Document_Type__r.Instructions_for_Submitter__c,
            Document_Type__r.Sort_Order__c,
            Reviewer__r.Name
          FROM Checklist_Items__r
          ORDER BY
            Document_Type__r.Sort_Order__c NULLS LAST,
            Document_Type__r.Name ASC
        )
      FROM Onboarding_Document_Checklist__c
      WHERE Case__c = :caseId
      WITH USER_MODE
      ORDER BY Category__c ASC
    ];
  }

  // ─── Agentforce analysis ──────────────────────────────────────────────────

  @AuraEnabled
  public static Map<Id, AnalysisResult> analyzeDocuments(List<Id> itemIds) {
    List<Onboarding_Document_Checklist_Item__c> items = [
      SELECT
        Id,
        Content_Document_Id__c,
        Document_Type__r.Name,
        Document_Type__r.Instructions_for_Submitter__c
      FROM Onboarding_Document_Checklist_Item__c
      WHERE Id IN :itemIds AND Content_Document_Id__c != NULL
      WITH USER_MODE
    ];

    Map<Id, AnalysisResult> results = new Map<Id, AnalysisResult>();

    for (Onboarding_Document_Checklist_Item__c item : items) {
      try {
        String responseText = invokePromptTemplate(
          item.Content_Document_Id__c,
          item.Document_Type__r?.Name,
          item.Document_Type__r?.Instructions_for_Submitter__c
        );
        results.put(item.Id, parseResponse(responseText));
      } catch (Exception e) {
        AnalysisResult errorResult = new AnalysisResult();
        errorResult.summary = 'Analysis could not be completed for this document.';
        errorResult.issues = e.getMessage();
        errorResult.status = 'ACTION REQUIRED';
        errorResult.hasIssues = true;
        results.put(item.Id, errorResult);
      }
    }

    return results;
  }

  @AuraEnabled(cacheable=true)
  public static FilePreviewInfo getFilePreviewInfo(String contentDocumentId) {
    if (String.isBlank(contentDocumentId)) {
      throw new AuraHandledException('Content document id is required.');
    }

    List<ContentVersion> versions = [
      SELECT Id, ContentDocumentId, Title, FileExtension
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH USER_MODE
      LIMIT 1
    ];

    if (versions.isEmpty()) {
      throw new AuraHandledException('No previewable file version was found.');
    }

    ContentVersion version = versions[0];
    FilePreviewInfo info = new FilePreviewInfo();
    info.contentDocumentId = version.ContentDocumentId;
    info.contentVersionId = version.Id;
    info.title = version.Title;
    info.fileExtension = version.FileExtension;
    return info;
  }

  private static String invokePromptTemplate(
    String contentDocumentId,
    String documentTypeName,
    String documentInstructions
  ) {
    ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
    promptInput.isPreview = false;
    promptInput.inputParams = buildPromptInputs(
      contentDocumentId,
      documentTypeName,
      documentInstructions
    );
    promptInput.additionalConfig = new ConnectApi.EinsteinLLMAdditionalConfigInput();
    promptInput.additionalConfig.applicationName = PROMPT_APPLICATION_NAME;

    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
      'CAP_Document_Analysis',
      promptInput
    );

    return response.generations[0].text;
  }

  @TestVisible
  private static Map<String, ConnectApi.WrappedValue> buildPromptInputs(
    String contentDocumentId,
    String documentTypeName,
    String documentInstructions
  ) {
    Map<String, ConnectApi.WrappedValue> inputs = new Map<String, ConnectApi.WrappedValue>();

    ConnectApi.WrappedValue docVal = new ConnectApi.WrappedValue();
    docVal.value = new Map<String, String>{
      'id' => contentDocumentId,
      'type' => 'ContentDocument'
    };
    inputs.put('Input:Document', docVal);

    ConnectApi.WrappedValue typeVal = new ConnectApi.WrappedValue();
    typeVal.value = documentTypeName != null ? documentTypeName : '';
    inputs.put('Input:Document_Type_Name', typeVal);

    ConnectApi.WrappedValue instrVal = new ConnectApi.WrappedValue();
    instrVal.value = documentInstructions != null ? documentInstructions : '';
    inputs.put('Input:Document_Instructions', instrVal);

    return inputs;
  }

  private static AnalysisResult parseResponse(String text) {
    AnalysisResult result = new AnalysisResult();
    if (String.isBlank(text)) {
      result.summary = 'No response received.';
      result.issues = '';
      result.status = 'ACTION REQUIRED';
      result.hasIssues = true;
      return result;
    }

    Integer summaryIdx = text.indexOf('SUMMARY:');
    Integer issuesIdx = text.indexOf('ISSUES:');
    Integer statusIdx = text.indexOf('STATUS:');

    if (summaryIdx >= 0 && issuesIdx > summaryIdx) {
      result.summary = text.substring(summaryIdx + 8, issuesIdx).trim();
    } else {
      result.summary = text.trim();
    }

    if (issuesIdx >= 0 && statusIdx > issuesIdx) {
      result.issues = text.substring(issuesIdx + 7, statusIdx).trim();
    }

    if (statusIdx >= 0) {
      result.status = text.substring(statusIdx + 7).trim().toUpperCase();
    } else {
      result.status = 'ACTION REQUIRED';
    }

    result.hasIssues =
      result.status.contains('ACTION REQUIRED') ||
      (result.issues != null &&
      !result.issues.equalsIgnoreCase('None detected.'));

    return result;
  }

  // ─── Review update ────────────────────────────────────────────────────────

  @AuraEnabled
  public static void updateItemReview(
    Id itemId,
    String status,
    String rejectionReason,
    String notes
  ) {
    Onboarding_Document_Checklist_Item__c item = new Onboarding_Document_Checklist_Item__c(
      Id = itemId
    );

    if (String.isNotBlank(status)) {
      item.Status__c = status;
      item.Reviewer__c = UserInfo.getUserId();
      item.Reviewed_Date__c = System.now();
      if (status == 'Rejected') {
        item.Rejection_Reason__c = rejectionReason;
      }
    }

    if (notes != null) {
      item.Notes__c = notes;
    }

    try {
      update as user item;
    } catch (DmlException e) {
      throw new AuraHandledException(e.getDmlMessage(0));
    }
  }

  // ─── Inner classes ────────────────────────────────────────────────────────

  public class AnalysisResult {
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public String issues;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean hasIssues;
  }

  public class FilePreviewInfo {
    @AuraEnabled
    public String contentDocumentId;
    @AuraEnabled
    public String contentVersionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileExtension;
  }
}
