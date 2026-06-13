<p align="center">
  <img src="BookScan/Assets.xcassets/AppIcon.appiconset/BookScan_icon_1024_dark.png" width="160" alt="BookScan icon" />
</p>

<h1 align="center">BookScan</h1>

<p align="center">
  A native iOS app for scanning, organising, and lending your personal book collection — with iCloud sync across all your devices.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2018%2B-blue?logo=apple" alt="iOS 18+" />
  <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift" alt="Swift 5" />
  <img src="https://img.shields.io/badge/SwiftUI-%2B%20Core%20Data-purple" alt="SwiftUI + Core Data" />
  <img src="https://img.shields.io/badge/CloudKit-iCloud%20Sync-lightgrey?logo=icloud" alt="CloudKit" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
</p>

---

## What is BookScan?

BookScan is the app that remembers every book's place on your library's shelves — so any book can find its way back with a single scan.

Scan a book's barcode and the app instantly retrieves the title, author, year, and cover art. Assign the book to a named shelf — *"Living Room Top Row"*, *"Office Left"*, *"Kids Room"* — and BookScan remembers exactly where it lives. From that point on, any time a book ends up out of place, a single scan tells you where it belongs.

**The day-to-day usage:**

📚 **Building your library** — Walk to your shelves once and scan everything in. Each book gets assigned to its shelf in the app, creating a complete map of your physical library. No typing, no manual entry.

📍 **Putting books back** — Pulled a book out and not sure where it came from? Scan the barcode. The app instantly shows you the exact shelf to return it to. No more wandering around trying to remember where it lives.

🖥 **Always-on library assistant** — Leave an old iPad propped up on your bookshelf running BookScan full screen. It stays ready to scan at a moment's notice — no unlocking, no navigating. Just point and scan.

👧 **When kids rearrange your shelves** — Children pull books out constantly and rarely put them back in the right place. A quick scan on each displaced book tells you exactly where it belongs, turning a frustrating re-sort into a two-second job.

🤝 **Lending tracker** — Lend a book to someone with one tap. When they return it, scan the barcode: BookScan automatically clears the lent status and shows you which shelf to put it back on. If you can scan it, you have it back — it's that simple.

---

## Support the Project

If BookScan saves you time or you just find it useful, a small donation is greatly appreciated and helps fund continued development.

[![Donate with PayPal](https://www.paypalobjects.com/en_AU/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=mihailescu2m%40gmail%2Ecom&lc=AU&item_name=memeka&item_number=odroid&currency_code=AUD&bn=PP%2DDonationsBF%3Abtn_donate_LG%2Egif%3ANonHosted)

---

## Features

### Scanning & Lookup
- **Instant barcode scanning** — point the camera at an EAN-13 / ISBN-13 barcode and the book is identified in under a second
- **Manual ISBN entry** — type any ISBN-10 or ISBN-13 (with full check-digit validation) when a barcode is too worn to scan
- **Seven-source lookup engine** — two tiers, each raced in parallel with first-hit-wins: Open Library and Google Books first; if both miss, five more sources (Open Library's search index, Crossref, the Library of Congress, Trove, and Inventaire) race next. Each covers a different sweet spot (classics & library-catalogued, popular modern, contemporary popular fiction & non-fiction, academic & textbooks, niche US-published & children's, Australian-published, multilingual European editions) so almost every book is found — fast
- **Background cover search** — cover art is hunted in parallel with the metadata lookup (never delaying the New Book sheet) and keeps searching in the background after the book is saved, attaching the cover while the next book is already being scanned
- **Rich cover art** — searches nine sources concurrently (Open Library covers, Google Books ×3, Apple Books, WorldCat, Bookcover API, Better World Books, and Open Library search) and picks the best available image

### Library Management
- **Named shelves** — organise books into as many shelves as you like; drag between shelves at any time
- **Unshelved section** — books without a shelf always stay visible and accessible
- **Cover image editing** — change a cover from the camera, the photo library, or a web image search directly in the detail view
- **Full-text search** — find any book instantly by title, author, or ISBN with a 300 ms debounced search

### Lending Tracker
- **Lend a book** — one tap moves a book to the dedicated *Lent* shelf and remembers which shelf it came from
- **Return via barcode** — scanning a lent book's barcode automatically returns it to its original shelf; a confirmation screen shows where to put it back
- **Scan-to-return flow** — the scanner recognises lent books and triggers the return action immediately, no menus required

### Sync & Family Sharing
- **iCloud sync** — your library syncs silently across all your own devices via your private iCloud container
- **Family sharing** — share your whole library, read/write, with family (partner, kids): tap the share button, send an invite, and everyone sees and edits the same live library
- **Merged, equal access** — every member can scan, shelve, lend, and return; changes appear on the other devices within seconds
- **Conflict-safe** — owner-side maintenance and deterministic merge logic keep the shared library consistent under concurrent edits

### Privacy
- No tracking, no analytics, no third-party SDKs
- Camera access is used exclusively for barcode scanning
- Photo library access is opt-in and only used when you choose to set a cover image
- All data is stored in your private iCloud container — never on a third-party server

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Data & persistence | Core Data (`NSPersistentCloudKitContainer`) |
| Cloud sync & sharing | CloudKit (private + shared databases, `CKShare`) |
| Camera / scanning | AVFoundation (`AVCaptureSession`, EAN-13) |
| Image picking | PhotosUI (`PHPickerViewController`) |
| Book metadata | Open Library, Google Books, Crossref, Library of Congress, Trove, Inventaire |
| Cover images | Open Library Covers, Google Books, Apple Books, WorldCat, Bookcover API, Better World Books, Inventaire |
| Concurrency | Swift Structured Concurrency (`async/await`, `actor`, `async let`) |
| Localization | String Catalog (`Localizable.xcstrings`), translation-ready with plural inflection |
| Logging | `os.log` (unified logging) |
| Tests | Swift Testing framework |

---

## Requirements

| | Minimum |
|---|---|
| iOS | 18.0 |
| Xcode | 16.0 |
| Swift | 5.0 |
| iCloud account | Required for sync (app works offline without one) |

---

## Building & Running

1. **Clone the repository**
   ```bash
   git clone https://github.com/mihailescu2m/BookScan.git
   cd BookScan/BookScan
   ```

2. **Open in Xcode**
   ```bash
   open BookScan.xcodeproj
   ```

3. **Sign the app**  
   In Xcode → *Signing & Capabilities*, select your Apple Developer team. Xcode will register the App ID and the CloudKit container (`iCloud.memeka.BookScan`) automatically on first build.

   > **CloudKit schema deployment:** debug builds use the *Development* CloudKit environment; TestFlight/App Store builds use *Production*, whose schema is locked. After adding or changing a model field (most recently `Book.contributedBy`), run a debug build once so the field appears in Development, then open the [CloudKit Console](https://icloud.developer.apple.com) → `iCloud.memeka.BookScan` → **Deploy Schema Changes to Production** before shipping — otherwise Production saves of that field will fail.

4. **Run on a device**  
   Select your iPhone or iPad as the run destination and press **⌘R**.  
   > A physical device is required for barcode scanning. The iOS simulator cannot access a camera.

5. **Run unit tests**  
   ```bash
   xcodebuild build-for-testing \
     -project BookScan.xcodeproj \
     -scheme BookScan \
     -destination 'generic/platform=iOS'
   ```

---

## Project Structure

```
BookScan/
├── Models/
│   ├── Library.swift           — NSManagedObject: hidden root that owns shelves + books (sharing anchor)
│   ├── Book.swift              — NSManagedObject: isbn, title, author, shelf, lend/return logic
│   └── Shelf.swift             — NSManagedObject: name, sortOrder, isLendingShelf
├── Persistence/
│   ├── PersistenceController.swift — Core Data + CloudKit stack, private/shared stores, factories, sharing
│   └── BookScanModel.swift     — programmatic NSManagedObjectModel (CloudKit-compatible)
├── Services/
│   ├── ISBNValidator.swift     — ISBN-10/13 normalisation & check-digit validation
│   └── ISBNLookupService.swift — actor: metadata lookup + concurrent cover image search
├── Views/
│   ├── Components/
│   │   ├── CoverImage.swift         — UIImage resize/normalise pipeline
│   │   ├── DismissWhenDeleted.swift — Dismisses a view when its object is remotely deleted
│   │   ├── EditBookDetailsView.swift— Re-query all sources and pick the correct edition
│   │   ├── ImagePicker.swift        — Camera & photo library pickers
│   │   ├── NewShelfAlert.swift      — Reusable "New Shelf" alert modifier
│   │   ├── SharingPresenter.swift   — Presents UICloudSharingController (invite / manage / leave)
│   │   ├── SheetHeader.swift        — Flat iOS-style sheet header bar + circular buttons
│   │   └── WebCoverSearchView.swift — Web cover image grid picker
│   ├── Library/
│   │   ├── LibraryTabView.swift     — Main library with shelf sections + share button
│   │   ├── BookDetailView.swift     — Sheet wrapper for book detail
│   │   ├── BookDetailContent.swift  — Book info, shelf picker, lend/return/delete
│   │   └── SearchView.swift         — Full-text search with debounce
│   └── Scanner/
│       ├── ScannerTabView.swift         — Single enum-driven sheet state machine
│       ├── BarcodeScannerView.swift     — AVFoundation camera + EAN-13 decoder
│       ├── CoverPipeline.swift          — Background cover search that attaches after save
│       ├── NewBookView.swift            — Confirm & save a newly scanned book
│       ├── ExistingBookView.swift       — Show location / return a found book
│       └── ManualISBNEntryView.swift    — Keyboard ISBN entry with live validation
├── AppDelegate.swift   — Accepts CloudKit share invitations
├── BookScanApp.swift   — App entry point, persistence injection, owner-only bootstrap
└── ContentView.swift   — TabView + floating tab bar + search sheet
```

---

## Data Model

```
Library ──< Shelf
Library ──< Book
Shelf   ──< Book (shelf)
Shelf   ──< Book (previousShelf)   ← remembers original shelf while lent
```

A single hidden `Library` root owns every shelf and book; sharing that one object moves the whole graph into a shared CloudKit zone, so the entire library is shared (and new items automatically join it).

`Book.lend(to:)` stores `shelf` → `previousShelf` and moves the book to the lending shelf.  
`Book.returnBook()` restores `shelf = previousShelf` and clears `previousShelf`.

---

## API Credits

BookScan uses the following free, open APIs — no API keys required (except Trove, optional):

| Service | Used for |
|---|---|
| [Open Library](https://openlibrary.org/developers/api) | Book metadata (1st, catalog API; 3rd, search index) + cover images by ISBN and title/author search |
| [Google Books API](https://developers.google.com/books) | Book metadata (2nd) + cover images (queried three ways: by ISBN, title+author, title) |
| [Crossref](https://www.crossref.org/documentation/retrieve-metadata/rest-api/) | Book metadata (4th) — academic, scientific, and university press titles |
| [Library of Congress](https://www.loc.gov/apis/) | Book metadata (5th) — niche US-published, regional, children's, cookbooks, official publications |
| [Trove (National Library of Australia)](https://trove.nla.gov.au/about/create-something/using-api) | Book metadata (6th) — Australian-published books. Needs a free API key (renewed yearly), pasted into iOS Settings → BookScan |
| [Inventaire](https://api.inventaire.io/) | Book metadata (7th) + cover images — Wikidata-federated community database; multilingual European editions (incl. Romanian) |
| [Apple Books (iTunes Search)](https://performance-partners.apple.com/search-api) | Cover images by title + author — strong coverage of mainstream commercial titles |
| [WorldCat / OCLC](https://www.worldcat.org) | Cover images by ISBN — excellent coverage of academic, older, and non-English titles |
| [Bookcover API](https://bookcover.longitood.com) | Cover images by ISBN |
| [Better World Books](https://www.betterworldbooks.com) | Cover images by ISBN |

All nine cover-image sources run **concurrently** and results are assembled in priority order, so the app shows the best available cover without waiting for slower sources. Crossref and the Library of Congress provide metadata only — cover images are handled by the other sources.

---

## Contributing

Bug reports and pull requests are welcome. For major changes please open an issue first to discuss what you'd like to change.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a pull request

Please make sure existing tests pass and add new tests for any new logic.

---

## License

BookScan is released under the [MIT License](LICENSE).

```
MIT License

Copyright (c) 2026 Marian Mihailescu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
