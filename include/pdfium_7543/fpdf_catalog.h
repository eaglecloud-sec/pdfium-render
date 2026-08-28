// Copyright 2017 The PDFium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PUBLIC_FPDF_CATALOG_H_
#define PUBLIC_FPDF_CATALOG_H_

// NOLINTNEXTLINE(build/include)
#include "fpdfview.h"

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

// Experimental API.
//
// Determine if |document| represents a tagged PDF.
//
// For the definition of tagged PDF, See (see 10.7 "Tagged PDF" in PDF
// Reference 1.7).
//
//   document - handle to a document.
//
// Returns |true| iff |document| is a tagged PDF.
FPDF_EXPORT FPDF_BOOL FPDF_CALLCONV
FPDFCatalog_IsTagged(FPDF_DOCUMENT document);

// Experimental API.
// Sets the language of |document| to |language|.
//
// document - handle to a document.
// language - the language to set to.
//
// Returns TRUE on success.
FPDF_EXPORT FPDF_BOOL FPDF_CALLCONV
FPDFCatalog_SetLanguage(FPDF_DOCUMENT document, FPDF_BYTESTRING language);

// Experimental API.
// Status values returned by FPDFCatalog_GetCustomStream().
#define FPDF_CATALOG_CUSTOM_STREAM_SUCCESS 0
#define FPDF_CATALOG_CUSTOM_STREAM_MISSING 1
#define FPDF_CATALOG_CUSTOM_STREAM_NOT_A_STREAM 2
#define FPDF_CATALOG_CUSTOM_STREAM_TOO_LARGE 3
#define FPDF_CATALOG_CUSTOM_STREAM_UNSUPPORTED_FILTER 4
#define FPDF_CATALOG_CUSTOM_STREAM_DECODE_ERROR 5
#define FPDF_CATALOG_CUSTOM_STREAM_INVALID_ARGUMENT 6

// Retrieves a custom stream from the document catalog with a decoded-size
// limit. See the Eagle PDFium 7543 release for supported filters.
FPDF_EXPORT int FPDF_CALLCONV FPDFCatalog_GetCustomStream(
    FPDF_DOCUMENT document,
    FPDF_BYTESTRING key,
    unsigned long max_size,
    void* buffer,
    unsigned long buflen,
    unsigned long* out_len);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  // PUBLIC_FPDF_CATALOG_H_
