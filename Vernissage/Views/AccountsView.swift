//
//  https://mczachurski.dev
//  Copyright © 2023 Marcin Czachurski and the repository contributors.
//  Licensed under the MIT License.
//
    
import SwiftUI
import MastodonKit
import Foundation

struct AccountsView: View {
    public enum ListType {
        case followers
        case following
        case reblogged
        case favourited
    }
    
    @EnvironmentObject var applicationState: ApplicationState
    @EnvironmentObject var client: Client

    @State var entityId: String
    @State var listType: ListType

    @State private var accounts: [Account] = []
    @State private var downloadedPage = 1
    @State private var allItemsLoaded = false
    @State private var state: ViewState = .loading
    
    var body: some View {
        self.mainBody()
            .navigationBarTitle(self.getTitle())
    }
    
    @ViewBuilder
    private func mainBody() -> some View {
        switch state {
        case .loading:
            LoadingIndicator()
                .task {
                    await self.loadAccounts(page: self.downloadedPage)
                }
        case .loaded:
            if self.accounts.isEmpty {
                NoDataView(imageSystemName: "person.3.sequence", text: "Unfortunately, there is no one here.")
            } else {
                List {
                    ForEach(accounts, id: \.id) { account in
                        NavigationLink(value: RouteurDestinations.userProfile(
                            accountId: account.id,
                            accountDisplayName: account.displayNameWithoutEmojis,
                            accountUserName: account.acct)
                        ) {
                            UsernameRow(accountId: account.id,
                                        accountAvatar: account.avatar,
                                        accountDisplayName: account.displayNameWithoutEmojis,
                                        accountUsername: account.acct)
                        }
                    }
                    
                    if allItemsLoaded == false {
                        HStack {
                            Spacer()
                            LoadingIndicator()
                                .task {
                                    self.downloadedPage = self.downloadedPage + 1
                                    await self.loadAccounts(page: self.downloadedPage)
                                }
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        case .error(let error):
            ErrorView(error: error) {
                self.state = .loading
                
                self.downloadedPage = 1
                self.allItemsLoaded = false
                self.accounts = []
                await self.loadAccounts(page: self.downloadedPage)
            }
            .padding()
        }
    }
    
    private func loadAccounts(page: Int) async {
        do {
            let accountsFromApi = try await self.loadFromApi(page: page)

            if accountsFromApi.isEmpty {
                self.allItemsLoaded = true
                return
            }
            
            await self.downloadAvatars(accounts: accountsFromApi)
            self.accounts.append(contentsOf: accountsFromApi)
            
            self.state = .loaded
        } catch {
            if !Task.isCancelled {
                ErrorService.shared.handle(error, message: "Error during download followers from server.", showToastr: true)
                self.state = .error(error)
            } else {
                ErrorService.shared.handle(error, message: "Error during download followers from server.", showToastr: false)
            }
        }
    }
    
    private func getTitle() -> String {
        switch self.listType {
        case .followers:
            return "Followers"
        case .following:
            return "Following"
        case .favourited:
            return "Favourited by"
        case .reblogged:
            return "Reboosted by"
        }
    }
    
    private func loadFromApi(page: Int) async throws -> [Account] {
        switch self.listType {
        case .followers:
            return try await self.client.accounts?.followers(account: self.entityId, page: page) ?? []
        case .following:
            return try await self.client.accounts?.following(account: self.entityId, page: page) ?? []
        case .favourited:
            return try await self.client.statuses?.favouritedBy(statusId: self.entityId, page: page) ?? []
        case .reblogged:
            return try await self.client.statuses?.rebloggedBy(statusId: self.entityId, page: page) ?? []
        }
    }
    
    private func downloadAvatars(accounts: [Account]) async {
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { await CacheImageService.shared.download(url: account.avatar) }
            }
        }
    }
}
