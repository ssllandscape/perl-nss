#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <string.h>

#if defined(XP_UNIX)
#include <unistd.h>
#endif

// #include "prerror.h"

#include "pk11func.h"
#include "seccomon.h"
#include "secmod.h"
#include "secitem.h"
#include "secder.h"
#include "cert.h"
#include "ocsp.h"


/* #include <stdlib.h> */
/* #include <errno.h> */
/* #include <fcntl.h> */
/* #include <stdarg.h> */

#include "nspr.h"
#include "plgetopt.h"
#include "prio.h"
#include "nss.h"

/* #include "vfyutil.h" */

#define RD_BUF_SIZE (60 * 1024)


/* fake our package name */
typedef CERTCertificate* Crypt__NSS__Certificate;


//---- Beginning here this is a direct copy from NSS vfychain.c

#define REVCONFIG_TEST_UNDEFINED      0
#define REVCONFIG_TEST_LEAF           1
#define REVCONFIG_TEST_CHAIN          2
#define REVCONFIG_METHOD_CRL          1
#define REVCONFIG_METHOD_OCSP         2

#define REV_METHOD_INDEX_MAX  4

typedef struct RevMethodsStruct {
    uint testType;
    char *testTypeStr;
    uint testFlags;
    char *testFlagsStr;
    uint methodType;
    char *methodTypeStr;
    uint methodFlags;
    char *methodFlagsStr;
} RevMethods;

RevMethods revMethodsData[REV_METHOD_INDEX_MAX];

SECStatus
configureRevocationParams(CERTRevocationFlags *flags)
{
   int i;
   uint testType = REVCONFIG_TEST_UNDEFINED;
   static CERTRevocationTests *revTests = NULL;
   PRUint64 *revFlags;

   for(i = 0;i < REV_METHOD_INDEX_MAX;i++) {
       if (revMethodsData[i].testType == REVCONFIG_TEST_UNDEFINED) {
           continue;
       }
       if (revMethodsData[i].testType != testType) {
           testType = revMethodsData[i].testType;
           if (testType == REVCONFIG_TEST_CHAIN) {
               revTests = &flags->chainTests;
           } else {
               revTests = &flags->leafTests;
           }
           revTests->number_of_preferred_methods = 0;
           revTests->preferred_methods = 0;
           revFlags = revTests->cert_rev_flags_per_method;
       }
       /* Set the number of the methods independently to the max number of
        * methods. If method flags are not set it will be ignored due to
        * default DO_NOT_USE flag. */
       revTests->number_of_defined_methods = cert_revocation_method_count;
       revTests->cert_rev_method_independent_flags |=
           revMethodsData[i].testFlags;
       if (revMethodsData[i].methodType == REVCONFIG_METHOD_CRL) {
           revFlags[cert_revocation_method_crl] =
               revMethodsData[i].methodFlags;
       } else if (revMethodsData[i].methodType == REVCONFIG_METHOD_OCSP) {
           revFlags[cert_revocation_method_ocsp] =
               revMethodsData[i].methodFlags;
       }
   }
   return SECSuccess;
}

//---- end direct copy from vfychain.c

SECStatus sv_to_item(SV* certSv, SECItem* dst) {
  STRLEN len;
  char *cert;

  cert = SvPV(certSv, len);

  if ( len <= 0 ) {
    return SECFailure;
  }

  dst->len = 0;
  dst->data = NULL;

  dst->data = (unsigned char*)PORT_Alloc(len);
  PORT_Memcpy(dst->data, cert, len);
  dst->len = len;

  return SECSuccess;
}

SV* item_to_sv(SECItem* item) {
  return newSVpvn((const char*) item->data, item->len);
}

MODULE = Crypt::NSS    PACKAGE = Crypt::NSS

PROTOTYPES: DISABLE

BOOT:
{
  
  PR_Init( PR_SYSTEM_THREAD, PR_PRIORITY_NORMAL, 1);

  //SECU_RegisterDynamicOids();
}

void
_init_nodb()

  PREINIT:
  SECStatus secStatus;
  
  CODE:
  secStatus = NSS_NoDB_Init(NULL);
  //SECMOD_AddNewModule("Builtins", DLL_PREFIX"nssckbi."DLL_SUFFIX, 0, 0);

  if (secStatus != SECSuccess) {
    croak("NSS init");
  }

  
void
_init_db(string)
  SV* string;

  PREINIT:
  SECStatus secStatus;
  char* path;  

  CODE:
  path = SvPV_nolen(string);

  secStatus = NSS_InitReadWrite(path);
  //SECMOD_AddNewModule("Builtins", DLL_PREFIX"nssckbi."DLL_SUFFIX, 0, 0);

  if (secStatus != SECSuccess) {
    croak("NSS init");
  }
  

SV*
add_cert_to_db(cert, string)
  Crypt::NSS::Certificate cert;
  SV* string;

  PREINIT:
  PK11SlotInfo *slot = NULL;
  CERTCertTrust *trust = NULL;
  CERTCertDBHandle *defaultDB;
  SECStatus rv;
  char* nick;

  CODE:
  RETVAL = 0;
  nick = SvPV_nolen(string);

  defaultDB = CERT_GetDefaultCertDB();

  slot = PK11_GetInternalKeySlot();
  trust = (CERTCertTrust *)PORT_ZAlloc(sizeof(CERTCertTrust));
  if (!trust) {
    croak("Could not create trust");
  }

  rv = CERT_DecodeTrustString(trust, "C");
  if (rv) {
    croak("unable to decode trust string");
  }

  rv = PK11_ImportCert(slot, cert, CK_INVALID_HANDLE, nick, PR_FALSE);
  if (rv != SECSuccess) {
    PRErrorCode err = PR_GetError();
    croak( "could not add certificate to db %d = %s\n",
	         err, PORT_ErrorToString(err));
  }

  rv = CERT_ChangeCertTrust(defaultDB, cert, trust);
  if (rv != SECSuccess) {
    croak("Could not change cert trust");
  }

  PORT_Free(trust);

  RETVAL = newSViv(1);   
  

  OUTPUT: 
  RETVAL

MODULE = Crypt::NSS    PACKAGE = Crypt::NSS::Certificate

SV*
accessor(cert)
  Crypt::NSS::Certificate cert  

  ALIAS:
  subject = 1
  issuer = 2  
  serial_raw = 3
  notBefore = 5
  notAfter = 6
  version = 8

  PREINIT:

  CODE:

  if ( ix == 1 ) {
    RETVAL = newSVpvf("%s", cert->subjectName);
  } else if ( ix == 2 ) {
    RETVAL = newSVpvf("%s", cert->issuerName);
  } else if ( ix == 3 ) {
    RETVAL = item_to_sv(&cert->serialNumber);
  } else if ( ix == 5 || ix == 6 ) {
    int64 time;
    SECStatus rv;
    char *timeString;
    PRExplodedTime printableTime; 

    if ( ix == 5 ) 
    	rv = DER_UTCTimeToTime(&time, &cert->validity.notBefore);
    else if ( ix == 6 )    
	rv = DER_UTCTimeToTime(&time, &cert->validity.notAfter);
    else
        croak("not possible");

    if (rv != SECSuccess)
      croak("Could not parse time");

    PR_ExplodeTime(time, PR_GMTParameters, &printableTime);
    timeString = PORT_Alloc(256);
    if ( ! PR_FormatTime(timeString, 256, "%a %b %d %H:%M:%S %Y", &printableTime) ) {
      croak("Could not format time string");
    }

    RETVAL = newSVpvf("%s", timeString);
    PORT_Free(timeString);
  } else if ( ix == 8 ) {
    // if version is not specified it it 1 (0).
    int version = cert->version.len ? DER_GetInteger(&cert->version) : 0;
    RETVAL = newSViv(version+1);
  } else {
    croak("Unknown accessor %d", ix);
  }


  OUTPUT:
  RETVAL

SV*
old_verify(cert)
  Crypt::NSS::Certificate cert;

  ALIAS:
  old_verify_pkix = 1

  PREINIT:
  SECStatus secStatus;
  PRTime time = 0;
  CERTCertDBHandle *defaultDB;

  CODE:
  defaultDB = CERT_GetDefaultCertDB();

  if (!time)
    time = PR_Now();

  if ( ix == 1 ) 
    CERT_SetUsePKIXForValidation(PR_TRUE);

  secStatus = CERT_VerifyCertificate(defaultDB, cert,
                                     PR_FALSE, // check sig 
				     certificateUsageSSLServer,
				     time,
				     0,
				     0, NULL);

  if (secStatus != SECSuccess ) {
    RETVAL = &PL_sv_no;
  } else {
    RETVAL = &PL_sv_yes;
  }  

  OUTPUT:
  RETVAL

SV*
verify(cert)
  Crypt::NSS::Certificate cert;

  PREINIT:
  SECStatus secStatus;
  PRBool certFetching = PR_FALSE; // automatically get AIA certs

  static CERTValOutParam cvout[4];
  static CERTValInParam cvin[6];
  int inParamIndex = 0;
  static CERTRevocationFlags rev;
  static PRUint64 revFlagsLeaf[2];
  static PRUint64 revFlagsChain[2];

  CODE:


  cvin[inParamIndex].type = cert_pi_useAIACertFetch;
  cvin[inParamIndex].value.scalar.b = certFetching;
  inParamIndex++;
  
  rev.leafTests.cert_rev_flags_per_method = revFlagsLeaf;
  rev.chainTests.cert_rev_flags_per_method = revFlagsChain;
  secStatus = configureRevocationParams(&rev);
 
  if (secStatus) {
    croak("Can not configure revocation parameters");
  }

  cvin[inParamIndex].type = cert_pi_revocationFlags;
  cvin[inParamIndex].value.pointer.revocation = &rev;
  inParamIndex++;


  cvin[inParamIndex].type = cert_pi_end;
  
  cvout[0].type = cert_po_trustAnchor;
  cvout[0].value.pointer.cert = NULL;
  cvout[1].type = cert_po_certList;
  cvout[1].value.pointer.chain = NULL; 
  cvout[2].type = cert_po_end;

  secStatus = CERT_PKIXVerifyCert(cert, certificateUsageSSLServer,
                                  cvin, cvout, NULL);
  

  if (secStatus != SECSuccess ) {
    PRErrorCode err = PR_GetError();
    croak( "could not add certificate to db %d = %s\n",
	         err, PORT_ErrorToString(err));
    RETVAL = &PL_sv_no;
  } else {
    RETVAL = &PL_sv_yes;
  }  

  OUTPUT: 
  RETVAL

Crypt::NSS::Certificate
new(class, string)
  SV  *string

  PREINIT:
  CERTCertificate *cert;
  CERTCertDBHandle *defaultDB;
  //PRFileDesc*     fd;
  SECStatus       rv;
  SECItem         item        = {0, NULL, 0};

  CODE:
 // SV  *class

  defaultDB = CERT_GetDefaultCertDB();
  rv = sv_to_item(string, &item);
  if (rv != SECSuccess) {
    croak("sv_to_item failed");
  }

  cert = CERT_NewTempCertificate(defaultDB, &item, 
                                   NULL     /* nickname */, 
                                   PR_FALSE /* isPerm */, 
				   PR_TRUE  /* copyDER */);

  
  if (!cert) {
    PRErrorCode err = PR_GetError();
    croak( "couldn't import certificate %d = %s\n",
	         err, PORT_ErrorToString(err));
    PORT_Free(item.data);
  }

  RETVAL = cert;

  OUTPUT:
  RETVAL


