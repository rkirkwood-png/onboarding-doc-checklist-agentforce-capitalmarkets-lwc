import { LightningElement, api, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getChecklistData from "@salesforce/apex/CapDocumentChecklistController.getChecklistData";
import analyzeDocuments from "@salesforce/apex/CapDocumentChecklistController.analyzeDocuments";
import getFilePreviewInfo from "@salesforce/apex/CapDocumentChecklistController.getFilePreviewInfo";
import updateItemReview from "@salesforce/apex/CapDocumentChecklistController.updateItemReview";

const STATUS_BADGE = {
  "Not Started": "slds-badge",
  "In Progress": "slds-badge slds-badge--inprogress",
  Complete: "slds-badge slds-badge--complete",
  Blocked: "slds-badge slds-badge--blocked",
  "Pending Review": "slds-badge slds-badge--pending",
  Approved: "slds-badge slds-badge--approved",
  Rejected: "slds-badge slds-badge--rejected",
  Expired: "slds-badge slds-badge--expired",
  Waived: "slds-badge slds-badge--waived"
};

export default class CapDocumentChecklist extends LightningElement {
  @api recordId;

  @track checklists = [];
  @track isAnalyzing = false;
  @track showDocumentModal = false;
  @track errorMessage = null;
  @track lastAnalyzedAt = null;

  modalDocumentId = null;
  modalDocumentTitle = "";
  modalFileUrl = "";
  modalDownloadUrl = "";
  modalFullPreviewUrl = "";
  modalPreviewError = null;
  isModalPreviewLoading = false;

  _wiredResult;
  _analysisMap = {};
  _expandedChecklists = new Set();
  _expandedItems = new Set();
  _pendingRejections = {};
  _showRejectionFor = new Set();

  // ─── Wire ────────────────────────────────────────────────────────────────

  @wire(getChecklistData, { caseId: "$recordId" })
  wiredChecklists(result) {
    this._wiredResult = result;
    if (result.data) {
      this._buildState(result.data);
      this.errorMessage = null;
    } else if (result.error) {
      this.errorMessage =
        "Failed to load document checklists. Please refresh the page.";
    }
  }

  // ─── State builders ───────────────────────────────────────────────────────

  _buildState(data) {
    this.checklists = data.map((cl) => this._mapChecklist(cl));
  }

  _mapChecklist(cl) {
    const expanded = this._expandedChecklists.has(cl.Id);
    const approved = cl.Items_Approved__c || 0;
    const total = cl.Items_Total__c || 0;
    const allDone = total > 0 && approved === total;
    const items = (cl.Checklist_Items__r || []).map((item) =>
      this._mapItem(item)
    );
    const missingCount = items.filter(
      (item) => item.isRequired && !item.hasDocument
    ).length;
    const analyzedCount = items.filter((item) => item.hasAnalysis).length;
    const nigoCount = items.filter((item) => item.hasFlag).length;
    const hasAiSummary = analyzedCount > 0;
    const hasNigoFlags = nigoCount > 0;

    return {
      id: cl.Id,
      category: cl.Category__c || "Uncategorized",
      status: cl.Status__c || "Not Started",
      itemsApproved: approved,
      itemsTotal: total,
      missingCount,
      missingLabel:
        missingCount === 1
          ? "1 required doc missing"
          : `${missingCount} required docs missing`,
      analyzedCount,
      nigoCount,
      hasAiSummary,
      aiSummaryLabel: hasNigoFlags
        ? `NIGO Flag (${nigoCount}/${analyzedCount})`
        : `AI Clear (0/${analyzedCount})`,
      aiSummaryBadgeClass: hasNigoFlags
        ? "slds-badge ai-summary-badge ai-summary-badge--nigo slds-m-left_x-small"
        : "slds-badge ai-summary-badge ai-summary-badge--clear slds-m-left_x-small",
      aiSummaryIconName: hasNigoFlags ? "utility:warning" : "utility:success",
      isExpanded: expanded,
      chevronIcon: expanded ? "utility:chevrondown" : "utility:chevronright",
      progressLabel: `${approved} / ${total} Approved`,
      progressPillClass: allDone
        ? "progress-pill progress-pill--complete"
        : "progress-pill",
      statusBadgeClass: STATUS_BADGE[cl.Status__c] || "slds-badge",
      items
    };
  }

  _mapItem(item) {
    const expanded = this._expandedItems.has(item.Id);
    const analysis = this._analysisMap[item.Id] || null;
    const hasDocument = !!item.Content_Document_Id__c;
    const hasFlag = this._isNigoAnalysis(analysis);
    const showRejection = this._showRejectionFor.has(item.Id);

    return {
      id: item.Id,
      documentTypeName: item.Document_Type__r?.Name || "Unknown Document",
      documentTypeInstructions:
        item.Document_Type__r?.Instructions_for_Submitter__c || "",
      contentDocumentId: item.Content_Document_Id__c || null,
      status: item.Status__c || "Not Started",
      isRequired: item.Is_Required__c,
      dueDate: item.Due_Date__c || "—",
      submittedDate: item.Submitted_Date__c
        ? new Date(item.Submitted_Date__c).toLocaleDateString()
        : "—",
      reviewerName: item.Reviewer__r?.Name || "—",
      notes: item.Notes__c || "",
      isExpanded: expanded,
      showRejectionReason: showRejection,
      pendingRejectionReason: this._pendingRejections[item.Id] || "",
      analysis,
      hasDocument,
      hasAnalysis: !!analysis,
      hasFlag,
      itemRecordUrl: `/${item.Id}`,
      chevronIcon: expanded ? "utility:chevrondown" : "utility:chevronright",
      submissionBadgeClass: hasDocument
        ? "slds-badge slds-badge--submitted"
        : "slds-badge slds-badge--not-submitted",
      submissionLabel: hasDocument ? "● Submitted" : "Not Submitted",
      statusBadgeClass: STATUS_BADGE[item.Status__c] || "slds-badge",
      analysisCalloutClass: analysis
        ? analysis.hasIssues
          ? "analysis-callout analysis-callout--flagged slds-m-bottom_small"
          : "analysis-callout analysis-callout--ok slds-m-bottom_small"
        : ""
    };
  }

  // ─── Getters ──────────────────────────────────────────────────────────────

  get hasChecklists() {
    return this.checklists && this.checklists.length > 0;
  }

  get totalApproved() {
    return this.checklists.reduce(
      (sum, cl) => sum + (cl.itemsApproved || 0),
      0
    );
  }

  get totalItems() {
    return this.checklists.reduce((sum, cl) => sum + (cl.itemsTotal || 0), 0);
  }

  get isAnalyzeDisabled() {
    if (this.isAnalyzing) return true;
    return !this.checklists.some((cl) =>
      cl.items.some((item) => item.hasDocument)
    );
  }

  get analyzeButtonTitle() {
    return this.isAnalyzeDisabled && !this.isAnalyzing
      ? "No submitted documents to analyze"
      : "Run Einstein AI analysis on all submitted documents";
  }

  get lastAnalyzedLabel() {
    if (!this.lastAnalyzedAt) {
      return "Not analyzed yet";
    }

    return `Last analyzed: ${new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(this.lastAnalyzedAt)}`;
  }

  // ─── Accordion handlers ───────────────────────────────────────────────────

  handleToggleChecklist(event) {
    const id = event.currentTarget.dataset.id;
    if (this._expandedChecklists.has(id)) {
      this._expandedChecklists.delete(id);
    } else {
      this._expandedChecklists.add(id);
    }
    this._rebuildState();
  }

  handleToggleItem(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (this._expandedItems.has(id)) {
      this._expandedItems.delete(id);
    } else {
      this._expandedItems.add(id);
    }
    this._rebuildState();
  }

  // ─── Analyze All ─────────────────────────────────────────────────────────

  async handleAnalyzeAll() {
    const itemIds = this.checklists
      .flatMap((cl) => cl.items)
      .filter((item) => item.hasDocument)
      .map((item) => item.id);

    if (itemIds.length === 0) return;

    try {
      const analyzedCount = await this._analyzeItems(itemIds);
      this.lastAnalyzedAt = new Date();
      this._showToast(
        "Analysis Complete",
        `${analyzedCount} document(s) analyzed.`,
        "success"
      );
    } catch (error) {
      this._handleAnalysisError(error);
    }
  }

  async handleAnalyzeItem(event) {
    event.stopPropagation();
    const itemId = event.currentTarget.dataset.id;
    if (!itemId) return;

    try {
      await this._analyzeItems([itemId]);
      this._showToast(
        "Analysis Complete",
        "Document analysis has been refreshed.",
        "success"
      );
    } catch (error) {
      this._handleAnalysisError(error);
    }
  }

  // ─── Review actions ───────────────────────────────────────────────────────

  handleReviewAction(event) {
    event.stopPropagation();
    const itemId = event.currentTarget.dataset.id;
    const action = event.currentTarget.dataset.action;

    if (action === "Rejected") {
      this._showRejectionFor.add(itemId);
      this._rebuildState();
      return;
    }

    this._submitReview(itemId, action, null);
  }

  handleRejectionReasonChange(event) {
    const itemId = event.currentTarget.dataset.id;
    this._pendingRejections[itemId] = event.detail.value;
  }

  handleConfirmRejection(event) {
    event.stopPropagation();
    const itemId = event.currentTarget.dataset.id;
    const reason = this._pendingRejections[itemId] || "";
    this._showRejectionFor.delete(itemId);
    delete this._pendingRejections[itemId];
    this._submitReview(itemId, "Rejected", reason);
  }

  handleCancelRejection(event) {
    event.stopPropagation();
    const itemId = event.currentTarget.dataset.id;
    this._showRejectionFor.delete(itemId);
    delete this._pendingRejections[itemId];
    this._rebuildState();
  }

  async _submitReview(itemId, status, rejectionReason) {
    const notesEl = this.template.querySelector(
      `lightning-textarea[data-id="${itemId}"]`
    );
    const notes = notesEl ? notesEl.value : null;

    try {
      await updateItemReview({ itemId, status, rejectionReason, notes });
      await refreshApex(this._wiredResult);
      this._showToast("Saved", `Item marked as ${status}.`, "success");
    } catch (error) {
      this._showToast(
        "Error",
        error?.body?.message || "Failed to save review.",
        "error"
      );
    }
  }

  // ─── Notes ────────────────────────────────────────────────────────────────

  async handleNotesSave(event) {
    const itemId = event.currentTarget.dataset.id;
    const notes = event.detail.value;

    try {
      await updateItemReview({
        itemId,
        status: null,
        rejectionReason: null,
        notes
      });
    } catch {
      this._showToast("Error", "Failed to save notes.", "error");
    }
  }

  // ─── Document modal ───────────────────────────────────────────────────────

  async handleViewDocument(event) {
    event.stopPropagation();
    this.modalDocumentId = event.currentTarget.dataset.docid;
    this.modalDocumentTitle = event.currentTarget.dataset.doctitle;
    this.modalFileUrl = "";
    this.modalDownloadUrl = "";
    this.modalFullPreviewUrl = `/sfc/servlet.shepherd/document/preview/${this.modalDocumentId}`;
    this.modalPreviewError = null;
    this.isModalPreviewLoading = true;
    this.showDocumentModal = true;

    try {
      const previewInfo = await getFilePreviewInfo({
        contentDocumentId: this.modalDocumentId
      });
      this.modalFileUrl = this._buildRenditionUrl(previewInfo);
      this.modalDownloadUrl = `/sfc/servlet.shepherd/version/download/${previewInfo.contentVersionId}`;
    } catch (error) {
      this.modalPreviewError =
        error?.body?.message ||
        "Preview could not be loaded. Open the full preview instead.";
    } finally {
      this.isModalPreviewLoading = false;
    }
  }

  handleCloseModal() {
    this.showDocumentModal = false;
    this.modalDocumentId = null;
    this.modalDocumentTitle = "";
    this.modalFileUrl = "";
    this.modalDownloadUrl = "";
    this.modalFullPreviewUrl = "";
    this.modalPreviewError = null;
    this.isModalPreviewLoading = false;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  _rebuildState() {
    if (this._wiredResult?.data) {
      this._buildState(this._wiredResult.data);
    }
  }

  async _analyzeItems(itemIds) {
    this.isAnalyzing = true;
    this.errorMessage = null;

    try {
      const results = await analyzeDocuments({ itemIds });
      Object.assign(this._analysisMap, results);
      this._rebuildState();
      return Object.keys(results).length;
    } finally {
      this.isAnalyzing = false;
    }
  }

  _handleAnalysisError(error) {
    this.errorMessage = "Einstein analysis failed. Please try again.";
    console.error("analyzeDocuments error:", error);
  }

  _isNigoAnalysis(analysis) {
    if (!analysis) return false;
    return (
      analysis.hasIssues ||
      (analysis.status || "").toUpperCase() === "ACTION REQUIRED"
    );
  }

  _buildRenditionUrl(previewInfo) {
    return `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${previewInfo.contentVersionId}`;
  }

  _showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
