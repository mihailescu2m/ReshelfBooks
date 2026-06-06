<p align="center">
  <img src="BookScan/Assets.xcassets/AppIcon.appiconset/BookScan_icon_1024_dark.png" width="160" alt="BookScan icon" />
</p>

<h1 align="center">BookScan</h1>

<p align="center">
  A native iOS app for scanning, cataloguing, and lending your personal book collection — with iCloud sync across all your devices.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2018%2B-blue?logo=apple" alt="iOS 18+" />
  <img src="https://img.shields.io/badge/Swift-6-orange?logo=swift" alt="Swift 6" />
  <img src="https://img.shields.io/badge/SwiftUI-%2B%20SwiftData-purple" alt="SwiftUI + SwiftData" />
  <img src="https://img.shields.io/badge/CloudKit-iCloud%20Sync-lightgrey?logo=icloud" alt="CloudKit" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
</p>

---

## What is BookScan?

BookScan turns your iPhone or iPad into a personal library cataloguer. Point the camera at any book's barcode and the app instantly looks up the title, author, year, and cover art — no typing required. Your entire library lives in iCloud, so it stays in sync across every device you own.

**Use cases:**

- 📚 Cataloguing a home library, office bookshelf, or classroom collection
- 🔍 Quickly checking whether you already own a book before buying it
- 🤝 Tracking books you have lent to friends and family
- 📖 Organising books into named shelves (Fiction, Non-Fiction, To-Read, etc.)
- 🔎 Searching your collection by title, author, or ISBN at any time

---

## Features

### Scanning & Lookup
- **Instant barcode scanning** — point the camera at an EAN-13 / ISBN-13 barcode and the book is identified in under a second
- **Manual ISBN entry** — type any ISBN-10 or ISBN-13 (with full check-digit validation) when a barcode is too worn to scan
- **Dual lookup engine** — queries Open Library first, then Google Books as a fallback, so almost every book is found
- **Rich cover art** — searches seven sources concurrently (Open Library, Google Books ×3, Bookcover API, Better World Books, and an Open Library search) and picks the best available image

### Library Management
- **Named shelves** — organise books into as many shelves as you like; drag between shelves at any time
- **Unshelved section** — books without a shelf always stay visible and accessible
- **Cover image editing** — change a cover from the camera, the photo library, or a web image search directly in the detail view
- **Full-text search** — find any book instantly by title, author, or ISBN with a 300 ms debounced search

### Lending Tracker
- **Lend a book** — one tap moves a book to the dedicated *Lent* shelf and remembers which shelf it came from
- **Return via barcode** — scanning a lent book's barcode automatically returns it to its original shelf; a confirmation screen shows where to put it back
- **Scan-to-return flow** — the scanner recognises lent books and triggers the return action immediately, no menus required

### iCloud Sync
- **CloudKit private database** — your library syncs silently across iPhone and iPad via your private iCloud container
- **Conflict-safe** — launch-time merge logic deduplicates any *Lent* shelf copies that a CloudKit sync race might create, keeping your data consistent

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
| Data & persistence | SwiftData |
| Cloud sync | CloudKit (private database) |
| Camera / scanning | AVFoundation (`AVCaptureSession`, EAN-13) |
| Image picking | PhotosUI (`PHPickerViewController`) |
| Book metadata | Open Library API, Google Books API |
| Cover images | Open Library Covers, Google Books, Bookcover API, Better World Books |
| Concurrency | Swift Structured Concurrency (`async/await`, `actor`, `async let`) |
| Logging | `os.log` (unified logging) |
| Tests | Swift Testing framework |

---

## Requirements

| | Minimum |
|---|---|
| iOS | 18.0 |
| Xcode | 16.0 |
| Swift | 6.0 |
| iCloud account | Required for sync (app works offline without one) |

---

## Building & Running

1. **Clone the repository**
   ```bash
   git clone https://github.com/<your-username>/BookScan.git
   cd BookScan/BookScan
   ```

2. **Open in Xcode**
   ```bash
   open BookScan.xcodeproj
   ```

3. **Sign the app**  
   In Xcode → *Signing & Capabilities*, select your Apple Developer team. Xcode will register the App ID and the CloudKit container (`iCloud.memeka.BookScan`) automatically on first build.

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
│   ├── Book.swift              — @Model: isbn, title, author, shelf, lend/return logic
│   └── Shelf.swift             — @Model: name, sortOrder, isLendingShelf
├── Services/
│   ├── ISBNValidator.swift     — ISBN-10/13 normalisation & check-digit validation
│   └── ISBNLookupService.swift — actor: metadata lookup + concurrent cover image search
├── Views/
│   ├── Components/
│   │   ├── CoverImage.swift         — UIImage resize/normalise pipeline
│   │   ├── ImagePicker.swift        — Camera & photo library pickers
│   │   ├── NewShelfAlert.swift      — Reusable "New Shelf" alert modifier
│   │   └── WebCoverSearchView.swift — Web cover image grid picker
│   ├── Library/
│   │   ├── LibraryTabView.swift     — Main library with shelf sections
│   │   ├── BookDetailView.swift     — Sheet wrapper for book detail
│   │   ├── BookDetailContent.swift  — Book info, shelf picker, lend/return/delete
│   │   └── SearchView.swift         — Full-text search with debounce
│   └── Scanner/
│       ├── ScannerTabView.swift         — Single enum-driven sheet state machine
│       ├── BarcodeScannerView.swift     — AVFoundation camera + EAN-13 decoder
│       ├── NewBookView.swift            — Confirm & save a newly scanned book
│       ├── ExistingBookView.swift       — Show location / return a found book
│       └── ManualISBNEntryView.swift    — Keyboard ISBN entry with live validation
├── BookScanApp.swift   — App entry point, ModelContainer, lending-shelf dedup
└── ContentView.swift   — TabView + floating tab bar + search sheet
```

---

## Data Model

```
Shelf ──< Book (shelf)
Shelf ──< Book (previousShelf)   ← remembers original shelf while lent
```

`Book.lend(to:)` stores `shelf` → `previousShelf` and moves the book to the lending shelf.  
`Book.returnBook()` restores `shelf = previousShelf` and clears `previousShelf`.

---

## API Credits

BookScan uses the following free, open APIs — no API keys required:

- **[Open Library](https://openlibrary.org/developers/api)** — book metadata and cover images
- **[Google Books API](https://developers.google.com/books)** — book metadata and cover images
- **[Bookcover API](https://bookcover.longitood.com)** — cover images by ISBN
- **[Better World Books](https://www.betterworldbooks.com)** — cover images by ISBN

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

## Support the Project

If BookScan saves you time or you just find it useful, a small donation is greatly appreciated and helps fund continued development.

<p align="center">
  <a href="https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=mihailescu2m%40gmail%2Ecom&lc=AU&item_name=memeka&item_number=odroid&currency_code=AUD&bn=PP%2DDonationsBF%3Abtn_donate_LG%2Egif%3ANonHosted">
    <img src="https://www.paypalobjects.com/en_AU/i/btn/btn_donate_LG.gif" alt="Donate with PayPal" />
  </a>
</p>

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
