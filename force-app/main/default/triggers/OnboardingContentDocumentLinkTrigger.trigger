trigger OnboardingContentDocumentLinkTrigger on ContentDocumentLink(
  after insert
) {
  OnboardingContentDocumentLinkHandler.handleAfterInsert(Trigger.new);
}
