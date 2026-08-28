//! Defines the [PdfCatalog] struct, exposing internal properties related to the
//! document catalog for a single [PdfDocument].

use crate::bindgen::FPDF_DOCUMENT;
use crate::error::PdfiumError;
use crate::pdfium::PdfiumLibraryBindingsAccessor;
use std::marker::PhantomData;

#[cfg(any(
    feature = "pdfium_future",
    feature = "pdfium_7881",
    feature = "pdfium_7763"
))]
use crate::utils::{mem::create_byte_buffer, utf16le::get_string_from_pdfium_utf16le_bytes};

#[cfg(feature = "pdfium_eagle_catalog")]
use std::ffi::CString;

#[cfg(feature = "pdfium_eagle_catalog")]
use std::os::raw::c_ulong;

#[cfg(any(
    feature = "pdfium_future",
    feature = "pdfium_7881",
    feature = "pdfium_7763"
))]
use std::ffi::c_ushort;

#[cfg(doc)]
use crate::pdf::document::PdfDocument;

/// The internal catalog properties for a single [PdfDocument].
pub struct PdfCatalog<'a> {
    document_handle: FPDF_DOCUMENT,
    lifetime: PhantomData<&'a FPDF_DOCUMENT>,
}

/// Result of reading a bounded custom stream from a PDF document catalog.
#[cfg(feature = "pdfium_eagle_catalog")]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PdfCatalogCustomStreamResult {
    Data(Vec<u8>),
    Missing,
    NotAStream,
    TooLarge,
    UnsupportedFilter,
    DecodeError,
    InvalidArgument,
}

impl<'a> PdfCatalog<'a> {
    #[inline]
    pub(crate) fn from_pdfium(document_handle: FPDF_DOCUMENT) -> Self {
        Self {
            document_handle,
            lifetime: PhantomData,
        }
    }

    /// Returns the internal `FPDF_DOCUMENT` handle of the `PdfDocument` containing
    /// this [PdfCatalog] instance.
    #[inline]
    pub(crate) fn document_handle(&self) -> FPDF_DOCUMENT {
        self.document_handle
    }

    /// Returns `true` if the containing [PdfDocument] is a tagged PDF.
    ///
    /// A PDF is considered "tagged" if it includes structural elements and metadata
    /// that can be used to facilitate content extraction and processing by tooling;
    /// in other words, the PDF contains data above and beyond that required merely for
    /// rendering.
    ///
    /// For more information on tagged PDFs, see The PDF Reference, Sixth Edition,
    /// section 10.7, starting on page 883.
    #[inline]
    pub fn is_tagged(&self) -> bool {
        self.bindings()
            .is_true(unsafe { self.bindings().FPDFCatalog_IsTagged(self.document_handle()) })
    }

    /// Reads a custom catalog stream without decoding more than `max_size`
    /// bytes. This API requires an Eagle PDFium build exposing
    /// `FPDFCatalog_GetCustomStream()`.
    #[cfg(feature = "pdfium_eagle_catalog")]
    pub fn custom_stream(&self, key: &str, max_size: usize) -> PdfCatalogCustomStreamResult {
        use crate::bindgen::{
            FPDF_CATALOG_CUSTOM_STREAM_DECODE_ERROR, FPDF_CATALOG_CUSTOM_STREAM_MISSING,
            FPDF_CATALOG_CUSTOM_STREAM_NOT_A_STREAM, FPDF_CATALOG_CUSTOM_STREAM_SUCCESS,
            FPDF_CATALOG_CUSTOM_STREAM_TOO_LARGE, FPDF_CATALOG_CUSTOM_STREAM_UNSUPPORTED_FILTER,
        };

        let Ok(key) = CString::new(key) else {
            return PdfCatalogCustomStreamResult::InvalidArgument;
        };
        let Ok(buffer_size) = c_ulong::try_from(max_size) else {
            return PdfCatalogCustomStreamResult::InvalidArgument;
        };
        if buffer_size == 0 {
            return PdfCatalogCustomStreamResult::InvalidArgument;
        }

        let mut buffer = Vec::new();
        if buffer.try_reserve_exact(max_size).is_err() {
            return PdfCatalogCustomStreamResult::InvalidArgument;
        }
        buffer.resize(max_size, 0);
        let mut out_len: c_ulong = 0;
        let status = unsafe {
            self.bindings().FPDFCatalog_GetCustomStream(
                self.document_handle(),
                key.as_ptr(),
                buffer_size,
                buffer.as_mut_ptr().cast(),
                buffer_size,
                &mut out_len,
            )
        };

        match status {
            FPDF_CATALOG_CUSTOM_STREAM_SUCCESS => {
                let Ok(out_len) = usize::try_from(out_len) else {
                    return PdfCatalogCustomStreamResult::DecodeError;
                };
                if out_len > buffer.len() {
                    return PdfCatalogCustomStreamResult::DecodeError;
                }
                buffer.truncate(out_len);
                PdfCatalogCustomStreamResult::Data(buffer)
            }
            FPDF_CATALOG_CUSTOM_STREAM_MISSING => PdfCatalogCustomStreamResult::Missing,
            FPDF_CATALOG_CUSTOM_STREAM_NOT_A_STREAM => PdfCatalogCustomStreamResult::NotAStream,
            FPDF_CATALOG_CUSTOM_STREAM_TOO_LARGE => PdfCatalogCustomStreamResult::TooLarge,
            FPDF_CATALOG_CUSTOM_STREAM_UNSUPPORTED_FILTER => {
                PdfCatalogCustomStreamResult::UnsupportedFilter
            }
            FPDF_CATALOG_CUSTOM_STREAM_DECODE_ERROR => PdfCatalogCustomStreamResult::DecodeError,
            _ => PdfCatalogCustomStreamResult::InvalidArgument,
        }
    }

    #[cfg(any(
        feature = "pdfium_future",
        feature = "pdfium_7881",
        feature = "pdfium_7763"
    ))]
    /// Returns the language set in the catalog of the containing [PdfDocument], if any.
    pub fn get_language(&self) -> Result<String, PdfiumError> {
        // Retrieving the bookmark title from Pdfium is a two-step operation. First, we call
        // FPDFBookmark_GetTitle() with a null buffer; this will retrieve the length of
        // the bookmark title in bytes. If the length is zero, then there is no title.

        // If the length is non-zero, then we reserve a byte buffer of the given
        // length and call FPDFBookmark_GetTitle() again with a pointer to the buffer;
        // this will write the bookmark title to the buffer in UTF16-LE format.

        let buffer_length = unsafe {
            self.bindings()
                .FPDFCatalog_GetLanguage(self.document_handle(), std::ptr::null_mut(), 0)
        };

        if buffer_length == 0 {
            // An error occurred.

            return Err(PdfiumError::PdfiumFunctionReturnValueIndicatedFailure);
        }

        if buffer_length == 2 {
            // No language is set.

            return Err(PdfiumError::NoLanguageSetInDocumentCatalog);
        }

        let mut buffer = create_byte_buffer(buffer_length as usize);

        let result = unsafe {
            self.bindings().FPDFCatalog_GetLanguage(
                self.document_handle(),
                buffer.as_mut_ptr() as *mut c_ushort,
                buffer_length,
            )
        };

        assert_eq!(result, buffer_length);

        get_string_from_pdfium_utf16le_bytes(buffer)
            .ok_or(PdfiumError::NoLanguageSetInDocumentCatalog)
    }

    #[cfg(any(
        feature = "pdfium_future",
        feature = "pdfium_7881",
        feature = "pdfium_7763",
        feature = "pdfium_7543",
        feature = "pdfium_7350",
        feature = "pdfium_7215",
        feature = "pdfium_7123",
        feature = "pdfium_6996",
        feature = "pdfium_6721",
        feature = "pdfium_6666"
    ))]
    /// Sets the language of the containing [PdfDocument] to the given value.
    pub fn set_language(&mut self, language: impl ToString) -> Result<(), PdfiumError> {
        if self.bindings().is_true(unsafe {
            self.bindings()
                .FPDFCatalog_SetLanguage_str(self.document_handle(), language.to_string().as_str())
        }) {
            Ok(())
        } else {
            Err(PdfiumError::PdfiumFunctionReturnValueIndicatedFailure)
        }
    }
}

impl<'a> PdfiumLibraryBindingsAccessor<'a> for PdfCatalog<'a> {}

#[cfg(feature = "thread_safe")]
unsafe impl<'a> Send for PdfCatalog<'a> {}

#[cfg(feature = "thread_safe")]
unsafe impl<'a> Sync for PdfCatalog<'a> {}
