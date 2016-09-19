/*
 * Copyright (c) 2004, 2005, 2006 TADA AB - Taby Sweden
 * Distributed under the terms shown in the file COPYRIGHT
 * found in the root folder of this project or at
 * http://eng.tada.se/osprojects/COPYRIGHT.html
 *
 * @author Thomas Hallgren
 */
#include <postgres.h>
#include <miscadmin.h>
#include "org_postgresql_pljava_internal_Session.h"
#include "pljava/Session.h"
#include "pljava/type/AclId.h"

#define pg_unreachable() abort()


extern void Session_initialize(void);
void Session_initialize(void)
{
	JNINativeMethod methods[] = {
		{
		"_setUser",
		"(Lorg/postgresql/pljava/internal/AclId;Z)Z",
	  	Java_org_postgresql_pljava_internal_Session__1setUser
		},
		{ 0, 0, 0 }};

	PgObject_registerNatives("org/postgresql/pljava/internal/Session", methods);
}

/****************************************
 * JNI methods
 ****************************************/
/*
 * Class:     org_postgresql_pljava_internal_Session
 * Method:    _setUser
 * Signature: (Lorg/postgresql/pljava/internal/AclId;Z)Z
 */
JNIEXPORT jboolean JNICALL
Java_org_postgresql_pljava_internal_Session__1setUser(
	JNIEnv* env, jclass cls, jobject aclId, jboolean isLocalChange)
{
	/* No error checking since this might be a restore of user in
	 * a finally block after an exception.
	 */
	BEGIN_NATIVE_NO_ERRCHECK
	SetUserIdAndContext(AclId_getAclId(aclId), true);
	END_NATIVE
	return JNI_TRUE;
}

