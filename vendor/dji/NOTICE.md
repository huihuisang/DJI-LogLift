# DJI resource provenance

Checked on 2026-10-30.

The source of these LUT files and product photos is DJI's public download center. DJI and its contributors retain their rights. The resource files have not been assigned the license of the application source code.

- Official LUT directory: <https://www.dji.com/lut>
- Download-index source: <https://www.dji.com/cn/downloads/softwares/osmo-nano-d-log-m-to-rec-709-vivid-lut>
- DJI website and software terms: <https://www.dji.com/terms>

`source-index.json` records the package metadata and official URLs. The runtime catalog records each downloaded file's requested and resolved URL, version, publication date, SHA-256, and local path. Extracted CUBE files also record their archive member name, encoding, dimensions, and sample count. Neither downloading nor parsing changes the original bytes.

Temporary download authorization and signature parameters are removed from published provenance URLs. A `sanitizedURLFields` entry identifies altered URL fields. The resource bytes and their checksums remain unchanged; a sanitized resolved URL may require a fresh redirect from the official source page before download.

Some legacy LUT packages are listed only under the Windows download category. They are data archives, not Windows programs. Those LUTs are included; executables and old transcoder applications are excluded.

## Product photos

`LogBatch/Resources/ProductImages/manifest.json` records 36 product entries with official source pages, published/download/resolved image URLs, pixel dimensions, alpha status, and SHA-256. The importer reads DJI product download pages and product-specific page metadata. Original downloaded image bytes are preserved. The app trims transparent padding only in its decoded display image.

The combined `inspire-1-pro-and-raw` page redirects to DJI's Inspire 1 Pro support page. Its record is marked `official-family`, and the UI shows a series-image label. The other 35 records use product-specific images. This snapshot covers the app's LUT catalog, not all DJI hardware.

## Distribution status

**A dedicated permission to redistribute these LUTs or product photos inside a third-party application has not been verified.** Public download availability is not a redistribution grant. The general website terms restrict certain reproduction, transfer, and automated access; package-specific terms may apply separately. This record does not establish a legal license or legal compliance.

The project owner requested inclusion in the local development app and private backup, then explicitly requested a public project snapshot including these images, LUTs, and archives on 2026-10-31. That request does not establish permission from DJI. No DJI account was created, no agreement was accepted, and no permission request was sent. No App Store release is authorized by that request.

These materials are excluded from the project's current PolyForm Noncommercial license and from its earlier MIT grant. Their publication does not establish a redistribution grant. Confirm the applicable license or obtain permission before redistributing them or shipping a derivative application. Do not describe LogLift as an official or endorsed DJI product.

