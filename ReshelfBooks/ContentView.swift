//
//  ContentView.swift
//  ReshelfBooks
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @State private var selectedTab = 1
    @State private var showingSearch = false

    /// The family-sharing alerts, collapsed into one case set so a single `.alert`
    /// modifier drives them — three separate `.alert` modifiers on one view can
    /// compete for the single presentation slot if two conditions are ever set at once.
    private enum LibraryAlert: Identifiable {
        case joinedSharedLibrary(bookCount: Int)
        case leftSharedLibrary(bookCount: Int)
        case joinBlocked(reason: String)

        var id: Int {
            switch self {
            case .joinedSharedLibrary: 0
            case .leftSharedLibrary: 1
            case .joinBlocked: 2
            }
        }

        var title: String {
            switch self {
            case .joinedSharedLibrary: String(localized: "Joined Shared Library")
            case .leftSharedLibrary: String(localized: "Left Shared Library")
            case .joinBlocked: String(localized: "Can't Join Library")
            }
        }
    }

    /// The single alert to show, derived from persistence's published state. Priority
    /// order resolves the (practically impossible) case where more than one is set.
    private var activeAlert: LibraryAlert? {
        if let reason = persistence.joinBlockedReason { return .joinBlocked(reason: reason) }
        if let count = persistence.pendingJoinLocalBookCount { return .joinedSharedLibrary(bookCount: count) }
        if let snapshot = persistence.pendingLeaveSnapshot { return .leftSharedLibrary(bookCount: snapshot.count) }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            TabView(selection: $selectedTab) {
                ScannerTabView(isTabActive: selectedTab == 0)
                    .tag(0)

                LibraryTabView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom floating tab bar with search button
            floatingTabBar
        }
        .sheet(isPresented: $showingSearch) {
            SearchView()
                .standardSheetPresentation()
        }
        // One family-sharing alert. The buttons are the sole drivers of the outcome;
        // the isPresented setter is intentionally a no-op so dismissing can never undo a
        // button's choice — e.g. "Move Into Shared Library" arms the move, and a "keep"
        // side effect in the setter would silently disarm it. Alerts only dismiss via
        // their buttons (which already clear the underlying state), so nothing is lost.
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(get: { activeAlert != nil }, set: { _ in }),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .joinedSharedLibrary:
                Button("Keep My Books Private") { persistence.keepLocalDataAfterJoin() }
                Button("Move Into Shared Library") { persistence.moveLocalBooksIntoSharedLibrary() }
            case .leftSharedLibrary:
                Button("Bring Them Back") { persistence.restoreContributedBooks() }
                Button("Leave Them", role: .destructive) { persistence.discardLeaveSnapshot() }
            case .joinBlocked:
                Button("OK", role: .cancel) { persistence.joinBlockedReason = nil }
            }
        } message: { alert in
            switch alert {
            case .joinedSharedLibrary(let count):
                // Inflection markup pluralizes "book" with the count and stays localizable.
                Text("You have ^[\(count) book](inflect: true) in your own library. Keep them private, or move them into the shared library?")
            case .leftSharedLibrary(let count):
                Text("You brought ^[\(count) book](inflect: true) into the shared library. Bring them back to your library?")
            case .joinBlocked(let reason):
                Text(reason)
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 12) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton(title: "Scan", icon: "barcode.viewfinder", tag: 0)
                tabButton(title: "Library", icon: "books.vertical", tag: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

            // Search button (always visible)
            Button {
                showingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(22)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            }
        }
        .padding(.bottom, 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
    }

    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))

                if selectedTab == tag {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(selectedTab == tag ? .accentColor : .secondary)
            .padding(.horizontal, selectedTab == tag ? 16 : 12)
            .padding(.vertical, 10)
            .background(selectedTab == tag ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
