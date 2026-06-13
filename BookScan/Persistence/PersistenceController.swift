//
//  PersistenceController.swift
//  BookScan
//
//  Created by Marian Mihailescu on 6/6/2026.
//
//  Core Data + CloudKit stack with private + shared databases, so the library can
//  be shared read/write with family members. SwiftData has no sharing API, so we
//  use NSPersistentCloudKitContainer (Apple's supported path).
//

import Foundation
import CoreData
import CloudKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.bookscan", category: "Persistence")

/// Value-type copy of a contributed book, captured at the moment a participant leaves
/// a shared library — BEFORE CloudKit's zone purge deletes the local records — so the
/// "Bring Them Back" prompt can rebuild the books at leisure. Shelves are recorded by
/// name (with current lending state), since the shelf objects themselves die with the
/// shared store.
struct ContributedBookSnapshot {
    let isbn: String
    let title: String
    let author: String
    let yearPublished: String
    let coverImageURL: String?
    let coverImageData: Data?
    let dateAdded: Date?
    /// Current shelf name; nil when unshelved or lent.
    let shelfName: String?
    let isLent: Bool
    /// The shelf to return to after lending; only set while lent.
    let previousShelfName: String?
}

final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    /// In-memory stack for SwiftUI previews and unit tests (no CloudKit).
    static let preview: PersistenceController = PersistenceController(inMemory: true)

    private static let containerID = "iCloud.memeka.BookScan"

    let container: NSPersistentCloudKitContainer

    /// The store backing the current user's own data (the share owner's library).
    private(set) var privateStore: NSPersistentStore?
    /// The store backing libraries shared *with* this user by someone else.
    private(set) var sharedStore: NSPersistentStore?

    /// Whether the active library is currently shared with anyone. Drives the
    /// "Library" vs "Shared Library" title. Updated on launch, on remote changes,
    /// and after the sharing sheet saves/stops a share.
    @Published private(set) var isLibraryShared = false

    /// Set right after joining a shared library *if* the joiner still has local
    /// (never-shared) books — its value is how many. Drives a "Keep My Books Private /
    /// Move Into Shared Library" prompt. `nil` means no prompt (the common case:
    /// nothing local to decide about).
    @Published var pendingJoinLocalBookCount: Int?

    /// Snapshot of the books this user contributed to a shared library, captured at
    /// the moment they leave it (before the zone purge deletes the local copies).
    /// Drives a "Bring Them Back / Leave Them" prompt; `nil` means no prompt.
    @Published var pendingLeaveSnapshot: [ContributedBookSnapshot]?

    /// Non-nil when a share invitation was declined because this user already owns a
    /// shared library. Drives an explanatory alert.
    @Published var joinBlockedReason: String?

    var viewContext: NSManagedObjectContext { container.viewContext }
    // Stored lazily so `eraseAllDataIfRequested()` (called in init) and the sharing
    // flow share the same `CKContainer` instance rather than allocating a new one on
    // every call site.
    lazy var ckContainer: CKContainer = CKContainer(identifier: Self.containerID)

    private let inMemory: Bool

    // MARK: - Init

    /// UserDefaults key written by the toggle in the app's iOS Settings bundle.
    private static let resetFlagKey = "reset_all_data"
    /// Set when the user chose "Move Into Shared Library" at join time. The shared
    /// library may not have synced down yet, so the move stays armed (surviving
    /// relaunches) until a shared-store library exists and the migration runs.
    private static let pendingMoveKey = "pending_move_into_shared_library"
    /// Cached CloudKit user record ID — stable per iCloud account, so books tagged on
    /// one of the user's devices are recognized on all of them.
    private static let userRecordIDKey = "cloudkit_user_record_id"
    /// Per-install fallback tag, used only until the CloudKit ID has been fetched.
    private static let localContributorIDKey = "local_contributor_id"

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        container = NSPersistentCloudKitContainer(
            name: "BookScan",
            managedObjectModel: Self.makeManagedObjectModel()
        )
        // Honor a "reset everything" request from iOS Settings BEFORE the stores load.
        if !inMemory { eraseAllDataIfRequested() }
        configureStoreDescriptions()
        loadStores()
        configureViewContext()
        observeRemoteChanges()
    }

    private func configureStoreDescriptions() {
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
            return
        }

        let baseURL = NSPersistentContainer.defaultDirectoryURL()

        // Private database store (the owner's own data).
        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("Expected an initial persistent store description")
        }
        privateDescription.url = baseURL.appendingPathComponent("BookScan.sqlite")
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerID)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        // Shared database store (libraries shared with this user).
        guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("Could not copy private store description")
        }
        sharedDescription.url = baseURL.appendingPathComponent("BookScan-shared.sqlite")
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerID)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
    }

    private func loadStores() {
        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                logger.critical("Failed to load store \(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
                return
            }
            // Match each loaded store to its scope so we can target writes correctly.
            if let store = self.container.persistentStoreCoordinator.persistentStore(for: description.url ?? URL(fileURLWithPath: "/dev/null")) {
                if self.inMemory {
                    self.privateStore = store
                } else if description.cloudKitContainerOptions?.databaseScope == .shared {
                    self.sharedStore = store
                } else {
                    self.privateStore = store
                }
            }
        }

        // Resilience: if the on-disk private store failed to load (e.g. corruption or
        // a CloudKit setup error), fall back to an in-memory store so the app still
        // launches and is usable rather than silently unable to create or persist
        // anything. Data won't persist in this degraded mode, but the app works.
        //
        // NOTE: `loadPersistentStores` for SQLite invokes its handler synchronously
        // (Apple's documented behaviour for on-disk stores), so `privateStore` is
        // guaranteed to be populated before we reach this check. If that assumption ever
        // breaks (async handler delivery), the fallback simply creates an extra in-memory
        // store, which is harmless but unnecessary.
        if !inMemory, privateStore == nil {
            logger.warning("Private store unavailable; falling back to an in-memory store")
            privateStore = try? container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSInMemoryStoreType,
                configurationName: nil,
                at: nil,
                options: nil
            )
        }
    }

    /// Erases all local and CloudKit data when the user toggled the reset switch in
    /// iOS Settings. Local store files are deleted immediately; the flag is cleared
    /// only once the CloudKit zone purge has actually SUCCEEDED. A reset issued while
    /// offline therefore stays armed and completes on a later launch, instead of the
    /// old data quietly syncing back down. While armed, every launch starts from an
    /// empty store — anything created in between is erased too, which is the intended
    /// meaning of "reset everything" (the Settings toggle visibly stays on until done).
    private func eraseAllDataIfRequested() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.resetFlagKey) else { return }
        logger.warning("Reset requested from Settings — erasing all local and CloudKit data")

        // 1. Delete the local store files so this launch starts empty.
        let base = NSPersistentContainer.defaultDirectoryURL()
        for store in ["BookScan.sqlite", "BookScan-shared.sqlite"] {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: base.appendingPathComponent(store + suffix))
            }
        }

        // 2. Delete the user's own (private database) CloudKit zones so the data doesn't
        //    sync back down. We can't touch zones owned by someone who shared a library
        //    with us (and don't need to — those live in the shared store file).
        let database = ckContainer.privateCloudDatabase
        database.fetchAllRecordZones { zones, _ in
            // Offline / fetch failed: leave the flag set so the next launch retries.
            guard let zones else { return }
            let deletableIDs = zones.map(\.zoneID)
                .filter { $0.zoneName != CKRecordZone.default().zoneID.zoneName }
            guard !deletableIDs.isEmpty else {
                // Nothing to purge — the reset is complete.
                defaults.set(false, forKey: Self.resetFlagKey)
                return
            }
            let purge = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: deletableIDs)
            purge.modifyRecordZonesResultBlock = { result in
                if case .success = result {
                    defaults.set(false, forKey: Self.resetFlagKey)
                }
            }
            database.add(purge)
        }
    }

    private func configureViewContext() {
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.transactionAuthor = "app"
        // Intentionally NOT pinning the query generation: with live CloudKit imports
        // (especially from other family members), a pinned generation can hide newly
        // synced records until the app restarts. Let the context track the latest.
    }

    private var remoteChangeObserver: NSObjectProtocol?
    private var refreshWorkItem: DispatchWorkItem?

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            // The view context auto-merges automatically; we only need to recompute
            // the derived sharing state. Debounce it: CloudKit's initial import can
            // fire many remote-change notifications in quick succession, and share
            // membership changes rarely, so coalescing avoids needless main-thread work.
            self?.scheduleSharedStateRefresh()
        }
    }

    private func scheduleSharedStateRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            // The queued join-time move waits for the shared library to sync down,
            // which announces itself via these same remote-change notifications.
            self?.performPendingMoveIfPossible()
            self?.refreshSharedState()
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    // MARK: - Active library

    /// The single library used for new objects and for sharing. Prefers a library
    /// that was shared *with* this user (they've joined someone else's); otherwise
    /// the user's own private library; creating one lazily only if asked.
    @discardableResult
    func activeLibrary(creatingIfNeeded: Bool) -> Library? {
        let libraries = (try? viewContext.fetch(Library.fetchRequestAll())) ?? []
        let sorted = libraries.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        if let shared = sorted.first(where: { $0.objectID.persistentStore === sharedStore }) {
            return shared
        }
        if let owned = sorted.first(where: { $0.objectID.persistentStore === privateStore }) {
            return owned
        }
        if let any = sorted.first {
            return any
        }
        guard creatingIfNeeded, let privateStore else { return nil }

        let library = insert("Library") as! Library
        viewContext.assign(library, to: privateStore)
        try? viewContext.obtainPermanentIDs(for: [library])
        library.createdAt = Date()
        // Persist so it gets a permanent objectID/store for later store(for:) lookups.
        try? viewContext.save()
        return library
    }

    /// The persistent store an object lives in, falling back to the private store.
    private func store(for object: NSManagedObject) -> NSPersistentStore? {
        object.objectID.persistentStore ?? privateStore
    }

    private func insert(_ entityName: String) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: viewContext)
    }

    // MARK: - Visibility

    /// The persistent store backing the active library: the shared store while
    /// participating in someone else's library, the private store otherwise.
    var activeStore: NSPersistentStore? {
        activeLibrary(creatingIfNeeded: false).flatMap(store(for:)) ?? privateStore
    }

    /// Filters fetched objects down to the active library's store. While participating
    /// in a shared library this parks the user's own private books out of sight (they
    /// return automatically when the share ends) — and guarantees the UI can never
    /// relate objects across stores, which Core Data forbids (such saves fail and
    /// roll back silently).
    func visibleOnly<T: NSManagedObject>(_ objects: some Sequence<T>) -> [T] {
        guard let store = activeStore else { return Array(objects) }
        return objects.filter { $0.objectID.persistentStore === store }
    }

    // MARK: - Factories
    //
    // All creation goes through here so every new object is (a) attached to the
    // active library's object graph (so it joins the share) and (b) assigned to the
    // SAME persistent store as that library — Core Data forbids relationships that
    // cross stores, and participant writes must land in the shared store.

    @discardableResult
    func makeShelf(name: String, isLendingShelf: Bool = false) -> Shelf {
        let library = activeLibrary(creatingIfNeeded: true)
        let targetStore = library.flatMap(store(for:)) ?? privateStore
        return insertShelf(name: name, isLendingShelf: isLendingShelf, library: library, store: targetStore)
    }

    /// Core shelf creation with an explicit library/store target — used by `makeShelf`
    /// (active library) and by the leave-share restore (private library, which can't
    /// rely on `activeLibrary` while the shared store is still purging).
    @discardableResult
    private func insertShelf(name: String, isLendingShelf: Bool, library: Library?, store targetStore: NSPersistentStore?) -> Shelf {
        let shelf = insert("Shelf") as! Shelf
        if let targetStore { viewContext.assign(shelf, to: targetStore) }
        try? viewContext.obtainPermanentIDs(for: [shelf])
        shelf.dateCreated = Date()
        shelf.name = name
        shelf.isLendingShelf = isLendingShelf
        if isLendingShelf {
            shelf.sortOrder = Int64.max
        } else {
            // Sort after every existing regular shelf. Counted globally (not just the
            // active library's shelves) to match the Library view's global ordering,
            // so the new shelf reliably lands last even when orphan shelves exist.
            let regularShelfCount = ((try? viewContext.fetch(Shelf.fetchRequestAll())) ?? [])
                .filter { !$0.isLendingShelf }.count
            shelf.sortOrder = Int64(regularShelfCount)
        }
        shelf.library = library
        return shelf
    }

    @discardableResult
    func makeBook(
        isbn: String,
        title: String,
        author: String,
        yearPublished: String,
        coverImageURL: String?,
        shelf: Shelf?
    ) -> Book {
        let library = activeLibrary(creatingIfNeeded: true)
        let targetStore = library.flatMap(store(for:)) ?? privateStore

        let book = insert("Book") as! Book
        if let targetStore { viewContext.assign(book, to: targetStore) }
        try? viewContext.obtainPermanentIDs(for: [book])
        book.dateAdded = Date()
        // Store the canonical ISBN-13 so a hand-typed ISBN-10 and a scanned EAN-13
        // of the same book always match.
        book.isbn = ISBNValidator.canonicalize(isbn)
        book.title = title
        book.author = author
        book.yearPublished = yearPublished
        book.coverImageURL = coverImageURL
        book.library = library
        book.shelf = shelf
        return book
    }

    /// The lending shelf, creating it lazily if asked.
    ///
    /// Resolves to the lending shelf that lives in the **same persistent store** as
    /// the active library. A shelf from a different store must never be returned:
    /// setting `book.shelf = foreignStoreLendingShelf` creates a cross-store
    /// relationship that Core Data forbids, causing every subsequent `save()` to
    /// throw and leaving the context in a permanently dirty state.
    ///
    /// We still fetch globally (both stores) so that an orphan lending shelf
    /// migrated from the old schema — which has `library == nil` — is found and
    /// adopted. But we only return one whose store matches the active library.
    @discardableResult
    func lendingShelf(creatingIfNeeded: Bool) -> Shelf? {
        let allShelves = (try? viewContext.fetch(Shelf.fetchRequestAll())) ?? []
        // Determine which store the active library lives in; fall back to private.
        let activeStore = activeLibrary(creatingIfNeeded: false).flatMap { store(for: $0) } ?? privateStore

        // Prefer a lending shelf in the same store as the active library.
        let candidateShelves = allShelves.filter { $0.objectID.persistentStore === activeStore }
        if let existing = candidateShelves.lendingShelf {
            // Adopt an orphan lending shelf into the active library (same store only).
            if existing.library == nil,
               let library = activeLibrary(creatingIfNeeded: true),
               library.objectID.persistentStore === existing.objectID.persistentStore {
                existing.library = library
            }
            return existing
        }
        // No lending shelf in the active library's store — create one there.
        guard creatingIfNeeded else { return nil }
        return makeShelf(name: "Lent", isLendingShelf: true)
    }

    // MARK: - Mutations

    func delete(_ object: NSManagedObject) {
        viewContext.delete(object)
    }

    /// Saves the view context. Returns false when the save failed and was rolled
    /// back, so flows that must not lose data on failure (join-time move, leave
    /// restore) can keep their trigger armed instead of discarding the user's choice.
    @discardableResult
    func save() -> Bool {
        guard viewContext.hasChanges else { return true }
        do {
            try viewContext.save()
            return true
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            // Roll back so invalid changes (e.g. a cross-store relationship) don't
            // accumulate in the context and cause every subsequent save to fail too.
            viewContext.rollback()
            return false
        }
    }

    // MARK: - Launch maintenance (owner only)

    /// Owner-only structural cleanup. Participants never run this, so there is no
    /// multi-writer delete race: only the owner's device merges duplicates.
    func bootstrap() {
        // Trigger a CloudKit account-status fetch immediately so the result is cached
        // before the user taps the share button. The very first call to the CKContainer
        // performs a network round-trip (~100-300 ms) to retrieve the auth token.
        // UICloudSharingController — and our own container.share() call — both check
        // account status internally; if that token isn't ready they return a spurious
        // "not authenticated" error even when the user IS signed in.
        // Firing this here, at launch, means it's resolved long before the Share tap.
        if !inMemory { ckContainer.accountStatus { _, _ in } }

        // Cache the CloudKit user ID used to tag contributed books, and finish a
        // queued join-time move if the app was killed before it could run.
        fetchUserRecordIDIfNeeded()
        performPendingMoveIfPossible()

        // Participants (preferred library lives in the shared store) do no structural
        // maintenance — that avoids any multi-writer delete race on shared data.
        if let active = activeLibrary(creatingIfNeeded: false),
           active.objectID.persistentStore === sharedStore {
            refreshSharedState()
            return
        }
        guard let privateStore else { refreshSharedState(); return }

        let privateLibraries = ((try? viewContext.fetch(Library.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === privateStore }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        let privateShelves = ((try? viewContext.fetch(Shelf.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === privateStore }
        let privateBooks = ((try? viewContext.fetch(Book.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === privateStore }

        // Nothing of our own to maintain.
        guard !privateLibraries.isEmpty || !privateShelves.isEmpty || !privateBooks.isEmpty else {
            refreshSharedState()
            return
        }

        // Canonical library: the earliest existing one, or a fresh one created to own
        // orphaned data (e.g. records migrated from the old schema, which have no library).
        let canonical: Library
        if let first = privateLibraries.first {
            canonical = first
        } else {
            canonical = insert("Library") as! Library
            viewContext.assign(canonical, to: privateStore)
            try? viewContext.obtainPermanentIDs(for: [canonical])
            canonical.createdAt = Date()
        }

        // 1. Merge any duplicate libraries (two owner devices can each create one before
        //    the first sync) into the canonical library.
        for duplicate in privateLibraries where duplicate !== canonical {
            for shelf in Array(duplicate.shelves ?? []) { shelf.library = canonical }
            for book in Array(duplicate.books ?? []) { book.library = canonical }
            viewContext.delete(duplicate)
        }

        // 2. Adopt orphans (no library) into the canonical library. Without this they
        //    display fine (the views fetch globally) but are NOT reachable from the
        //    Library root, so they'd be silently excluded when the library is shared.
        for shelf in privateShelves where shelf.library == nil { shelf.library = canonical }
        for book in privateBooks where book.library == nil { book.library = canonical }

        // 3. Collapse ALL lending shelves into one canonical lending shelf (global, so
        //    a migrated orphan lending shelf doesn't shadow the real one in the UI).
        let lendingShelves = privateShelves
            .filter { $0.isLendingShelf }
            .sorted { ($0.dateCreated ?? .distantFuture) < ($1.dateCreated ?? .distantFuture) }
        if let keep = lendingShelves.first {
            for duplicate in lendingShelves.dropFirst() {
                for book in Array(duplicate.books ?? []) { book.shelf = keep }
                for book in Array(duplicate.previousBooks ?? []) { book.previousShelf = keep }
                viewContext.delete(duplicate)
            }
        }

        // 4. Canonicalize legacy ISBN-10s to ISBN-13, so barcode scans (always EAN-13)
        //    and ISBN searches match books that were originally entered by hand.
        for book in privateBooks {
            let canonical = ISBNValidator.canonicalize(book.isbn)
            if book.isbn != canonical { book.isbn = canonical }
        }

        // NOTE: we deliberately do NOT auto-merge same-ISBN books. Two Book records with
        // the same ISBN may be intentional (a user owning two copies), so silently
        // deleting one would be data loss; a concurrent-scan duplicate is rare and visible.

        save()
        refreshSharedState()
    }

    // MARK: - Sharing

    func existingShare(for library: Library) -> CKShare? {
        guard !inMemory else { return nil }
        return (try? container.fetchShares(matching: [library.objectID]))?[library.objectID]
    }

    /// True when the current user owns the library (their data is in the private store).
    func isOwner(_ library: Library) -> Bool {
        library.objectID.persistentStore === privateStore
    }

    /// Ensures a `CKShare` exists for the library (creating it if needed), then hands
    /// it back on the main queue so the UI can present `UICloudSharingController`.
    /// Using a pre-created share avoids the deprecated preparation-handler initializer.
    func prepareShare(for library: Library, completion: @escaping (CKShare?) -> Void) {
        if let existing = existingShare(for: library) {
            completion(existing)
            return
        }
        // Only the owner can create a share. A participant (library in the shared
        // store) must already have a share record; if not, do nothing rather than
        // attempt to share data they don't own.
        guard isOwner(library) else {
            completion(nil)
            return
        }
        container.share([library], to: nil) { [weak self] _, share, _, error in
            if let error {
                logger.error("Failed to create share: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.refreshSharedState()
                completion(share)
            }
        }
    }

    /// Removes the active library's share if it was created but never used (the owner
    /// is still the only participant). Deleting the share record is the supported way
    /// to stop sharing, so this just cleans up an abandoned "Share…" tap. Best-effort.
    func removeUnusedShareIfNeeded() {
        guard let library = activeLibrary(creatingIfNeeded: false),
              isOwner(library),
              let share = existingShare(for: library),
              share.participants.allSatisfy({ $0.role == .owner }) else { return }
        ckContainer.privateCloudDatabase.delete(withRecordID: share.recordID) { [weak self] _, error in
            if let error {
                logger.error("Failed to remove unused share: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { self?.refreshSharedState() }
        }
    }

    func refreshSharedState() {
        // viewContext access must happen on the main queue; re-enter there if needed.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshSharedState() }
            return
        }
        guard let library = activeLibrary(creatingIfNeeded: false) else {
            isLibraryShared = false
            return
        }
        // Participant side is a cheap, local check.
        if library.objectID.persistentStore === sharedStore {
            isLibraryShared = true
            return
        }
        // Owner side needs fetchShares — run it off the main thread (read-only, and the
        // objectID is permanent so it's safe to pass across threads), then publish back.
        let objectID = library.objectID
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let participantCount = (try? self.container.fetchShares(matching: [objectID]))?[objectID]?.participants.count ?? 0
            DispatchQueue.main.async { self.isLibraryShared = participantCount > 1 }
        }
    }

    /// True when the user already owns a library they're actively sharing with others.
    private func ownsActivelySharedLibrary() -> Bool {
        let libraries = (try? viewContext.fetch(Library.fetchRequestAll())) ?? []
        return libraries.contains { library in
            guard library.objectID.persistentStore === privateStore else { return false }
            if let share = existingShare(for: library) { return share.participants.count > 1 }
            return false
        }
    }

    /// Accept a share invitation (called when a family member taps the share link).
    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore else {
            logger.error("Cannot accept share: shared store not loaded")
            return
        }
        // Don't let someone who is already sharing their *own* library join another —
        // it would redirect their writes to the joined library and confuse everyone.
        // We simply don't import the share and explain why.
        if ownsActivelySharedLibrary() {
            DispatchQueue.main.async { [weak self] in
                self?.joinBlockedReason = String(localized: "You're already sharing your own library. Stop sharing it before joining another library.")
            }
            return
        }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            if let error {
                logger.error("Failed to accept share: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    // A fresh join always starts with a clean slate: a Move armed for a
                    // PREVIOUS share that never completed must not fire against this one.
                    // The prompt below re-arms it if the user picks Move again.
                    UserDefaults.standard.set(false, forKey: Self.pendingMoveKey)
                    // Silently drop empty leftover scaffolding (a private library with
                    // no books, e.g. a lending shelf created before joining).
                    self.discardEmptyUnsharedLibraries()
                    // If real local books remain, ask the user whether to keep or
                    // delete them — never silently destroy data. No prompt otherwise.
                    let localCount = self.unsharedLocalBookCount()
                    if localCount > 0 {
                        self.pendingJoinLocalBookCount = localCount
                    }
                }
                self.refreshSharedState()
            }
        }
    }

    /// Number of books in purely-local (never shared-out) private libraries.
    private func unsharedLocalBookCount() -> Int {
        let libraries = (try? viewContext.fetch(Library.fetchRequestAll())) ?? []
        return libraries.reduce(0) { partial, library in
            guard library.objectID.persistentStore === privateStore,
                  existingShare(for: library) == nil else { return partial }
            return partial + (library.books ?? []).count
        }
    }

    /// User chose to keep their local books private after joining — dismiss the
    /// prompt and disarm any queued move (an explicit Keep overrides a Move armed for
    /// an earlier share that never completed). The books stay in the private store,
    /// hidden by the active-store visibility filter until the share ends, then
    /// reappear automatically.
    func keepLocalDataAfterJoin() {
        pendingJoinLocalBookCount = nil
        UserDefaults.standard.set(false, forKey: Self.pendingMoveKey)
    }

    /// User chose to move their local books into the shared library. The shared
    /// library may not have synced down yet (share acceptance completes before the
    /// CloudKit import), so this only ARMS the move; `performPendingMoveIfPossible`
    /// runs it — from the remote-change handler or next launch — once the destination
    /// actually exists. The flag survives relaunches.
    func moveLocalBooksIntoSharedLibrary() {
        pendingJoinLocalBookCount = nil
        UserDefaults.standard.set(true, forKey: Self.pendingMoveKey)
        performPendingMoveIfPossible()
    }

    /// Runs the armed join-time migration if the shared library has synced down.
    /// Safe to call repeatedly; no-ops unless armed and a destination exists.
    ///
    /// For every book in the user's unshared private libraries: re-create it in the
    /// shared store (shelves matched or created by NAME so the user's organization
    /// survives, lending state preserved), tag it with `contributedBy` so it can be
    /// taken back on leaving, then delete the private original (a literal move).
    func performPendingMoveIfPossible() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.pendingMoveKey) else { return }

        let libraries = (try? viewContext.fetch(Library.fetchRequestAll())) ?? []
        // Destination not imported yet — stay armed and try again on the next change.
        guard libraries.contains(where: { $0.objectID.persistentStore === sharedStore }) else { return }

        let sourceLibraries = libraries.filter {
            $0.objectID.persistentStore === privateStore && existingShare(for: $0) == nil
        }
        let tag = contributorID
        for library in sourceLibraries {
            for book in Array(library.books ?? []) {
                let targetShelf: Shelf?
                var targetPreviousShelf: Shelf?
                if book.isLent {
                    targetShelf = lendingShelf(creatingIfNeeded: true)
                    targetPreviousShelf = book.previousShelf.map { findOrCreateActiveShelf(named: $0.name) }
                } else if let shelf = book.shelf {
                    targetShelf = findOrCreateActiveShelf(named: shelf.name)
                } else {
                    targetShelf = nil
                }
                let moved = makeBook(
                    isbn: book.isbn,
                    title: book.title,
                    author: book.author,
                    yearPublished: book.yearPublished,
                    coverImageURL: book.coverImageURL,
                    shelf: targetShelf
                )
                moved.coverImageData = book.coverImageData
                moved.dateAdded = book.dateAdded
                moved.previousShelf = targetPreviousShelf
                moved.contributedBy = tag
            }
            for shelf in Array(library.shelves ?? []) { viewContext.delete(shelf) }
            for book in Array(library.books ?? []) { viewContext.delete(book) }
            viewContext.delete(library)
        }
        // Disarm only on a successful save. On failure everything was rolled back, so
        // the books are still private (hidden) and the armed flag retries later —
        // clearing it here would strand them invisible with no way to ever move.
        if save() {
            defaults.set(false, forKey: Self.pendingMoveKey)
            logger.info("Moved local books into the shared library")
        } else {
            logger.error("Join-time move failed to save; staying armed for a retry")
        }
    }

    /// A regular shelf with this name in the active library's store, creating it
    /// there if needed — used by the join-time move so shelves carry over by name.
    private func findOrCreateActiveShelf(named name: String) -> Shelf {
        let store = activeStore
        let existing = ((try? viewContext.fetch(Shelf.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === store && !$0.isLendingShelf && $0.name == name }
            .min { ($0.dateCreated ?? .distantFuture) < ($1.dateCreated ?? .distantFuture) }
        return existing ?? makeShelf(name: name)
    }

    // MARK: - Contributor identity

    /// Tag written onto contributed books: the CloudKit user record ID when known
    /// (stable across all of this user's devices), else a per-install fallback.
    private var contributorID: String {
        UserDefaults.standard.string(forKey: Self.userRecordIDKey) ?? localContributorID
    }

    /// Every tag value this user may have written (CloudKit ID and/or the local
    /// fallback used before that ID was fetched) — matched against on leave.
    private var contributorIDs: Set<String> {
        var ids: Set<String> = [localContributorID]
        if let ckID = UserDefaults.standard.string(forKey: Self.userRecordIDKey) {
            ids.insert(ckID)
        }
        return ids
    }

    private var localContributorID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.localContributorIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.localContributorIDKey)
        return id
    }

    private func fetchUserRecordIDIfNeeded() {
        guard !inMemory,
              UserDefaults.standard.string(forKey: Self.userRecordIDKey) == nil else { return }
        ckContainer.fetchUserRecordID { recordID, _ in
            guard let recordID else { return }
            UserDefaults.standard.set(recordID.recordName, forKey: Self.userRecordIDKey)
        }
    }

    // MARK: - Leaving a shared library

    /// Captures the books this user contributed at join time — with their CURRENT
    /// shelf/lending state — so the "bring them back" prompt can rebuild them.
    ///
    /// MUST run synchronously from the sharing sheet's didStopSharing delegate: the
    /// zone purge that follows a leave deletes the local shared-store records, so this
    /// is the only reliable moment the data still exists. If the OWNER revokes access
    /// remotely there is no callback and no snapshot — those books stay with the
    /// family, by design. On the owner's own "stop sharing" this finds no tagged books
    /// in the shared store (their library lives in the private store) and does nothing.
    func captureLeaveSnapshotIfNeeded() {
        guard let sharedStore else { return }
        let ids = contributorIDs
        let mine = ((try? viewContext.fetch(Book.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === sharedStore }
            .filter { book in book.contributedBy.map(ids.contains) ?? false }
        guard !mine.isEmpty else { return }

        pendingLeaveSnapshot = mine.map { book in
            ContributedBookSnapshot(
                isbn: book.isbn,
                title: book.title,
                author: book.author,
                yearPublished: book.yearPublished,
                coverImageURL: book.coverImageURL,
                coverImageData: book.coverImageData,
                dateAdded: book.dateAdded,
                shelfName: book.isLent ? nil : book.shelf?.name,
                isLent: book.isLent,
                previousShelfName: book.isLent ? book.previousShelf?.name : nil
            )
        }
    }

    /// User chose to leave their contributed books with the family.
    func discardLeaveSnapshot() {
        pendingLeaveSnapshot = nil
    }

    /// Rebuilds the contributed books in the user's private library from the snapshot
    /// taken at leave time. Targets the private store EXPLICITLY: the shared store may
    /// still be mid-purge, so `activeLibrary` can't be trusted to have flipped back.
    func restoreContributedBooks() {
        guard let snapshot = pendingLeaveSnapshot else { return }
        pendingLeaveSnapshot = nil
        guard let privateStore else { return }

        // Canonical private library, created fresh if the user moved everything out.
        let library: Library
        let privateLibraries = ((try? viewContext.fetch(Library.fetchRequestAll())) ?? [])
            .filter { $0.objectID.persistentStore === privateStore }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let first = privateLibraries.first {
            library = first
        } else {
            library = insert("Library") as! Library
            viewContext.assign(library, to: privateStore)
            try? viewContext.obtainPermanentIDs(for: [library])
            library.createdAt = Date()
        }

        // Find-or-create within the private store, by name (lending shelf by flag).
        func privateShelf(named name: String, isLending: Bool) -> Shelf {
            let existing = ((try? viewContext.fetch(Shelf.fetchRequestAll())) ?? [])
                .filter {
                    $0.objectID.persistentStore === privateStore
                        && $0.isLendingShelf == isLending
                        && (isLending || $0.name == name)
                }
                .min { ($0.dateCreated ?? .distantFuture) < ($1.dateCreated ?? .distantFuture) }
            if let existing {
                if existing.library == nil { existing.library = library }
                return existing
            }
            return insertShelf(name: name, isLendingShelf: isLending, library: library, store: privateStore)
        }

        for item in snapshot {
            let book = insert("Book") as! Book
            viewContext.assign(book, to: privateStore)
            try? viewContext.obtainPermanentIDs(for: [book])
            book.isbn = item.isbn
            book.title = item.title
            book.author = item.author
            book.yearPublished = item.yearPublished
            book.coverImageURL = item.coverImageURL
            book.coverImageData = item.coverImageData
            book.dateAdded = item.dateAdded
            book.library = library
            if item.isLent {
                book.shelf = privateShelf(named: "Lent", isLending: true)
                if let previousName = item.previousShelfName {
                    book.previousShelf = privateShelf(named: previousName, isLending: false)
                }
            } else if let shelfName = item.shelfName {
                book.shelf = privateShelf(named: shelfName, isLending: false)
            }
        }
        // On failure the rollback removed everything just built; put the snapshot
        // back so the prompt reappears and the books aren't silently lost.
        if !save() {
            logger.error("Leave-share restore failed to save; re-presenting the prompt")
            pendingLeaveSnapshot = snapshot
        }
        refreshSharedState()
    }

    /// Removes empty (no-books) unshared private libraries — leftover scaffolding such
    /// as a lending shelf created before the user joined someone else's library. Books
    /// are never touched here, so this is safe to run silently.
    private func discardEmptyUnsharedLibraries() {
        let libraries = (try? viewContext.fetch(Library.fetchRequestAll())) ?? []
        var changed = false
        for library in libraries where library.objectID.persistentStore === privateStore {
            guard existingShare(for: library) == nil, (library.books ?? []).isEmpty else { continue }
            for shelf in Array(library.shelves ?? []) { viewContext.delete(shelf) }
            viewContext.delete(library)
            changed = true
        }
        if changed { save() }
    }
}
