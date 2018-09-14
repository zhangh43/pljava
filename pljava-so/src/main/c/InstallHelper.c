/*
 * Copyright (c) 2015 Tada AB and other contributors, as listed below.
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the The BSD 3-Clause License
 * which accompanies this distribution, and is available at
 * http://opensource.org/licenses/BSD-3-Clause
 *
 * Contributors:
 *   Chapman Flack
 */
#include <postgres.h>
#if PG_VERSION_NUM >= 90300
#include <access/htup_details.h>
#else
#include <access/htup.h>
#endif
#include <access/xact.h>
#include <catalog/pg_language.h>
#include <catalog/pg_proc.h>
#if PG_VERSION_NUM >= 90100
#include <commands/extension.h>
#endif
#include <commands/portalcmds.h>
#include <executor/spi.h>
#include <miscadmin.h>
#include <libpq/libpq-be.h>
#include <tcop/pquery.h>
#include <utils/builtins.h>
#include <utils/lsyscache.h>
#include <utils/memutils.h>
#include <utils/syscache.h>

#if PG_VERSION_NUM < 90000
#define SearchSysCache1(cid, k1) SearchSysCache(cid, k1, 0, 0, 0)
#define GetSysCacheOid1(cid, k1) GetSysCacheOid(cid, k1, 0, 0, 0)
#endif

#include "pljava/InstallHelper.h"
#include "pljava/Backend.h"
#include "pljava/Function.h"
#include "pljava/Invocation.h"
#include "pljava/JNICalls.h"
#include "pljava/PgObject.h"
#include "pljava/type/String.h"

#define pg_unreachable() abort()

/*
 * CppAsString2 first appears in PG8.4.  Once the compatibility target reaches
 * 8.4, this fallback will not be needed.
 */
#ifndef CppAsString2
#define CppAsString2(x) CppAsString(x)
#endif

/*
 * Before 9.1, there was no creating_extension. Before 9.5, it did not have
 * PGDLLIMPORT and so was not visible in Windows. In either case, just define
 * it to be false, but also define CREATING_EXTENSION_HACK if on Windows and
 * it needs to be tested for in some roundabout way.
 */
#if PG_VERSION_NUM < 90100 || defined(_MSC_VER) && PG_VERSION_NUM < 90500
#define creating_extension false
#if PG_VERSION_NUM >= 90100
#define CREATING_EXTENSION_HACK
#endif
#endif

#ifndef PLJAVA_SO_VERSION
#error "PLJAVA_SO_VERSION needs to be defined to compile this file."
#else
#define SO_VERSION_STRING CppAsString2(PLJAVA_SO_VERSION)
#endif

/*
 * The name of the table the extension scripts will create to pass information
 * here. The table name is phrased as an error message because it will appear
 * in one, if installation did not happen because the library had already been
 * loaded.
 */
#define LOADPATH_TBL_NAME "see doc: do CREATE EXTENSION PLJAVA in new session"

static jclass s_InstallHelper_class;
static jmethodID s_InstallHelper_hello;
static jmethodID s_InstallHelper_groundwork;

static bool extensionExNihilo = false;

static void checkLoadPath( bool *livecheck);
static void getExtensionLoadPath();

char const *pljavaLoadPath = NULL;

bool pljavaLoadingAsExtension = false;

Oid pljavaTrustedOid = InvalidOid;

Oid pljavaUntrustedOid = InvalidOid;

bool pljavaViableXact()
{
	return IsTransactionState() && 'E' != TransactionBlockStatusCode();
}

char *pljavaDbName()
{
	return MyProcPort->database_name;
}

char const *pljavaClusterName()
{
	/*
	 * If PostgreSQL isn't at least 9.5, there can't BE a cluster name, and if
	 * it is, then there's always one (even if it is an empty string), so
	 * PG_GETCONFIGOPTION is safe.
	 */
#if PG_VERSION_NUM < 90500
	return "";
#else
	return PG_GETCONFIGOPTION("cluster_name");
#endif
}

void pljavaCheckExtension( bool *livecheck)
{
	if ( ! creating_extension )
	{
		checkLoadPath( livecheck);
		return;
	}
	if ( NULL != livecheck )
	{
		*livecheck = true;
		return;
	}
	getExtensionLoadPath();
	if ( NULL != pljavaLoadPath )
		pljavaLoadingAsExtension = true;
}

/*
 * As for pljavaCheckExtension, livecheck == null when called from _PG_init
 * (when the real questions are whether PL/Java itself is being loaded, from
 * what path, and whether or not as an extension). When livecheck is not null,
 * PL/Java is already alive and the caller wants to know if an extension is
 * being created for some other reason. That wouldn't even involve this
 * function, except for the need to work around creating_extension visibility
 * on Windows. So if livecheck isn't null, this function only needs to proceed
 * as far as the CREATING_EXTENSION_HACK and then return.
 */
static void checkLoadPath( bool *livecheck)
{
	List *l;
	Node *ut;
	LoadStmt *ls;

#ifndef CREATING_EXTENSION_HACK
	if ( NULL != livecheck )
		return;
#endif
	if ( NULL == ActivePortal )
		return;
	l = ActivePortal->stmts;
	if ( NULL == l )
		return;
	if ( 1 < list_length( l) )
		elog(DEBUG2, "ActivePortal lists %d statements", list_length( l));
	ut = (Node *)linitial(l);
	if ( NULL == ut )
	{
		elog(DEBUG2, "got null for first statement from ActivePortal");
		return;
	}
	if ( T_LoadStmt != nodeTag(ut) )
#ifdef CREATING_EXTENSION_HACK
		if ( T_CreateExtensionStmt == nodeTag(ut) )
		{
			if ( NULL != livecheck )
			{
				*livecheck = true;
				return;
			}
			getExtensionLoadPath();
			if ( NULL != pljavaLoadPath )
				pljavaLoadingAsExtension = true;
		}
#endif
		return;
	if ( NULL != livecheck )
		return;
	ls = (LoadStmt *)ut;
	if ( NULL == ls->filename )
	{
		elog(DEBUG2, "got null for a LOAD statement's filename");
		return;
	}
	pljavaLoadPath =
		(char const *)MemoryContextStrdup(TopMemoryContext, ls->filename);
}

static void getExtensionLoadPath()
{
	MemoryContext curr;
	Datum dtm;
	bool isnull;
	StringInfoData buf;

	/*
	 * Check whether sqlj.loadpath exists before querying it. I would more
	 * happily just PG_CATCH() the error and compare to ERRCODE_UNDEFINED_TABLE
	 * but what's required to make that work right is "not terribly well
	 * documented, but the exception-block handling in plpgsql provides a
	 * working model" and that code is a lot more fiddly than you would guess.
	 */
	if ( InvalidOid == get_relname_relid(LOADPATH_TBL_NAME,
		GetSysCacheOid1(NAMESPACENAME, CStringGetDatum("sqlj"))) )
		return;

	SPI_connect();
	curr = CurrentMemoryContext;
	initStringInfo(&buf);
	appendStringInfo(&buf, "SELECT path, exnihilo FROM sqlj.%s",
		quote_identifier(LOADPATH_TBL_NAME));
	if ( SPI_OK_SELECT == SPI_execute(buf.data,	true, 1) && 1 == SPI_processed )
	{
		MemoryContextSwitchTo(TopMemoryContext);
		pljavaLoadPath = (char const *)SPI_getvalue(
			SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1);
		MemoryContextSwitchTo(curr);
		dtm = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 2,
			&isnull);
		if ( isnull )
			elog(ERROR, "defect in CREATE EXTENSION script");
		extensionExNihilo = DatumGetBool(dtm);
	}
	SPI_finish();
}

/*
 * Given the Oid of a function believed to be implemented with PL/Java, return
 * the dynamic library path of its language's function-call-handler function
 * (which will of course be PL/Java's library path, if the original belief was
 * correct) ... or NULL if the original belief can't be sustained.
 *
 * If a string is returned, it has been palloc'd in the current context.
 */
char *pljavaFnOidToLibPath(Oid fnOid)
{
	bool isnull;
	HeapTuple procTup;
	Form_pg_proc procStruct;
	Oid langId;
	HeapTuple langTup;
	Form_pg_language langStruct;
	Oid handlerOid;
	Datum probinattr;
	char *probinstring;

	/*
	 * It is proposed that fnOid refers to a function implemented with PL/Java.
	 */
	procTup = SearchSysCache1(PROCOID, ObjectIdGetDatum(fnOid));
	if (!HeapTupleIsValid(procTup))
		elog(ERROR, "cache lookup failed for function %u", fnOid);
	procStruct = (Form_pg_proc) GETSTRUCT(procTup);
	langId = procStruct->prolang;
	ReleaseSysCache(procTup);
	/*
	 * The langId just obtained (if the proposition is proved correct by
	 * surviving the further steps below) is a langId for PL/Java. It could
	 * be cached to simplify later checks. Not today.
	 */
	if ( langId == INTERNALlanguageId || langId == ClanguageId
		|| langId == SQLlanguageId )
		return NULL; /* these can be eliminated without searching syscache. */

	/*
	 * So far so good ... the function thought to be done in PL/Java has at
	 * least not turned out to be internal, or C, or SQL. So, next, look up its
	 * language, and get the Oid for its function call handler.
	 */
	langTup = SearchSysCache1(LANGOID, ObjectIdGetDatum(langId));
	if (!HeapTupleIsValid(langTup))
		elog(ERROR, "cache lookup failed for language %u", langId);
	langStruct = (Form_pg_language) GETSTRUCT(langTup);
	handlerOid = langStruct->lanplcallfoid;
	ReleaseSysCache(langTup);
	/*
	 * PL/Java has certainly got a function call handler, so if this language
	 * hasn't, PL/Java it's not.
	 */
	if ( InvalidOid == handlerOid )
		return NULL;

	/*
	 * Da capo al coda ... handlerOid is another function to be looked up.
	 */
	procTup = SearchSysCache1(PROCOID, ObjectIdGetDatum(handlerOid));
	if (!HeapTupleIsValid(procTup))
		elog(ERROR, "cache lookup failed for function %u", handlerOid);
	procStruct = (Form_pg_proc) GETSTRUCT(procTup);
	/*
	 * If the call handler's not a C function, this isn't PL/Java....
	 */
	if ( ClanguageId != procStruct->prolang )
		return NULL;

	/*
	 * Now that the handler is known to be a C function, it should have a
	 * probinattr containing the name of its dynamic library.
	 */
	probinattr =
		SysCacheGetAttr(PROCOID, procTup, Anum_pg_proc_probin, &isnull);
	if ( isnull )
		elog(ERROR, "null probin for C function %u", handlerOid);
	probinstring = /* TextDatumGetCString(probinattr); */
		DatumGetCString(DirectFunctionCall1(textout, probinattr)); /*archaic*/
	ReleaseSysCache(procTup);

	/*
	 * About this result: if the caller was initialization code passing a fnOid
	 * known to refer to PL/Java (because it was the function occasioning the
	 * call), then this string can be saved as the dynamic library name for
	 * PL/Java. Otherwise, it is the library name for whatever language is used
	 * by the fnOid passed in, and can be compared to such a saved value to
	 * determine whether that is a PL/Java function or not.
	 */
	return probinstring;
}

bool InstallHelper_isPLJavaFunction(Oid fn)
{
	char *itsPath;
	char *pljPath;
	bool result = false;

	itsPath = pljavaFnOidToLibPath(fn);
	if ( NULL == itsPath )
		return false;

	if ( NULL == pljavaLoadPath )
	{
		pljPath = NULL;
		if ( InvalidOid != pljavaTrustedOid )
			pljPath = pljavaFnOidToLibPath(pljavaTrustedOid);
		if ( NULL == pljPath && InvalidOid != pljavaUntrustedOid )
			pljPath = pljavaFnOidToLibPath(pljavaUntrustedOid);
		if ( NULL == pljPath )
		{
			elog(WARNING, "unable to determine PL/Java's load path");
			goto finally;
		}
		pljavaLoadPath =
			(char const *)MemoryContextStrdup(TopMemoryContext, pljPath);
		pfree(pljPath);
	}
	result = 0 == strcmp(itsPath, pljavaLoadPath);
finally:
	pfree(itsPath);
	return result;
}

char const *InstallHelper_defaultClassPath(char *pathbuf)
{
	char * const pbend = pathbuf + MAXPGPATH;
	char *pbp = pathbuf;
	size_t remaining;
	size_t verlen = strlen(SO_VERSION_STRING);

	get_share_path(my_exec_path, pathbuf);
	join_path_components(pathbuf, pathbuf, "pljava");
	join_path_components(pathbuf, pathbuf, "pljava-");

	for ( ; pbp < pbend && '\0' != *pbp ; ++ pbp )
		;
	if ( pbend == pbp )
		return NULL;

	remaining = pbend - pbp;
	if ( remaining < verlen + 5 )
		return NULL;

	snprintf(pbp, remaining, "%s.jar", SO_VERSION_STRING);
	return pathbuf;
}

char *InstallHelper_hello()
{
	char pathbuf[MAXPGPATH];
	Invocation ctx;
	jstring nativeVer;
	jstring user;
	jstring dbname;
	jstring clustername;
	jstring ddir;
	jstring ldir;
	jstring sdir;
	jstring edir;
	jstring greeting;
	char *greetingC;
	char const *clusternameC = pljavaClusterName();

	Invocation_pushBootContext(&ctx);
	nativeVer = String_createJavaStringFromNTS(SO_VERSION_STRING);
	elog(LOG, "511test1:%s",MyProcPort->user_name);
	user = String_createJavaStringFromNTS(MyProcPort->user_name);
	elog(LOG, "511test2:%s",MyProcPort->database_name);
	dbname = String_createJavaStringFromNTS(MyProcPort->database_name);
	elog(LOG, "511test3:%s",clusternameC);
	if ( '\0' == *clusternameC )
		clustername = NULL;
	else
		clustername = String_createJavaStringFromNTS(clusternameC);

	elog(LOG, "511test4:%s",DataDir);
	ddir = String_createJavaStringFromNTS(DataDir);

	get_pkglib_path(my_exec_path, pathbuf);
	ldir = String_createJavaStringFromNTS(pathbuf);
	elog(LOG, "511test5:%s",pathbuf);
	get_share_path(my_exec_path, pathbuf);
	sdir = String_createJavaStringFromNTS(pathbuf);
	elog(LOG, "511test6:%s",pathbuf);
	get_etc_path(my_exec_path, pathbuf);
	edir = String_createJavaStringFromNTS(pathbuf);
	elog(LOG, "511test7:%s",pathbuf);
	greeting = JNI_callStaticObjectMethod(
		s_InstallHelper_class, s_InstallHelper_hello,
		nativeVer, user, dbname, clustername, ddir, ldir, sdir, edir);

	elog(LOG, "511test8");
	JNI_deleteLocalRef(nativeVer);
	JNI_deleteLocalRef(user);
	JNI_deleteLocalRef(dbname);
	if ( NULL != clustername )
		JNI_deleteLocalRef(clustername);
	JNI_deleteLocalRef(ddir);
	JNI_deleteLocalRef(ldir);
	JNI_deleteLocalRef(sdir);
	JNI_deleteLocalRef(edir);
	greetingC = String_createNTS(greeting);
	JNI_deleteLocalRef(greeting);
	Invocation_popBootContext();
	return greetingC;
}

void InstallHelper_groundwork()
{
	Invocation ctx;
	Invocation_pushInvocation(&ctx, false);
	ctx.function = Function_INIT_WRITER;
	PG_TRY();
	{
		char const *lpt = LOADPATH_TBL_NAME;
		char const *lptq = quote_identifier(lpt);
		jstring pljlp = String_createJavaStringFromNTS(pljavaLoadPath);
		jstring jlpt = String_createJavaStringFromNTS(lpt);
		jstring jlptq = String_createJavaStringFromNTS(lptq);
		if ( lptq != lpt )
			pfree((void *)lptq);
		JNI_callStaticVoidMethod(
			s_InstallHelper_class, s_InstallHelper_groundwork,
			pljlp, jlpt, jlptq,
			pljavaLoadingAsExtension ? JNI_TRUE : JNI_FALSE,
			extensionExNihilo ? JNI_TRUE : JNI_FALSE);
		JNI_deleteLocalRef(pljlp);
		JNI_deleteLocalRef(jlpt);
		JNI_deleteLocalRef(jlptq);
		Invocation_popInvocation(false);
	}
	PG_CATCH();
	{
		Invocation_popInvocation(true);
		PG_RE_THROW();
	}
	PG_END_TRY();
}

void InstallHelper_initialize()
{
	s_InstallHelper_class = (jclass)JNI_newGlobalRef(PgObject_getJavaClass(
		"org/postgresql/pljava/internal/InstallHelper"));
	s_InstallHelper_hello = PgObject_getStaticJavaMethod(s_InstallHelper_class,
		"hello",
		"(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;"
		"Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;"
		"Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	s_InstallHelper_groundwork = PgObject_getStaticJavaMethod(
		s_InstallHelper_class, "groundwork",
		"(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZ)V");
}
