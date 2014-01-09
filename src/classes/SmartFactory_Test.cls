/*
   Copyright 2011 Mavens Consulting, Inc.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/   

@isTest
private class SmartFactory_Test {
	static {
		SmartFactory.FillAllFields = true; // increase test coverage without creating custom objects
	}  

	static testMethod void createsSingleObjectWithSingleRequiredStringField() {
		Account account = (Account)SmartFactory.createSObject('Account');
		insert account;
		System.assert(account.Id != null);
		System.assert(account.Name != null);
	}
	
	static testMethod void createsUser() {
		User u = (User)SmartFactory.createSObject('User');
		insert u;
		System.assert(u.Id != null);
	}

	static testMethod void createsObjectWithCascadeSetsLookupField() {
		Contact contact = (Contact)SmartFactory.createSObject('Contact', true);
		insert contact;
		System.assert(contact.Id != null);
		System.assert(contact.AccountId != null);
	}
	
	static testMethod void createsObjectWithoutCascadeDoesNotSetLookupField() {
		Contact contact = (Contact)SmartFactory.createSObject('Contact', false);
		insert contact;
		System.assert(contact.AccountId == null);
	}
	
	static testMethod void createObjectWithUnsupportedTypeThrowsException() {
		try {
			SmartFactory.createSObject('Unsupported');
			System.assert(false);
		} catch (UnsupportedObjectTypeException ex) {
			System.assert(true);
		}
	}
	
	static testMethod void creating401UniqueRecords() {
		
		// if you hit the limit of CPU time due to many custom fields, uncomment the following line
		// SmartFactory.FillAllFields = false;

		List<SObject> contactsAsSObjects = SmartFactory.createSObjectList('Contact', false, 401);
		insert contactsAsSObjects;
		for (SObject s : contactsAsSObjects)
		{
			Contact c = (Contact) s;
			System.assert(c.Id != null);
		}
	}  

	static testMethod void creating200UniqueRecordsWithCascade() {

		// if you hit the limit of CPU time due to many custom fields, uncomment the following line
		// SmartFactory.FillAllFields = false;

		List<SObject> contactsAsSObjects = SmartFactory.createSObjectList('Contact', true, 200);
		insert contactsAsSObjects;
		for (SObject s : contactsAsSObjects)
		{
			Contact c = (Contact) s;
			System.assert(c.Id != null);
		}
	}
	
    static testMethod void loadTestWith100PlusAccountNContacts() {
    	for (Integer idx = 0; idx <= 101; idx++)
    		Account account = (Account)SmartFactory.createSObject('Account');
		for (Integer idx = 0; idx <= 101; idx++)
    		Contact cont = (Contact)SmartFactory.createSObject('Contact');    		
    }

	static testMethod void creatingRecordsWithSpecificDefaults() {

		Map<String, Object> defaults = new Map<String, Object>{
			'Birthdate'=> Date.newInstance(1980, 1, 1),          // all records will get this date
			'Department'=> new List<String>{'Dept 1', 'Dept 2'}  // half will get the first value, half the second
		};

		List<SObject> contactsAsSObjects = SmartFactory.createSObjectList('Contact', 20, defaults);
		insert contactsAsSObjects;
		for (SObject s : contactsAsSObjects)
		{
			Contact c = (Contact) s;
			System.assert(c.Id != null);
			System.assert(c.Department.startsWith('Dept'));
			System.assertEquals(Date.newInstance(1980, 1, 1), c.Birthdate);
		}
		system.debug(loggingLevel.WARN, (Contact)(contactsAsSObjects[0]));
	}  

	static testMethod void creatingRecordsForSpecificParentId() {
		Account account = (Account)SmartFactory.createSObject('Account');
		insert account;

		// create 20 contacts in that account
		List<Contact> contactsAsSObjects = (List<Contact>)(SmartFactory.createSObjectList(
			'Contact', 20, new Map<String, Object>{'AccountId' => account.Id}));
		insert contactsAsSObjects;

		for (Contact c : contactsAsSObjects)
		{
			System.assert(c.Id != null);
			System.assert(c.AccountId == account.Id);
		}
	}  

	static testMethod void creatingRecordsForSpecificParentObject() {
		Account account = (Account)SmartFactory.createSObject('Account');
		insert account;

		// create 20 contacts in that account
		List<SObject> contactsAsSObjects = 
			SmartFactory.createSObjectList('Contact', 20, new Map<String, Object>{'AccountId' => account});
		insert contactsAsSObjects;

		for (SObject s : contactsAsSObjects)
		{
			Contact c = (Contact) s;
			System.assert(c.Id != null);
			System.assert(c.AccountId == account.Id);
		}
	}  

	static testMethod void creatingRecordsWithListOfDefaultParents() {

		// create 5 accounts
		list<Account> accountList = (list<Account>)(SmartFactory.createSObjectList('Account', 5));
		insert accountList;

		// each account gets 4 contacts
		List<SObject> contactsAsSObjects = SmartFactory.createSObjectList('Contact', 20, new Map<String, Object>{'AccountId' => accountList});
		insert contactsAsSObjects;

		Id acctId = accountList[0].Id;
		list<Contact> contactCount = [select id from contact where accountId = : acctId ]; 
		system.assertEquals(4, contactCount.size());
	}  

}