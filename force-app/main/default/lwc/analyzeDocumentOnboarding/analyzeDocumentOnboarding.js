import { LightningElement, api } from 'lwc';
import { open, execute } from 'lightning/accApi';

const BOT_ID = '0Xxak000003JDz7CAG';

export default class AnalyzeDocumentOnboarding extends LightningElement {
    @api recordId;
    isLoading = false;

    async handleClick() {
        this.isLoading = true;
        try {
            await open(BOT_ID);
            await execute(`Analyze this document for DocumentChecklistItem ID ${this.recordId}`, BOT_ID);
        } finally {
            this.isLoading = false;
        }
    }
}
