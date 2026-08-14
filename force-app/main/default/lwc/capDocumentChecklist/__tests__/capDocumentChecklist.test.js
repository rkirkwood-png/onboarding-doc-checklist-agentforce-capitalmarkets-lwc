import { createElement } from "lwc";
import CapDocumentChecklist from "c/capDocumentChecklist";
import getChecklistData from "@salesforce/apex/CapDocumentChecklistController.getChecklistData";
import analyzeDocuments from "@salesforce/apex/CapDocumentChecklistController.analyzeDocuments";
import getFilePreviewInfo from "@salesforce/apex/CapDocumentChecklistController.getFilePreviewInfo";

jest.mock(
  "@salesforce/apex/CapDocumentChecklistController.getChecklistData",
  () => {
    const {
      createApexTestWireAdapter
    } = require("@salesforce/wire-service-jest-util");
    return {
      default: createApexTestWireAdapter(jest.fn())
    };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CapDocumentChecklistController.analyzeDocuments",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/CapDocumentChecklistController.getFilePreviewInfo",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

const flushPromises = () => Promise.resolve();

const findButtonByLabel = (element, label) =>
  Array.from(element.shadowRoot.querySelectorAll("lightning-button")).find(
    (button) => button.label === label
  );

describe("c-cap-document-checklist", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the number of required checklist items missing documents", async () => {
    const element = createElement("c-cap-document-checklist", {
      is: CapDocumentChecklist
    });
    document.body.appendChild(element);

    getChecklistData.emit([
      {
        Id: "a01",
        Category__c: "Compliance",
        Status__c: "In Progress",
        Items_Approved__c: 1,
        Items_Total__c: 3,
        Checklist_Items__r: [
          {
            Id: "a02",
            Is_Required__c: true,
            Content_Document_Id__c: null
          },
          {
            Id: "a03",
            Is_Required__c: true,
            Content_Document_Id__c: "069000000000001"
          },
          {
            Id: "a04",
            Is_Required__c: false,
            Content_Document_Id__c: null
          }
        ]
      }
    ]);

    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("1 required doc missing");
  });

  it("renders a file rendition in the modal instead of embedding the preview page", async () => {
    getFilePreviewInfo.mockResolvedValue({
      contentDocumentId: "069000000000001",
      contentVersionId: "068000000000001",
      title: "Certificate of Incorporation",
      fileExtension: "png"
    });

    const element = createElement("c-cap-document-checklist", {
      is: CapDocumentChecklist
    });
    document.body.appendChild(element);

    getChecklistData.emit([
      {
        Id: "a01",
        Category__c: "Legal",
        Status__c: "In Progress",
        Items_Approved__c: 0,
        Items_Total__c: 1,
        Checklist_Items__r: [
          {
            Id: "a02",
            Is_Required__c: true,
            Content_Document_Id__c: "069000000000001",
            Document_Type__r: {
              Name: "Certificate of Incorporation"
            }
          }
        ]
      }
    ]);

    await flushPromises();

    element.shadowRoot.querySelector(".group-header").click();
    await flushPromises();

    element.shadowRoot.querySelector(".item-header").click();
    await flushPromises();

    element.shadowRoot.querySelector("[data-docid='069000000000001']").click();
    await flushPromises();
    await flushPromises();

    expect(getFilePreviewInfo).toHaveBeenCalledWith({
      contentDocumentId: "069000000000001"
    });

    const image = element.shadowRoot.querySelector(".preview-image");
    expect(image.src).toContain(
      "/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=068000000000001"
    );
    expect(element.shadowRoot.querySelector("iframe")).toBeNull();
  });

  it("shows section NIGO summary and timestamp after analyzing all documents", async () => {
    analyzeDocuments.mockResolvedValue({
      a02: {
        summary: "Certificate has missing filing stamp.",
        issues: "Missing filing stamp.",
        status: "ACTION REQUIRED",
        hasIssues: true
      },
      a03: {
        summary: "Proof of address is complete.",
        issues: "None detected.",
        status: "READY FOR REVIEW",
        hasIssues: false
      }
    });

    const element = createElement("c-cap-document-checklist", {
      is: CapDocumentChecklist
    });
    document.body.appendChild(element);

    getChecklistData.emit([
      {
        Id: "a01",
        Category__c: "Legal",
        Status__c: "In Progress",
        Items_Approved__c: 0,
        Items_Total__c: 2,
        Checklist_Items__r: [
          {
            Id: "a02",
            Is_Required__c: true,
            Content_Document_Id__c: "069000000000001",
            Document_Type__r: {
              Name: "Certificate of Incorporation"
            }
          },
          {
            Id: "a03",
            Is_Required__c: true,
            Content_Document_Id__c: "069000000000002",
            Document_Type__r: {
              Name: "Proof of Business Address"
            }
          }
        ]
      }
    ]);

    await flushPromises();
    expect(element.shadowRoot.textContent).toContain("Not analyzed yet");

    findButtonByLabel(element, "⚡ Analyze All Documents").click();
    await flushPromises();
    await flushPromises();
    await flushPromises();

    expect(analyzeDocuments).toHaveBeenCalledWith({ itemIds: ["a02", "a03"] });
    expect(element.shadowRoot.textContent).toContain("NIGO Flag (1/2)");
    expect(element.shadowRoot.textContent).toContain("Last analyzed:");
  });

  it("analyzes a single document and links to its checklist item record", async () => {
    analyzeDocuments.mockResolvedValue({
      a02: {
        summary: "Certificate has missing filing stamp.",
        issues: "Missing filing stamp.",
        status: "ACTION REQUIRED",
        hasIssues: true
      }
    });

    const element = createElement("c-cap-document-checklist", {
      is: CapDocumentChecklist
    });
    document.body.appendChild(element);

    getChecklistData.emit([
      {
        Id: "a01",
        Category__c: "Legal",
        Status__c: "In Progress",
        Items_Approved__c: 0,
        Items_Total__c: 1,
        Checklist_Items__r: [
          {
            Id: "a02",
            Is_Required__c: true,
            Content_Document_Id__c: "069000000000001",
            Document_Type__r: {
              Name: "Certificate of Incorporation"
            }
          }
        ]
      }
    ]);

    await flushPromises();

    element.shadowRoot.querySelector(".group-header").click();
    await flushPromises();

    element.shadowRoot.querySelector(".item-header").click();
    await flushPromises();

    const itemRecordLink = element.shadowRoot.querySelector("a[href='/a02']");
    expect(itemRecordLink).not.toBeNull();
    expect(itemRecordLink.textContent).toContain("Open Item Record");

    findButtonByLabel(element, "Analyze This Document").click();
    await flushPromises();
    await flushPromises();

    expect(analyzeDocuments).toHaveBeenCalledWith({ itemIds: ["a02"] });
    expect(element.shadowRoot.textContent).toContain("NIGO Flag (1/1)");
  });
});
