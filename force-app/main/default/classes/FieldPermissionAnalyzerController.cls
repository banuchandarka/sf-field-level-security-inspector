/**
 * @description Controller for Field Level Security Permission Analyzer
 * @author Your Name
 */
public with sharing class FieldPermissionAnalyzerController {
    
    /**
     * @description Search for active users by name or username
     * @param searchTerm The search string
     * @return List of matching users
     */
    @AuraEnabled(cacheable=true)
    public static List<UserWrapper> searchUsers(String searchTerm) {
        List<UserWrapper> userList = new List<UserWrapper>();
        
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return userList;
        }
        
        String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        List<User> users = [
            SELECT Id, Name, Username, Email, Profile.Name, IsActive, SmallPhotoUrl
            FROM User 
            WHERE (Name LIKE :searchKey OR Username LIKE :searchKey OR Email LIKE :searchKey)
            AND IsActive = true
            ORDER BY Name ASC
            LIMIT 25
        ];
        
        for (User u : users) {
            userList.add(new UserWrapper(u));
        }
        
        return userList;
    }
    
    /**
     * @description Get all accessible objects in the org
     * @return List of object options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAllObjects() {
        List<PicklistOption> options = new List<PicklistOption>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for (String objName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult descResult = globalDescribe.get(objName).getDescribe();
            
            // Filter to show only accessible, queryable, and relevant objects
            if (descResult.isAccessible() && 
                descResult.isQueryable() && 
                !descResult.isDeprecatedAndHidden()) {
                
                String label = descResult.getLabel();
                String name = descResult.getName();
                
                // Include object API name in label for clarity
                options.add(new PicklistOption(name, label + ' (' + name + ')'));
            }
        }
        
        // Sort by label
        options.sort();
        return options;
    }
    
    /**
     * @description Get all fields for a specific object
     * @param objectApiName The API name of the object
     * @return List of field options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getObjectFields(String objectApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        
        if (String.isBlank(objectApiName)) {
            return options;
        }
        
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        
        if (sObjectType == null) {
            return options;
        }
        
        Map<String, Schema.SObjectField> fieldsMap = sObjectType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDesc = fieldsMap.get(fieldName).getDescribe();
            
            String label = fieldDesc.getLabel();
            String name = fieldDesc.getName();
            String fieldType = String.valueOf(fieldDesc.getType());
            
            options.add(new PicklistOption(name, label + ' (' + name + ') - ' + fieldType));
        }
        
        options.sort();
        return options;
    }
    
    /**
     * @description Analyze field permissions for a user on a specific field
     * @param userId The user's Id
     * @param objectApiName The object API name
     * @param fieldApiName The field API name
     * @return Permission analysis result
     */
    @AuraEnabled
    public static PermissionAnalysisResult analyzeFieldPermissions(
        String userId, 
        String objectApiName, 
        String fieldApiName
    ) {
        PermissionAnalysisResult result = new PermissionAnalysisResult();
        result.permissionSources = new List<PermissionSourceDetail>();
        result.objectApiName = objectApiName;
        result.fieldApiName = fieldApiName;
        
        try {
            // Get User details
            User targetUser = [
                SELECT Id, Name, Username, ProfileId, Profile.Name 
                FROM User 
                WHERE Id = :userId
                LIMIT 1
            ];
            
            result.userName = targetUser.Name;
            result.userProfileName = targetUser.Profile.Name;
            
            // Get all Permission Set Assignments for the user
            List<PermissionSetAssignment> assignments = [
                SELECT 
                    PermissionSetId,
                    PermissionSet.Name,
                    PermissionSet.Label,
                    PermissionSet.IsOwnedByProfile,
                    PermissionSet.Profile.Name,
                    PermissionSet.PermissionSetGroupId,
                    PermissionSet.PermissionSetGroup.MasterLabel,
                    PermissionSet.PermissionSetGroup.DeveloperName,
                    PermissionSet.Type
                FROM PermissionSetAssignment 
                WHERE AssigneeId = :userId
            ];
            
            // Collect all Permission Set IDs
            Set<Id> permissionSetIds = new Set<Id>();
            Map<Id, PermissionSetAssignment> assignmentMap = new Map<Id, PermissionSetAssignment>();
            
            for (PermissionSetAssignment psa : assignments) {
                permissionSetIds.add(psa.PermissionSetId);
                assignmentMap.put(psa.PermissionSetId, psa);
            }
            
            // Query Field Permissions
            String fieldKey = objectApiName + '.' + fieldApiName;
            
            List<FieldPermissions> fieldPermissions = [
                SELECT 
                    Id,
                    Field,
                    PermissionsRead,
                    PermissionsEdit,
                    ParentId,
                    Parent.Name,
                    Parent.Label,
                    Parent.IsOwnedByProfile,
                    Parent.Profile.Name,
                    Parent.PermissionSetGroupId,
                    Parent.PermissionSetGroup.MasterLabel,
                    Parent.Type
                FROM FieldPermissions 
                WHERE ParentId IN :permissionSetIds
                AND Field = :fieldKey
            ];
            
            // Process each permission source
            for (FieldPermissions fp : fieldPermissions) {
                PermissionSourceDetail source = new PermissionSourceDetail();
                source.permissionSetId = fp.ParentId;
                source.hasRead = fp.PermissionsRead == true;
                source.hasEdit = fp.PermissionsEdit == true;
                
                // Determine the source type and name
                if (fp.Parent.IsOwnedByProfile) {
                    source.sourceType = 'Profile';
                    source.sourceName = fp.Parent.Profile.Name;
                    source.sourceIcon = 'standard:user';
                    source.badgeClass = 'slds-badge slds-theme_success';
                } else if (fp.Parent.PermissionSetGroupId != null) {
                    source.sourceType = 'Permission Set Group';
                    source.sourceName = fp.Parent.PermissionSetGroup.MasterLabel;
                    source.permissionSetName = fp.Parent.Label;
                    source.sourceIcon = 'standard:groups';
                    source.badgeClass = 'slds-badge slds-theme_warning';
                } else if (fp.Parent.Type == 'Session') {
                    source.sourceType = 'Session-Based Permission Set';
                    source.sourceName = fp.Parent.Label;
                    source.sourceIcon = 'standard:timeslot';
                    source.badgeClass = 'slds-badge slds-theme_info';
                } else {
                    source.sourceType = 'Permission Set';
                    source.sourceName = fp.Parent.Label;
                    source.sourceIcon = 'standard:permission_set';
                    source.badgeClass = 'slds-badge slds-theme_alt-inverse';
                }
                
                // Track overall access
                if (source.hasRead) {
                    result.hasReadAccess = true;
                }
                if (source.hasEdit) {
                    result.hasEditAccess = true;
                }
                
                result.permissionSources.add(source);
            }
            
            // Sort sources: Profile first, then Permission Set Groups, then Permission Sets
            result.permissionSources.sort();
            
            result.isSuccess = true;
            result.totalSources = result.permissionSources.size();
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Get user's assigned permission sets and permission set groups
     * @param userId The user's Id
     * @return List of assigned permission sets
     */
    @AuraEnabled(cacheable=true)
    public static List<AssignedPermissionSet> getUserPermissionSets(String userId) {
        List<AssignedPermissionSet> assignedSets = new List<AssignedPermissionSet>();
        
        List<PermissionSetAssignment> assignments = [
            SELECT 
                PermissionSetId,
                PermissionSet.Name,
                PermissionSet.Label,
                PermissionSet.IsOwnedByProfile,
                PermissionSet.Profile.Name,
                PermissionSet.PermissionSetGroupId,
                PermissionSet.PermissionSetGroup.MasterLabel,
                PermissionSet.Type,
                PermissionSet.Description
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :userId
            AND PermissionSet.IsOwnedByProfile = false
            ORDER BY PermissionSet.Label ASC
        ];
        
        for (PermissionSetAssignment psa : assignments) {
            AssignedPermissionSet aps = new AssignedPermissionSet();
            aps.permissionSetId = psa.PermissionSetId;
            aps.name = psa.PermissionSet.Label;
            aps.apiName = psa.PermissionSet.Name;
            aps.description = psa.PermissionSet.Description;
            
            if (psa.PermissionSet.PermissionSetGroupId != null) {
                aps.type = 'Permission Set Group';
                aps.groupName = psa.PermissionSet.PermissionSetGroup.MasterLabel;
            } else if (psa.PermissionSet.Type == 'Session') {
                aps.type = 'Session-Based';
            } else {
                aps.type = 'Permission Set';
            }
            
            assignedSets.add(aps);
        }
        
        return assignedSets;
    }
    
    // ================== WRAPPER CLASSES ==================
    
    /**
     * @description Wrapper for User data
     */
    public class UserWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String email;
        @AuraEnabled public String profileName;
        @AuraEnabled public String photoUrl;
        
        public UserWrapper(User u) {
            this.id = u.Id;
            this.name = u.Name;
            this.username = u.Username;
            this.email = u.Email;
            this.profileName = u.Profile.Name;
            this.photoUrl = u.SmallPhotoUrl;
        }
    }
    
    /**
     * @description Generic picklist option wrapper
     */
    public class PicklistOption implements Comparable {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        
        public PicklistOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
        
        public Integer compareTo(Object compareTo) {
            PicklistOption other = (PicklistOption) compareTo;
            return this.label.compareTo(other.label);
        }
    }
    
    /**
     * @description Result wrapper for permission analysis
     */
    public class PermissionAnalysisResult {
        @AuraEnabled public Boolean isSuccess = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String userName;
        @AuraEnabled public String userProfileName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public Boolean hasReadAccess = false;
        @AuraEnabled public Boolean hasEditAccess = false;
        @AuraEnabled public Integer totalSources = 0;
        @AuraEnabled public List<PermissionSourceDetail> permissionSources;
    }
    
    /**
     * @description Detail wrapper for each permission source
     */
    public class PermissionSourceDetail implements Comparable {
        @AuraEnabled public String permissionSetId;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String permissionSetName; // For PSG, the actual perm set within the group
        @AuraEnabled public String sourceIcon;
        @AuraEnabled public String badgeClass;
        @AuraEnabled public Boolean hasRead = false;
        @AuraEnabled public Boolean hasEdit = false;
        
        public Integer compareTo(Object compareTo) {
            PermissionSourceDetail other = (PermissionSourceDetail) compareTo;
            
            // Sort order: Profile > Permission Set Group > Permission Set > Session-Based
            Map<String, Integer> sortOrder = new Map<String, Integer>{
                'Profile' => 1,
                'Permission Set Group' => 2,
                'Permission Set' => 3,
                'Session-Based Permission Set' => 4
            };
            
            Integer thisOrder = sortOrder.get(this.sourceType) != null ? sortOrder.get(this.sourceType) : 5;
            Integer otherOrder = sortOrder.get(other.sourceType) != null ? sortOrder.get(other.sourceType) : 5;
            
            if (thisOrder != otherOrder) {
                return thisOrder - otherOrder;
            }
            return this.sourceName.compareTo(other.sourceName);
        }
    }
    
    /**
     * @description Wrapper for assigned permission sets
     */
    public class AssignedPermissionSet {
        @AuraEnabled public String permissionSetId;
        @AuraEnabled public String name;
        @AuraEnabled public String apiName;
        @AuraEnabled public String type;
        @AuraEnabled public String groupName;
        @AuraEnabled public String description;
    }
}
