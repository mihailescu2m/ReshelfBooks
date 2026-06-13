//
//  ContentView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @State private var selectedTab = 1
    @State private var showingSearch = false

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
        // Shown only after joining a shared library while the joiner still has local
        // books: park them privately (hidden until the share ends) or move them in.
        .alert("Joined Shared Library", isPresented: Binding(
            get: { persistence.pendingJoinLocalBookCount != nil },
            set: { if !$0 { persistence.keepLocalDataAfterJoin() } }
        )) {
            Button("Keep My Books Private") { persistence.keepLocalDataAfterJoin() }
            Button("Move Into Shared Library") { persistence.moveLocalBooksIntoSharedLibrary() }
        } message: {
            Text(joinPromptMessage)
        }
        // Shown when a participant leaves a shared library they had moved books into:
        // bring those books back (with their current shelves) or leave them behind.
        .alert("Left Shared Library", isPresented: Binding(
            get: { persistence.pendingLeaveSnapshot != nil },
            set: { if !$0 { persistence.discardLeaveSnapshot() } }
        )) {
            Button("Bring Them Back") { persistence.restoreContributedBooks() }
            Button("Leave Them", role: .destructive) { persistence.discardLeaveSnapshot() }
        } message: {
            Text(leavePromptMessage)
        }
        // Shown when a share invitation is declined because the user already owns a
        // shared library of their own.
        .alert("Can't Join Library", isPresented: Binding(
            get: { persistence.joinBlockedReason != nil },
            set: { if !$0 { persistence.joinBlockedReason = nil } }
        )) {
            Button("OK", role: .cancel) { persistence.joinBlockedReason = nil }
        } message: {
            Text(persistence.joinBlockedReason ?? "")
        }
    }

    private var joinPromptMessage: String {
        let count = persistence.pendingJoinLocalBookCount ?? 0
        let books = count == 1 ? "book" : "books"
        return "You have \(count) \(books) in your own library. "
            + "Keep them private, or move them into the shared library?"
    }

    private var leavePromptMessage: String {
        let count = persistence.pendingLeaveSnapshot?.count ?? 0
        let books = count == 1 ? "book" : "books"
        return "You brought \(count) \(books) into the shared library. "
            + "Bring them back to your library?"
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
            .cornerRadius(25)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

            // Search button (always visible)
            Button {
                showingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
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
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
