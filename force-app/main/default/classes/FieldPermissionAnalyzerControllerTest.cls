@IsTest
private class FieldPermissionAnalyzerControllerTest {
    private static Integer userSequence = 0;
    
    private class AccessExpectation {
        Boolean hasReadAccess = false;
        Boolean hasEditAccess = false;
        Integer sourceCount = 0;
    }
    
    private static User createTestUser() {
        userSequence++;
        String uniqueValue = String.valueOf(DateTime.now().getTime()) + '-' + String.valueOf(userSequence);
        User testUser = new User(
            FirstName = 'FLS',
            LastName = 'Inspector',
            Alias = 'flsusr',
            Email = 'fls-inspector-' + uniqueValue + '@example.com',
            Username = 'fls-inspector-' + uniqueValue + '@example.com',
            CommunityNickname = 'fls-' + uniqueValue,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert testUser;
        return testUser;
    }
    
    private static Boolean hasOptionValue(
        List<FieldPermissionAnalyzerController.PicklistOption> options,
        String expectedValue
    ) {
        for (FieldPermissionAnalyzerController.PicklistOption option : options) {
            if (option.value == expectedValue) {
                return true;
            }
        }
        return false;
    }
    
    private static Boolean hasUserId(
        List<FieldPermissionAnalyzerController.UserWrapper> users,
        Id expectedUserId
    ) {
        for (FieldPermissionAnalyzerController.UserWrapper userWrap : users) {
            if (userWrap.id == expectedUserId) {
                return true;
            }
        }
        return false;
    }
    
    private static AccessExpectation calculateExpectedAccess(
        Id userId,
        String objectApiName,
        String fieldApiName
    ) {
        AccessExpectation expectation = new AccessExpectation();
        
        Set<Id> permissionSetIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
        ]) {
            permissionSetIds.add(assignment.PermissionSetId);
        }
        
        if (permissionSetIds.isEmpty()) {
            return expectation;
        }
        
        Map<Id, Boolean> sourceCanReadObject = new Map<Id, Boolean>();
        Map<Id, Boolean> sourceCanEditObject = new Map<Id, Boolean>();
        
        for (ObjectPermissions op : [
            SELECT
                ParentId,
                PermissionsRead,
                PermissionsEdit,
                PermissionsViewAllRecords,
                PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :permissionSetIds
            AND SObjectType = :objectApiName
        ]) {
            sourceCanReadObject.put(
                op.ParentId,
                op.PermissionsRead == true ||
                op.PermissionsViewAllRecords == true ||
                op.PermissionsModifyAllRecords == true
            );
            sourceCanEditObject.put(
                op.ParentId,
                op.PermissionsEdit == true || op.PermissionsModifyAllRecords == true
            );
        }
        
        String fieldKey = objectApiName + '.' + fieldApiName;
        for (FieldPermissions fp : [
            SELECT ParentId, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId IN :permissionSetIds
            AND Field = :fieldKey
        ]) {
            expectation.sourceCount++;
            
            Boolean hasRead = fp.PermissionsRead == true &&
                sourceCanReadObject.containsKey(fp.ParentId) &&
                sourceCanReadObject.get(fp.ParentId);
            Boolean hasEdit = fp.PermissionsEdit == true &&
                sourceCanEditObject.containsKey(fp.ParentId) &&
                sourceCanEditObject.get(fp.ParentId);
            
            if (hasRead) {
                expectation.hasReadAccess = true;
            }
            if (hasEdit) {
                expectation.hasEditAccess = true;
            }
        }
        
        return expectation;
    }
    
    // ========== Helper Methods for Permission Setup ==========
    
    private static PermissionSet createTestPermissionSet(String name) {
        PermissionSet ps = new PermissionSet(
            Name = name,
            Label = name + ' Label'
        );
        insert ps;
        return ps;
    }
    
    private static void assignPermissionSetToUser(Id userId, Id permissionSetId) {
        PermissionSetAssignment assignment = new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permissionSetId
        );
        insert assignment;
    }
    
    private static void grantFieldPermission(
        Id permissionSetId,
        String fieldKey,
        Boolean canRead,
        Boolean canEdit
    ) {
        FieldPermissions fp = new FieldPermissions(
            Field = fieldKey,
            ParentId = permissionSetId,
            PermissionsRead = canRead,
            PermissionsEdit = canEdit
        );
        insert fp;
    }
    
    private static void grantObjectPermission(
        Id permissionSetId,
        String objectApiName,
        Boolean canRead,
        Boolean canEdit
    ) {
        ObjectPermissions op = new ObjectPermissions(
            ParentId = permissionSetId,
            SObjectType = objectApiName,
            PermissionsRead = canRead,
            PermissionsEdit = canEdit
        );
        insert op;
    }
    
    @IsTest
    static void searchAndDescribeMethods_coverAccountMetadata() {
        User testUser = createTestUser();
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.UserWrapper> shortSearch =
            FieldPermissionAnalyzerController.searchUsers('a');
        List<FieldPermissionAnalyzerController.UserWrapper> users =
            FieldPermissionAnalyzerController.searchUsers('FLS Inspector');
        List<FieldPermissionAnalyzerController.PicklistOption> objects =
            FieldPermissionAnalyzerController.getAllObjects();
        List<FieldPermissionAnalyzerController.PicklistOption> fields =
            FieldPermissionAnalyzerController.getObjectFields('Account');
        List<FieldPermissionAnalyzerController.PicklistOption> invalidFields =
            FieldPermissionAnalyzerController.getObjectFields('DoesNotExist__c');
        Test.stopTest();
        
        System.assertEquals(0, shortSearch.size(), 'Search terms shorter than 2 chars must return no users.');
        System.assert(
            hasUserId(users, testUser.Id),
            'Created test user should be returned by search.'
        );
        System.assert(hasOptionValue(objects, 'Account'), 'Account should be present in object options.');
        System.assert(hasOptionValue(fields, 'Name'), 'Account.Name should be present in field options.');
        System.assertEquals(0, invalidFields.size(), 'Unknown object should return an empty field list.');
    }
    
    @IsTest
    static void analyzeFieldPermissions_calculatesEffectiveAccessForAccountName() {
        User testUser = createTestUser();
        AccessExpectation expected = calculateExpectedAccess(testUser.Id, 'Account', 'Name');
        
        Test.startTest();
        FieldPermissionAnalyzerController.PermissionAnalysisResult result =
            FieldPermissionAnalyzerController.analyzeFieldPermissions(
                testUser.Id,
                'Account',
                'Name'
            );
        Test.stopTest();
        
        System.assertEquals(true, result.isSuccess, 'Analysis should complete successfully.');
        System.assertEquals('Account', result.objectApiName, 'Object API name should be echoed back.');
        System.assertEquals('Name', result.fieldApiName, 'Field API name should be echoed back.');
        System.assertEquals(expected.hasReadAccess, result.hasReadAccess, 'Read access should match effective access.');
        System.assertEquals(expected.hasEditAccess, result.hasEditAccess, 'Edit access should match effective access.');
        System.assertNotEquals(null, result.permissionSources, 'Permission source list should always be initialized.');
        System.assertEquals(
            result.permissionSources.size(),
            result.totalSources,
            'totalSources should match permissionSources size.'
        );
        System.assertEquals(
            expected.sourceCount,
            result.totalSources,
            'Returned source count should match matching FieldPermissions rows.'
        );
    }
    
    @IsTest
    static void analyzeFieldPermissions_validatesRequiredInputs() {
        Test.startTest();
        FieldPermissionAnalyzerController.PermissionAnalysisResult result =
            FieldPermissionAnalyzerController.analyzeFieldPermissions(
                null,
                'Account',
                'Name'
            );
        Test.stopTest();
        
        System.assertEquals(false, result.isSuccess, 'Missing required params should fail validation.');
        System.assert(
            result.errorMessage != null && result.errorMessage.contains('required'),
            'Validation error should explain required inputs.'
        );
    }
    
    @IsTest
    static void getUserPermissionSets_returnsListWithoutErrors() {
        User testUser = createTestUser();
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.AssignedPermissionSet> assigned =
            FieldPermissionAnalyzerController.getUserPermissionSets(testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, assigned, 'Method should always return a non-null list.');
    }
    
    // ========== New Enhanced Tests ==========
    
    @IsTest
    static void searchUsers_returnsEmptyForShortTermsAndBlanks() {
        User testUser = createTestUser();
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.UserWrapper> blankSearch =
            FieldPermissionAnalyzerController.searchUsers('');
        List<FieldPermissionAnalyzerController.UserWrapper> nullSearch =
            FieldPermissionAnalyzerController.searchUsers(null);
        List<FieldPermissionAnalyzerController.UserWrapper> singleCharSearch =
            FieldPermissionAnalyzerController.searchUsers('F');
        Test.stopTest();
        
        System.assertEquals(0, blankSearch.size(), 'Blank search should return no results.');
        System.assertEquals(0, nullSearch.size(), 'Null search should return no results.');
        System.assertEquals(0, singleCharSearch.size(), 'Single character search should return no results.');
    }
    
    @IsTest
    static void searchUsers_returnsEmptyWhenNoMatches() {
        User testUser = createTestUser();
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.UserWrapper> noMatches =
            FieldPermissionAnalyzerController.searchUsers('ZZZUniqueName');
        Test.stopTest();
        
        System.assertEquals(0, noMatches.size(), 'Search with no matching users should return empty list.');
    }
    
    @IsTest
    static void searchUsers_returnsSortedMultipleResults() {
        User user1 = createTestUser();
        User user2 = createTestUser();
        User user3 = createTestUser();
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.UserWrapper> results =
            FieldPermissionAnalyzerController.searchUsers('FLS');
        Test.stopTest();
        
        System.assert(results.size() >= 3, 'Search should return at least 3 matching users.');
        Boolean isSorted = true;
        for (Integer i = 0; i < results.size() - 1; i++) {
            if (results[i].name.compareTo(results[i + 1].name) > 0) {
                isSorted = false;
                break;
            }
        }
        System.assert(isSorted, 'Search results should be sorted alphabetically by name.');
    }
    
    @IsTest
    static void getObjectFields_returnsEmptyForInvalidObject() {
        Test.startTest();
        List<FieldPermissionAnalyzerController.PicklistOption> invalidResults =
            FieldPermissionAnalyzerController.getObjectFields('CompletelyFakeObject__c');
        List<FieldPermissionAnalyzerController.PicklistOption> blankResults =
            FieldPermissionAnalyzerController.getObjectFields('');
        Test.stopTest();
        
        System.assertEquals(0, invalidResults.size(), 'Invalid object should return empty field list.');
        System.assertEquals(0, blankResults.size(), 'Blank object name should return empty field list.');
    }
    
    @IsTest
    static void getObjectFields_includesDataTypeInLabel() {
        Test.startTest();
        List<FieldPermissionAnalyzerController.PicklistOption> fields =
            FieldPermissionAnalyzerController.getObjectFields('Account');
        Test.stopTest();
        
        System.assert(fields.size() > 0, 'Account should have fields.');
        Boolean hasTypeInfo = false;
        for (FieldPermissionAnalyzerController.PicklistOption field : fields) {
            if (field.label.contains('-') && field.label.contains('(')) {
                hasTypeInfo = true;
                break;
            }
        }
        System.assert(
            hasTypeInfo,
            'Field labels should include data type information (format: "Label (API) - TYPE").'
        );
    }
    
    @IsTest
    static void analyzeFieldPermissions_validatesAllRequiredInputs() {
        Test.startTest();
        
        FieldPermissionAnalyzerController.PermissionAnalysisResult resultNullUser =
            FieldPermissionAnalyzerController.analyzeFieldPermissions(
                null,
                'Account',
                'Name'
            );
        FieldPermissionAnalyzerController.PermissionAnalysisResult resultNullObject =
            FieldPermissionAnalyzerController.analyzeFieldPermissions(
                UserInfo.getUserId(),
                null,
                'Name'
            );
        FieldPermissionAnalyzerController.PermissionAnalysisResult resultNullField =
            FieldPermissionAnalyzerController.analyzeFieldPermissions(
                UserInfo.getUserId(),
                'Account',
                null
            );
        
        Test.stopTest();
        
        System.assertEquals(
            false,
            resultNullUser.isSuccess,
            'Should fail when user ID is null.'
        );
        System.assertEquals(
            false,
            resultNullObject.isSuccess,
            'Should fail when object name is null.'
        );
        System.assertEquals(
            false,
            resultNullField.isSuccess,
            'Should fail when field name is null.'
        );
    }
    
    @IsTest
    static void getUserPermissionSets_returnsMultiplePermissionSets() {
        User testUser = createTestUser();
        PermissionSet ps1 = createTestPermissionSet('TestPS_List1');
        PermissionSet ps2 = createTestPermissionSet('TestPS_List2');
        
        assignPermissionSetToUser(testUser.Id, ps1.Id);
        assignPermissionSetToUser(testUser.Id, ps2.Id);
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.AssignedPermissionSet> assigned =
            FieldPermissionAnalyzerController.getUserPermissionSets(testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, assigned, 'Should return a non-null list.');
        System.assertEquals(
            2,
            assigned.size(),
            'Should return both assigned permission sets.'
        );
        
        Boolean hasPS1 = false;
        Boolean hasPS2 = false;
        for (FieldPermissionAnalyzerController.AssignedPermissionSet aps : assigned) {
            if (aps.apiName == ps1.Name) {
                hasPS1 = true;
            }
            if (aps.apiName == ps2.Name) {
                hasPS2 = true;
            }
        }
        System.assert(hasPS1, 'Should include first permission set.');
        System.assert(hasPS2, 'Should include second permission set.');
    }
    
    @IsTest
    static void getUserPermissionSets_resultsSorted() {
        User testUser = createTestUser();
        PermissionSet psZ = createTestPermissionSet('TestPS_Zebra');
        PermissionSet psA = createTestPermissionSet('TestPS_Alpha');
        PermissionSet psM = createTestPermissionSet('TestPS_Mike');
        
        assignPermissionSetToUser(testUser.Id, psZ.Id);
        assignPermissionSetToUser(testUser.Id, psA.Id);
        assignPermissionSetToUser(testUser.Id, psM.Id);
        
        Test.startTest();
        List<FieldPermissionAnalyzerController.AssignedPermissionSet> assigned =
            FieldPermissionAnalyzerController.getUserPermissionSets(testUser.Id);
        Test.stopTest();
        
        System.assertEquals(3, assigned.size(), 'Should return all three permission sets.');
        Boolean isSorted = true;
        for (Integer i = 0; i < assigned.size() - 1; i++) {
            if (assigned[i].name.compareTo(assigned[i + 1].name) > 0) {
                isSorted = false;
                break;
            }
        }
        System.assert(isSorted, 'Permission sets should be sorted by name.');
    }
}
