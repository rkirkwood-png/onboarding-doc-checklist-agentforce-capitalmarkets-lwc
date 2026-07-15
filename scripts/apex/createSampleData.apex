// ─────────────────────────────────────────────────────────────────────────────
// createSampleData.apex
// Run via: sf apex run --file scripts/apex/createSampleData.apex --target-org <alias>
//
// Creates a Case with all 5 checklist categories and 13 document items.
// No files are attached — items are in various statuses so the LWC renders
// a realistic view immediately.
// ─────────────────────────────────────────────────────────────────────────────

// ── Document Types ────────────────────────────────────────────────────────────

List<Onboarding_Document_Type__c> docTypes = new List<Onboarding_Document_Type__c>{
    new Onboarding_Document_Type__c(
        Name = 'Certificate of Incorporation',
        Category__c = 'Legal & Entity',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Provide a certified copy of your certificate of incorporation.',
        Sort_Order__c = 1
    ),
    new Onboarding_Document_Type__c(
        Name = 'Organizational Chart',
        Category__c = 'Legal & Entity',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Provide an org chart showing ultimate beneficial owners (25%+ ownership).',
        Sort_Order__c = 2
    ),
    new Onboarding_Document_Type__c(
        Name = 'Proof of Address',
        Category__c = 'Legal & Entity',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Utility bill or bank statement dated within the last 3 months.',
        Sort_Order__c = 3
    ),
    new Onboarding_Document_Type__c(
        Name = 'KYC Customer Identification Form',
        Category__c = 'Compliance & Regulatory',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Complete all sections including beneficial ownership and tax identification.',
        Sort_Order__c = 1
    ),
    new Onboarding_Document_Type__c(
        Name = 'Anti-Money Laundering Policy',
        Category__c = 'Compliance & Regulatory',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Provide your firm\'s current AML policy document.',
        Sort_Order__c = 2
    ),
    new Onboarding_Document_Type__c(
        Name = 'FATCA Self-Certification',
        Category__c = 'Compliance & Regulatory',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Complete the appropriate FATCA self-certification form for your entity type.',
        Sort_Order__c = 3
    ),
    new Onboarding_Document_Type__c(
        Name = 'Regulatory Disclosure Agreement',
        Category__c = 'Compliance & Regulatory',
        Is_Required__c = false,
        Instructions_for_Submitter__c = 'Sign and return the MarketAxess regulatory disclosure agreement.',
        Sort_Order__c = 4
    ),
    new Onboarding_Document_Type__c(
        Name = 'Authorized Trader Agreement',
        Category__c = 'Authorized Traders',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Each authorized trader must sign the Authorized Trader Agreement.',
        Sort_Order__c = 1
    ),
    new Onboarding_Document_Type__c(
        Name = 'Trader ID Verification',
        Category__c = 'Authorized Traders',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Government-issued photo ID for each authorized trader.',
        Sort_Order__c = 2
    ),
    new Onboarding_Document_Type__c(
        Name = 'Audited Financial Statements',
        Category__c = 'Financial',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Provide audited financial statements for the most recent fiscal year.',
        Sort_Order__c = 1
    ),
    new Onboarding_Document_Type__c(
        Name = 'Credit Application',
        Category__c = 'Financial',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'Complete the MarketAxess credit application form.',
        Sort_Order__c = 2
    ),
    new Onboarding_Document_Type__c(
        Name = 'W-9 / W-8BEN-E',
        Category__c = 'Financial',
        Is_Required__c = true,
        Instructions_for_Submitter__c = 'US entities: W-9. Non-US entities: W-8BEN-E. Must be signed and dated.',
        Sort_Order__c = 3
    ),
    new Onboarding_Document_Type__c(
        Name = 'Additional Supporting Documents',
        Category__c = 'Other',
        Is_Required__c = false,
        Instructions_for_Submitter__c = 'Any additional documents requested by the onboarding team.',
        Sort_Order__c = 1
    )
};
insert docTypes;

Map<String, Id> typeIdByName = new Map<String, Id>();
for (Onboarding_Document_Type__c dt : docTypes) {
    typeIdByName.put(dt.Name, dt.Id);
}

// ── Case ──────────────────────────────────────────────────────────────────────

Case testCase = new Case(
    Subject = 'MarketAxess Onboarding — Acme Capital Partners',
    Status  = 'New',
    Origin  = 'Web'
);
insert testCase;

// ── Checklists (one per category) ─────────────────────────────────────────────

List<Onboarding_Document_Checklist__c> checklists = new List<Onboarding_Document_Checklist__c>{
    new Onboarding_Document_Checklist__c(
        Case__c = testCase.Id, Category__c = 'Legal & Entity',
        Status__c = 'Complete', Items_Approved__c = 3, Items_Total__c = 3
    ),
    new Onboarding_Document_Checklist__c(
        Case__c = testCase.Id, Category__c = 'Compliance & Regulatory',
        Status__c = 'In Progress', Items_Approved__c = 1, Items_Total__c = 4
    ),
    new Onboarding_Document_Checklist__c(
        Case__c = testCase.Id, Category__c = 'Authorized Traders',
        Status__c = 'Complete', Items_Approved__c = 2, Items_Total__c = 2
    ),
    new Onboarding_Document_Checklist__c(
        Case__c = testCase.Id, Category__c = 'Financial',
        Status__c = 'Not Started', Items_Approved__c = 0, Items_Total__c = 3
    ),
    new Onboarding_Document_Checklist__c(
        Case__c = testCase.Id, Category__c = 'Other',
        Status__c = 'Not Started', Items_Approved__c = 0, Items_Total__c = 1
    )
};
insert checklists;

Map<String, Id> checklistIdByCategory = new Map<String, Id>();
for (Onboarding_Document_Checklist__c cl : checklists) {
    checklistIdByCategory.put(cl.Category__c, cl.Id);
}

// ── Checklist Items ───────────────────────────────────────────────────────────

List<Onboarding_Document_Checklist_Item__c> items = new List<Onboarding_Document_Checklist_Item__c>{
    // Legal & Entity — all approved
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Legal & Entity'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Certificate of Incorporation'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-5),
        Reviewed_Date__c  = System.now().addDays(-3)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Legal & Entity'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Organizational Chart'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-5),
        Reviewed_Date__c  = System.now().addDays(-3)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Legal & Entity'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Proof of Address'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-5),
        Reviewed_Date__c  = System.now().addDays(-3)
    ),
    // Compliance — mixed statuses
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Compliance & Regulatory'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Anti-Money Laundering Policy'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-4),
        Reviewed_Date__c  = System.now().addDays(-2)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Compliance & Regulatory'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('KYC Customer Identification Form'),
        Status__c = 'Pending Review', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-1),
        Due_Date__c = Date.today().addDays(7)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Compliance & Regulatory'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('FATCA Self-Certification'),
        Status__c = 'Not Started', Is_Required__c = true,
        Due_Date__c = Date.today().addDays(7)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Compliance & Regulatory'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Regulatory Disclosure Agreement'),
        Status__c = 'Pending Review', Is_Required__c = false,
        Submitted_Date__c = System.now().addDays(-1)
    ),
    // Authorized Traders — all approved
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Authorized Traders'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Authorized Trader Agreement'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-4),
        Reviewed_Date__c  = System.now().addDays(-2)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Authorized Traders'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Trader ID Verification'),
        Status__c = 'Approved', Is_Required__c = true,
        Submitted_Date__c = System.now().addDays(-4),
        Reviewed_Date__c  = System.now().addDays(-2)
    ),
    // Financial — not started
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Financial'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Audited Financial Statements'),
        Status__c = 'Not Started', Is_Required__c = true,
        Due_Date__c = Date.today().addDays(14)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Financial'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Credit Application'),
        Status__c = 'Not Started', Is_Required__c = true,
        Due_Date__c = Date.today().addDays(14)
    ),
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Financial'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('W-9 / W-8BEN-E'),
        Status__c = 'Not Started', Is_Required__c = true,
        Due_Date__c = Date.today().addDays(14)
    ),
    // Other
    new Onboarding_Document_Checklist_Item__c(
        Onboarding_Document_Checklist__c = checklistIdByCategory.get('Other'),
        Case__c = testCase.Id,
        Document_Type__c = typeIdByName.get('Additional Supporting Documents'),
        Status__c = 'Not Started', Is_Required__c = false
    )
};
insert items;

System.debug('✅ Sample data created. Case Id: ' + testCase.Id);
System.debug('   → Open the Case record page and add the capDocumentChecklist component to see it in action.');
