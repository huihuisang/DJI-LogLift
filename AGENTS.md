# Project guidance

- This public checkout is the only active development source for LogLift. Do not publish local internal records or private repository history.

- Use English for code, comments, UI source text, and commit messages.
- Localize UI text in English, Simplified Chinese, Japanese, and Korean.
- Use jj with colocated Git for local version control.
- Preserve unrelated changes and source media.
- Build with `./script/build_and_run.sh --build-only`. Launch only when the user requests a foreground session.
- Keep disposable build and test outputs outside the checkout. Reuse a shared build cache when possible.
- Preserve downloaded DJI resource bytes, provenance, and checksums.
- Read `THIRD_PARTY_NOTICES.md` before changing or distributing resources. Download availability does not establish redistribution permission.
- Do not infer Log encoding from low saturation, a filename, or a Rec.709 container tag alone.
- Use the existing native framework and SwiftUI patterns. Keep synthetic media tests separate from camera color-accuracy claims.
