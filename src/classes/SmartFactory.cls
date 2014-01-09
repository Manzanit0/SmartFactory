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
	public static boolean FillAllFields = false;

	// Key : SobjectAPIName  For ex. Account 
	// Value : Map<String, Schema.SObjectField>, field map (k:fieldname, v:Schema.Sobjectfield)
	public static Profile userProfile = [Select Id from Profile where Name = 'System Administrator'];

	private static final Map<String, Map<String, Schema.SObjectField>> FieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
	private static final Map<String, Id> defaultRecTypeCache = new Map<String, Id>();
	private static final Map<String, Id> referenceObjectCache = new Map<String, Id>();
	private static final Map<String, Schema.SObjectType> GlobalDescribe = Schema.getGlobalDescribe();

	// Key: sobject.field
	// Value: first picklist value
	private static final Map<String, String> DefaultPicklistValue = new Map<String, String>();

	// can't map by Schema.sObjectType, use object name String instead
	public static map<String, set<String>> ExcludedFields = new map<String, set<String>>{
		'All' => new set<String>{'OwnerId', 'LastModifiedById', 'CreatedById', 'LastModifiedDate', 'CreatedDate'},
		'Account' => new set<String>{'FirstName', 'LastName'},
		'User' => new set<String>{'IsActive','DelegatedApproverId','CallCenterId','ContactId','DelegatedApproverId','ManagerId','UserRoleId','FederationIdentifier'}
	};

	// to fill nillable fields, specify them here
	public static map<String, set<String>> IncludedFields = new map<String, set<String>>();

	// various simplified signatures for flexibility and backward compatibility
	public static SObject createSObject(String objectType) {
		return createSObject(objectType, false, 1, null);
	}

	public static SObject createSObject(String objectType, Map<String, Object> fieldValues) {
		return createSObject(objectType, false, 1, fieldValues);
	}

	public static SObject createSObject(String objectType, boolean cascade) {
		return createSObject(objectType, cascade, 1, null);
	}

	public static SObject createSObject(String objectType, boolean cascade, Integer counter) {
		return createSObject(objectType, cascade, counter, null);
	}

	public static SObject createSObject(String objectType, boolean cascade, Map<String, Object> fieldValues) {
		return createSObject(objectType, cascade, 1, fieldValues);
	}

	// full service signature
	// by passing in fieldValues, you can set defaults for any fields you like (data types must match)
	// for reference fields, fieldValues can optionally be actual parent objects to which you want the new objects to be related
	public static SObject createSObject(String objectType, boolean cascade, Integer counter, Map<String, Object> fieldValues) {
		//System.debug('Creating ' + objectType);
		Schema.sObjectType token = GlobalDescribe.get(objectType);
		if (token == null) {
			throw new UnsupportedObjectTypeException('Unsupported ObjectType ' + objectType);
		}

		SObject obj = token.newSObject();		

		set<String> exclude = new set<String>(); 
		if (ExcludedFields.get('All') != null)
			exclude.addAll(ExcludedFields.get('All'));
		if (ExcludedFields.get(objectType) != null)
			exclude.addAll(ExcludedFields.get(objectType));
		set<String> include = new set<String>(); 
		if (IncludedFields.get(objectType) != null)
			include.addAll(IncludedFields.get(objectType));		
		if (fieldValues != null)
			include.addAll(fieldValues.keyset());		

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

	public static List<SObject> createSObjectList(String objectType, boolean cascade, Integer numberOfObjects) {
		return createSObjectList(objectType, cascade, numberOfObjects, null);
	}

	// main method to create a list of objects
	// fieldValues here work as above, but can optionally be a list of objects, in which case they will each be used 
	// in some of the objects created (see the test class for examples)
	public static List<SObject> createSObjectList(String objectType, boolean cascade, Integer numberOfObjects, Map<String, Object> fieldValues) {
		List<SObject> sos = new List<SObject>();
		for( Integer i=0; i<numberOfObjects; i++ )
			sos.add(createSObject(objectType, cascade, i, fieldValues));
		return sos;  
	}

	/**
		Returns a field map for a given sobject. 

		Note : this method is kept public for Test cases to share the same field map info, without requiring a field desribe.

		@param objectType sobject api name for ex. Account
		@returns FieldMap [Key:FieldName,Value:Schema.SObjectField]
	*/
	public static  Map<String, Schema.SObjectField> fieldMapFor(String objectType) {
		Map<String, Schema.SObjectField> fieldMap = null;
		String normalizedObjectType = objectType.toLowerCase();

		if (FieldMapCache.containsKey(normalizedObjectType)) {
			fieldMap = FieldMapCache.get(normalizedObjectType);
		} else {
			fieldMap = GlobalDescribe.get(objectType).getDescribe().fields.getMap();
			// cache it for next use
			FieldMapCache.put(normalizedObjectType, fieldMap);
		}

		return fieldMap;
	}

	static String getDefaultPicklistValue(SObject obj, Schema.DescribeFieldResult fieldDescribe) {
		String key = obj.getSObjectType() + '.' + fieldDescribe.getName();

		if (!DefaultPicklistValue.containsKey(key)) {
			List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();
			String value = entries.size() > 0 ? entries[0].getValue() : null;
			DefaultPicklistValue.put(key, value);
		}

		return DefaultPicklistValue.get(key);
	}
/*
	static boolean isExcludedField(Schema.DescribeFieldResult fieldDescribe) {
		return ExcludedFields.get('All').contains(fieldDescribe.getName());
	}

	static boolean isExcludedField(SObject obj, Schema.DescribeFieldResult fieldDescribe) {
		set<String> fields = ExcludedFields.get(obj.getSObjectType().getDescribe().getName());
		return fields == null ? false : fields.contains(fieldDescribe.getName());
	}

	static boolean isIncludedField(SObject obj, Schema.DescribeFieldResult fieldDescribe) {
		set<String> fields = includedFields.get(obj.getSObjectType().getDescribe().getName());
		return fields == null ? false : fields.contains(fieldDescribe.getName());
	}
*/

	static final Boolean isPersonAccountEnabled = ( fieldMapFor('Account').get('IsPersonAccount') != null );
	static final set<String> skipPersonAccountFields = new set<string>{ 'Salutation' };
	
	static boolean isPersonAccountField(Schema.DescribeFieldResult fieldDescribe) {
        Boolean CustomPerson = fieldDescribe.isCustom() && fieldDescribe.getName().endsWith('pc');
        Boolean StandardPerson = !fieldDescribe.isCustom() && fieldDescribe.getName().startsWith('Person');

        return (isPersonAccountEnabled && (CustomPerson || StandardPerson || skipPersonAccountFields.contains(fieldDescribe.getName())));
	}

	static void setFieldValue(SObject obj, Schema.SObjectField field, boolean cascade, Integer counter, Set<String> include, Set<String> exclude, Map<String, Object> fieldValues) {
		Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
		Schema.DisplayType ft = fieldDescribe.getType();
		String fn = fieldDescribe.getName();
		
		if (fieldDescribe.isCreateable() && 
				(
					(
						!exclude.contains(fn) &&
						(!fieldDescribe.isNillable() || FillAllFields || (ft == Schema.DisplayType.Reference && cascade)) && 
						(!isPersonAccountEnabled || !isPersonAccountField(fieldDescribe))
					) 
				|| include.contains(fn))
			) {

			//System.debug(LOGGINGLEVEL.warn, obj.getSObjectType().getDescribe().getName() + '.' + fn + ': ' + ft.name());

			// look for a default value provided for this field
			if (fieldValues != null && fieldValues.containsKey(fn)) {

				// set the field to the default provided, whether it is a value or a list of values
				// also supports getting the Id of an sobject if that is what is provided as a default
				setFieldOverrideValue( obj, field, fieldValues.get(fn), counter );

			} else if (ft == Schema.DisplayType.String) {

				if (fn == 'CommunityNickname') { 
					obj.put(field, 't'+ string.valueof(math.roundtolong(math.random()*1000000)) ); 
				} else if (fn == 'Username') { 
					obj.put(field, 'test'+ string.valueof(Userinfo.getOrganizationId())+ string.valueof(math.roundtolong(math.random()*1000000))+ string.valueof(Datetime.now()).replace('-','').replace(':','').replace(' ','')+'@test.com'); // was a@a.com
				} else {
					String s = (fn + counter.format());
					obj.put(field, (fieldDescribe.getLength() > s.length()) ? s : counter.format()); 
				}
			} else if (ft == Schema.DisplayType.Picklist) {
				obj.put(field, getDefaultPicklistValue(obj, fieldDescribe));
			} else if (ft == Schema.DisplayType.Integer) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Boolean) {
				obj.put(field, false);
			} else if (ft == Schema.DisplayType.Currency) {
				obj.put(field, counter);
			} else if (ft == Schema.DisplayType.Date) {
				obj.put(field, Date.today());
			} else if (ft == Schema.DisplayType.DateTime) {
				obj.put(field, DateTime.now());
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
					//System.debug(LOGGINGLEVEL.warn, 'Creating reference to ' + referenceObjectType + ' for field ' + objName + '.' + fn);
					if (referenceObjectCache.containsKey(referenceObjectType)) {
						obj.put(field, referenceObjectCache.get(referenceObjectType));
					} else {
						SObject reference = createSObject(referenceObjectType, fieldValues);
						insert reference;
						obj.put(field, reference.Id);
						referenceObjectCache.put(referenceObjectType, reference.Id);
					}
				}
			} else if (ft == Schema.DisplayType.MultiPicklist) {
				obj.put(field, getDefaultPicklistValue(obj, fieldDescribe));
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
				obj.put(field, blob.valueOf(counter.format()));
			//} else if (ft == Schema.DisplayType.Id) {
				//System.debug('Id field ' + fn);
			} else {
				System.debug('Unhandled field type ' + ft);
			}
		}	
	}

	static void setFieldOverrideValue( SObject obj, Schema.SObjectField field, Object v, Integer counter ) {

		// first try to cast the object to a list of objects and use the right one
		// failing that, assume it is a single object or value
		try { 
			list<Object> oo = (list<Object>)(v);
			Integer i = (counter < oo.size()) ? counter : Math.mod(counter, oo.size());
			try { 
				obj.put(field, oo[i]);
			} catch (Exception ex1) {
				// if it isn't a value, try it as an sObject
				obj.put(field, ((sObject)(oo[i])).get('Id'));
			}
		} catch (Exception ex) {
			try { 
				// try the sObject first
				obj.put(field, ((sObject)(v)).get('Id'));
			} catch (Exception ex2) {
				// finally the object itself - this will throw an error if the datatype doesn't match
				obj.put(field, v);
			}
		}	
	}								

	static void setRecordType(SObject obj) {
		Schema.DescribeSObjectResult objDR = obj.getSObjectType().getDescribe();
		String otn = objDR.getName();

		List<Schema.RecordTypeInfo> recordTypes;
		if (defaultRecTypeCache.containsKey( otn )) {
			obj.put('RecordTypeId', defaultRecTypeCache.get( otn ));
		} else {
			recordTypes = objDR.getRecordTypeInfos();
			if (recordTypes.size() > 1) { // all objects have default Master type
				//System.debug('RecordTypes ' + recordTypes);
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