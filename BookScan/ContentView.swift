//
//  ContentView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
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
        .modelContainer(for: [Book.self, Shelf.self], inMemory: true)
}
