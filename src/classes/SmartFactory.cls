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

public with sharing class SmartFactory {
	public static Boolean fillAllFields = false;
	public static Profile userProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator'];

	// can't Map by Schema.SObjectType, use object name String instead
	public static Map<String, Set<String>> excludedFields = new Map<String, Set<String>>{
			'All' => new Set<String>{'OwnerId', 'LastModifiedById', 'CreatedById', 'LastModifiedDate', 'CreatedDate'},
			'Account' => new Set<String>{'FirstName', 'LastName'},
			'User' => new Set<String>{'IsActive','DelegatedApproverId','CallCenterId','ContactId','DelegatedApproverId','ManagerId','UserRoleId','FederationIdentifier'}
	};

	// to fill nillable fields, specify them here
	public static Map<String, Set<String>> includedFields = new Map<String, Set<String>>();

	// Key : SobjectAPIName  For ex. Account
	// Value : Map<String, Schema.SObjectField>, field Map (k:fieldname, v:Schema.Sobjectfield)
	private static final Map<String, Map<String, Schema.SObjectField>> fieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
	private static final Map<String, Id> defaultRecTypeCache = new Map<String, Id>();
	private static final Map<String, Id> referenceObjectCache = new Map<String, Id>();
	private static final Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
	private static final Boolean isPersonAccountEnabled = ( fieldMapFor('Account').get('IsPersonAccount') != null );
	private static final Set<String> skipPersonAccountFields = new Set<String>{ 'Salutation' };

	// Key: sobject.field
	// Value: first pickList value
	private static final Map<String, String> defaultPicklistValue = new Map<String, String>();

	// various simplified signatures for flexibility and backward compatibility
	public static SObject createSObject(String objectType) {
		return createSObject(objectType, false, 1, null);
	}

	public static SObject createSObject(String objectType, Map<String, Object> fieldValues) {
		return createSObject(objectType, false, 1, fieldValues);
	}

	public static SObject createSObject(String objectType, Boolean cascade) {
		return createSObject(objectType, cascade, 1, null);
	}

	public static SObject createSObject(String objectType, Boolean cascade, Integer counter) {
		return createSObject(objectType, cascade, counter, null);
	}

	public static SObject createSObject(String objectType, Boolean cascade, Map<String, Object> fieldValues) {
		return createSObject(objectType, cascade, 1, fieldValues);
	}

	// full service signature
	// by passing in fieldValues, you can Set defaults for any fields you like (data types must match)
	// for reference fields, fieldValues can optionally be actual parent objects to which you want the new objects to be related
	public static SObject createSObject(String objectType, Boolean cascade, Integer counter, Map<String, Object> fieldValues) {
		Schema.SObjectType token = globalDescribe.get(objectType);
		if (token == null) {
			throw new UnsupportedObjectTypeException('Unsupported ObjectType ' + objectType);
		}

		SObject obj = token.newSObject();		

		Set<String> exclude = new Set<String>(); 
		if(excludedFields.get('All') != null) {
			exclude.addAll(excludedFields.get('All'));
		}
		
		if(excludedFields.get(objectType) != null) {
			exclude.addAll(excludedFields.get(objectType));
		}
		
		Set<String> include = new Set<String>(); 
		if(includedFields.get(objectType) != null) {
			include.addAll(includedFields.get(objectType));
		}	
		
		if(fieldValues != null) {
			include.addAll(fieldValues.keySet());
		}		

		for (Schema.SObjectField field : fieldMapFor(objectType).values()) {
			setFieldValue(obj, field, cascade, counter, include, exclude, fieldValues);
		}

		return obj;
	}

	// more simplified signatures 
	public static List<SObject> createSObjectList(String objectType, Integer numberOfObjects) {
		return createSObjectList(objectType, false, numberOfObjects, null);
	}

	public static List<SObject> createSObjectList(String objectType, Integer numberOfObjects, Map<String, Object> fieldValues) {
		return createSObjectList(objectType, false, numberOfObjects, fieldValues);
	}

	public static List<SObject> createSObjectList(String objectType, Boolean cascade, Integer numberOfObjects) {
		return createSObjectList(objectType, cascade, numberOfObjects, null);
	}

	// main method to create a List of objects
	// fieldValues here work as above, but can optionally be a List of objects, in which case they will each be used 
	// in some of the objects created (see the test class for examples)
	public static List<SObject> createSObjectList(String objectType, Boolean cascade, Integer numberOfObjects, Map<String, Object> fieldValues) {
		List<SObject> sos = new List<SObject>();
		for( Integer i = 0; i < numberOfObjects; i++ ) {
			sos.add(createSObject(objectType, cascade, i, fieldValues));
		}
		
		return sos;  
	}

	/**
		Returns a field Map for a given sobject. 

		Note : this method is kept public for Test cases to share the same field Map info, without requiring a field desribe.

		@param objectType sobject api name for ex. Account
		@returns FieldMap [Key:FieldName,Value:Schema.SObjectField]
	*/
	public static  Map<String, Schema.SObjectField> fieldMapFor(String objectType) {
		Map<String, Schema.SObjectField> fieldMap = null;
		String normalizedObjectType = objectType.toLowerCase();

		if (fieldMapCache.containsKey(normalizedObjectType)) {
			fieldMap = fieldMapCache.get(normalizedObjectType);
		} else {
			fieldMap = globalDescribe.get(objectType).getDescribe().fields.getMap();
			// cache it for next use
			fieldMapCache.put(normalizedObjectType, fieldMap);
		}

		return fieldMap;
	}

	public static String getDefaultPickListValue(SObject obj, Schema.DescribeFieldResult fieldDescribe) {
		String key = obj.getSObjectType() + '.' + fieldDescribe.getName();

		if (!defaultPicklistValue.containsKey(key)) {
			List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();
			String value = entries.size() > 0 ? entries[0].getValue() : null;
			defaultPicklistValue.put(key, value);
		}

		return defaultPicklistValue.get(key);
	}

	public static Boolean isPersonAccountField(Schema.DescribeFieldResult fieldDescribe) {
        Boolean CustomPerson = fieldDescribe.isCustom() && fieldDescribe.getName().endsWith('pc');
        Boolean StandardPerson = !fieldDescribe.isCustom() && fieldDescribe.getName().startsWith('Person');

        return (isPersonAccountEnabled && (CustomPerson || StandardPerson || skipPersonAccountFields.contains(fieldDescribe.getName())));
	}

	public static void setFieldValue(SObject obj, Schema.SObjectField field, Boolean cascade, Integer counter, Set<String> include, Set<String> exclude, Map<String, Object> fieldValues) {
		Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
		Schema.DisplayType ft = fieldDescribe.getType();
		String fn = fieldDescribe.getName();
		
		if (fieldDescribe.isCreateable() && 
				(
					(
						!exclude.contains(fn) &&
						(!fieldDescribe.isNillable() || fillAllFields || (ft == Schema.DisplayType.Reference && cascade)) &&
						(!isPersonAccountEnabled || !isPersonAccountField(fieldDescribe))
					) 
				|| include.contains(fn))
			) {

			// look for a default value provided for this field
			if (fieldValues != null && fieldValues.containsKey(fn)) {

				// Set the field to the default provided, whether it is a value or a List of values
				// also supports getting the Id of an sobject if that is what is provided as a default
				setFieldOverrideValue( obj, field, fieldValues.get(fn), counter );

			} else if (ft == Schema.DisplayType.String) {

				if (fn == 'CommunityNickname') { 
					obj.put(field, 't'+ String.valueOf(Math.roundToLong(Math.random()*1000000)) ); 
				} else if (fn == 'Username') { 
					obj.put(field, 'test'+ String.valueOf(UserInfo.getOrganizationId())+ String.valueOf(Math.roundToLong(Math.random()*1000000))+ String.valueOf(Datetime.now()).replace('-','').replace(':','').replace(' ','')+'@test.com'); // was a@a.com
				} else {
					String s = (fn + counter.format());
					obj.put(field, (fieldDescribe.getLength() > s.length()) ? s : counter.format()); 
				}
			} else if (ft == Schema.DisplayType.PickList) {
				obj.put(field, getDefaultPickListValue(obj, fieldDescribe));
			} else if (ft == Schema.DisplayType.Integer) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Boolean) {
				obj.put(field, false);
			} else if (ft == Schema.DisplayType.Currency) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Date) {
				obj.put(field, Date.today());
			} else if (ft == Schema.DisplayType.Datetime) {
				obj.put(field, Datetime.now());
			} else if (ft == Schema.DisplayType.Double) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Email) {
				obj.put(field, 'test' + counter.format() + '@test.com');
			} else if (ft == Schema.DisplayType.TextArea) {
				obj.put(field, fn + counter.format()); 
			} else if (ft == Schema.DisplayType.Reference) {
				String objName = obj.getSObjectType().getDescribe().getName();
				String referenceObjectType = fieldDescribe.getReferenceTo()[0].getDescribe().getName();

				if (referenceObjectType == 'RecordType') {
					setRecordType(obj);
				} else if (referenceObjectType == 'Profile') { 
					obj.put(field, userProfile.Id);
				} else if (referenceObjectType == 'User') { 
					obj.put(field, UserInfo.getUserId());
				} else if (cascade && referenceObjectType != objName) {
					// TODO avoid infinite loop for same-type references
					if (referenceObjectCache.containsKey(referenceObjectType)) {
						obj.put(field, referenceObjectCache.get(referenceObjectType));
					} else {
						SObject reference = createSObject(referenceObjectType, fieldValues);
						insert reference;
						obj.put(field, reference.Id);
						referenceObjectCache.put(referenceObjectType, reference.Id);
					}
				}
			} else if (ft == Schema.DisplayType.MultiPickList) {
				obj.put(field, getDefaultPickListValue(obj, fieldDescribe));
			} else if (ft == Schema.DisplayType.Percent) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Phone) {
				obj.put(field, '(123) 456-7890');
			} else if (ft == Schema.DisplayType.Combobox) {
				obj.put(field, counter.format());
			} else if (ft == Schema.DisplayType.EncryptedString) {
				obj.put(field, 's');
			} else if (ft == Schema.DisplayType.Time) {
				obj.put(field, Time.newInstance(0, 0, 0, 0)); 
			} else if (ft == Schema.DisplayType.URL) {
				obj.put(field, 'http://test' + counter + '.com'); 
			} else if (ft == Schema.DisplayType.base64) {
				obj.put(field, Blob.valueOf(counter.format()));
			} else {
				System.debug('Unhandled field type ' + ft);
			}
		}	
	}

	public static void setFieldOverrideValue( SObject obj, Schema.SObjectField field, Object v, Integer counter ) {

		// first try to cast the object to a List of objects and use the right one
		// failing that, assume it is a single object or value
		try { 
			List<Object> oo = (List<Object>)(v);
			Integer i = (counter < oo.size()) ? counter : Math.mod(counter, oo.size());
			try { 
				obj.put(field, oo[i]);
			} catch (Exception ex1) {
				// if it isn't a value, try it as an SObject
				obj.put(field, ((SObject)(oo[i])).get('Id'));
			}
		} catch (Exception ex) {
			try { 
				// try the SObject first
				obj.put(field, ((SObject)(v)).get('Id'));
			} catch (Exception ex2) {
				// finally the object itself - this will throw an error if the datatype doesn't match
				obj.put(field, v);
			}
		}	
	}

	public static void setRecordType(SObject obj) {
		Schema.DescribeSObjectResult objDR = obj.getSObjectType().getDescribe();
		String otn = objDR.getName();

		List<Schema.RecordTypeInfo> recordTypes;
		if (defaultRecTypeCache.containsKey( otn )) {
			obj.put('RecordTypeId', defaultRecTypeCache.get( otn ));
		} else {
			recordTypes = objDR.getRecordTypeInfos();
			if (recordTypes.size() > 1) { // all objects have default Master type
				for (Schema.RecordTypeInfo recordType : recordTypes) {
					if (recordType.isAvailable() && recordType.isDefaultRecordTypeMapping()) {
						obj.put('RecordTypeId', recordType.getRecordTypeId());
						defaultRecTypeCache.put( otn, recordType.getRecordTypeId() );
						break;
					}
				}
			}
		}
	}
}