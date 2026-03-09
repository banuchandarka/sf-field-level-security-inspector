import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex methods
import searchUsers from '@salesforce/apex/FieldPermissionAnalyzerController.searchUsers';
import getAllObjects from '@salesforce/apex/FieldPermissionAnalyzerController.getAllObjects';
import getObjectFields from '@salesforce/apex/FieldPermissionAnalyzerController.getObjectFields';
import analyzeFieldPermissions from '@salesforce/apex/FieldPermissionAnalyzerController.analyzeFieldPermissions';

export default class FieldPermissionAnalyzer extends NavigationMixin(LightningElement) {
    
    // Search and User Selection
    @track searchTerm = '';
    @track userSearchResults = [];
    @track selectedUser = null;
    @track showUserResults = false;
    
    // Object and Field Selection
    @track objectOptions = [];
    @track fieldOptions = [];
    @track selectedObject = '';
    @track selectedField = '';
    
    // Results
    @track analysisResult = null;
    @track errorMessage = '';
    
    // UI State
    @track isLoading = false;
    
    // Debounce timer for search
    searchTimeout;

    // ================== LIFECYCLE HOOKS ==================
    
    connectedCallback() {
        this.loadObjects();
    }

    // ================== GETTERS ==================
    
    get isObjectSelectDisabled() {
        return !this.selectedUser;
    }
    
    get isFieldSelectDisabled() {
        return !this.selectedObject;
    }
    
    get isAnalyzeDisabled() {
        return !this.selectedUser || !this.selectedObject || !this.selectedField || this.isLoading;
    }
    
    get noUsersFound() {
        return this.searchTerm.length >= 2 && this.userSearchResults.length === 0;
    }
    
    get hasPermissionSources() {
        return this.analysisResult && 
               this.analysisResult.permissionSources && 
               this.analysisResult.permissionSources.length > 0;
    }

    // ================== DATA LOADING ==================
    
    async loadObjects() {
        try {
            const result = await getAllObjects();
            this.objectOptions = result.map(obj => ({
                label: obj.label,
                value: obj.value
            }));
        } catch (error) {
            this.showToast('Error', 'Failed to load objects: ' + this.reduceErrors(error), 'error');
        }
    }
    
    async loadFields(objectName) {
        try {
            this.isLoading = true;
            const result = await getObjectFields({ objectApiName: objectName });
            this.fieldOptions = result.map(field => ({
                label: field.label,
                value: field.value
            }));
        } catch (error) {
            this.showToast('Error', 'Failed to load fields: ' + this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ================== EVENT HANDLERS ==================
    
    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.analysisResult = null;
        this.errorMessage = '';
        
        // Clear previous timeout
        clearTimeout(this.searchTimeout);
        
        if (this.searchTerm.length < 2) {
            this.userSearchResults = [];
            this.showUserResults = false;
            return;
        }
        
        // Debounce search
        this.searchTimeout = setTimeout(() => {
            this.performUserSearch();
        }, 300);
    }
    
    async performUserSearch() {
        try {
            const results = await searchUsers({ searchTerm: this.searchTerm });
            this.userSearchResults = results;
            this.showUserResults = true;
        } catch (error) {
            this.showToast('Error', 'Search failed: ' + this.reduceErrors(error), 'error');
            this.userSearchResults = [];
        }
    }
    
    handleUserSelect(event) {
        const userId = event.currentTarget.dataset.userId;
        const userName = event.currentTarget.dataset.userName;
        const profileName = event.currentTarget.dataset.profileName;
        
        this.selectedUser = {
            id: userId,
            name: userName,
            profileName: profileName
        };
        
        this.showUserResults = false;
        this.searchTerm = '';
        this.userSearchResults = [];
        
        // Reset downstream selections
        this.selectedObject = '';
        this.selectedField = '';
        this.fieldOptions = [];
        this.analysisResult = null;
    }
    
    clearSelectedUser() {
        this.selectedUser = null;
        this.selectedObject = '';
        this.selectedField = '';
        this.fieldOptions = [];
        this.analysisResult = null;
    }
    
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedField = '';
        this.analysisResult = null;
        
        if (this.selectedObject) {
            this.loadFields(this.selectedObject);
        } else {
            this.fieldOptions = [];
        }
    }
    
    handleFieldChange(event) {
        this.selectedField = event.detail.value;
        this.analysisResult = null;
    }
    
    async analyzePermissions() {
        if (!this.selectedUser || !this.selectedObject || !this.selectedField) {
            this.showToast('Validation Error', 'Please select user, object, and field', 'warning');
            return;
        }
        
        this.isLoading = true;
        this.analysisResult = null;
        this.errorMessage = '';
        
        try {
            const result = await analyzeFieldPermissions({
                userId: this.selectedUser.id,
                objectApiName: this.selectedObject,
                fieldApiName: this.selectedField
            });
            
            if (result.isSuccess) {
                this.analysisResult = result;
                this.showToast('Success', 'Permission analysis complete!', 'success');
            } else {
                this.errorMessage = result.errorMessage;
                this.showToast('Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    navigateToPermissionSet(event) {
        const permSetId = event.currentTarget.dataset.id;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: permSetId,
                objectApiName: 'PermissionSet',
                actionName: 'view'
            }
        });
    }

    // ================== UTILITY METHODS ==================
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
    
    reduceErrors(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error.body) {
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }
            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors.map(e => e.message).join(', ');
            }
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}
