//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import Defaults
import Factory
import SwiftUI

struct UserSignInView: View {

    private enum Field: Hashable {
        case username
        case password
    }

    @Environment(\.localUserAuthenticationAction)
    private var authenticationAction

    @FocusState
    private var focusedTextField: Field?

    @Router
    private var router

    @State
    private var accessPolicy: UserAccessPolicy = .none
    @State
    private var existingUser: UserSignInViewModel.UserStateDataPair? = nil
    @State
    private var isPresentingExistingUser: Bool = false
    @State
    private var password: String = ""
    @State
    private var isCompletingSignIn: Bool = false
    @State
    private var pinHint: String = ""
    @State
    private var username: String = ""

    @StateObject
    private var viewModel: UserSignInViewModel

    private let initialUsername: String
    private let reauthenticatingUserID: String?

    init(
        server: ServerState,
        username: String = "",
        reauthenticatingUserID: String? = nil
    ) {
        self.initialUsername = username
        self.reauthenticatingUserID = reauthenticatingUserID
        self._username = State(initialValue: username)
        self._viewModel = StateObject(wrappedValue: UserSignInViewModel(server: server))
    }

    private func handleEvent(_ event: UserSignInViewModel._Event) {
        switch event {
        case let .connected(user):
            guard let authenticationAction else {
                #if DEBUG
                NSLog("EmbySignIn connected user=%@ but missing local authentication action", user.state.state.id)
                #endif
                return
            }
            #if DEBUG
            NSLog("EmbySignIn connected user=%@ server=%@", user.state.state.id, user.state.state.serverID)
            #endif
            viewModel.save(
                user: user,
                authenticationAction: (
                    authenticationAction,
                    accessPolicy,
                    accessPolicy.createReason(
                        user: user.state.state
                    )
                ),
                evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
            )
        case let .existingUser(existingUser):
            if shouldReplaceTokenAfterReauthentication(existingUser),
               let authenticationAction
            {
                let userState = existingUser.state.state
                let existingUserAccessPolicy = userState.accessPolicy

                viewModel.saveExisting(
                    user: existingUser,
                    replaceForAccessToken: true,
                    authenticationAction: (
                        authenticationAction,
                        existingUserAccessPolicy,
                        existingUserAccessPolicy.authenticateReason(
                            user: userState
                        )
                    ),
                    evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
                )

                return
            }

            #if DEBUG
            NSLog("EmbySignIn existing user=%@ presenting duplicate prompt", existingUser.state.state.id)
            #endif
            self.existingUser = existingUser
            self.isPresentingExistingUser = true
        case let .saved(user):
            UIDevice.feedback(.success)

            #if DEBUG
            NSLog("EmbySignIn saved user=%@ server=%@", user.id, user.serverID)
            #endif
            dismissThenCompleteSignIn(user: user)
        }
    }

    private func shouldReplaceTokenAfterReauthentication(_ user: UserSignInViewModel.UserStateDataPair) -> Bool {
        guard user.state.state.id == reauthenticatingUserID else { return false }
        return user.state.state.accessTokenIfAvailable?.isEmpty != false
    }

    private func processEvaluatedPolicy(
        _ evaluatedPolicy: any EvaluatedLocalUserAccessPolicy
    ) -> any EvaluatedLocalUserAccessPolicy {
        if let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy {
            return PinEvaluatedUserAccessPolicy(
                pin: pinPolicy.pin,
                pinHint: pinHint
            )
        }

        return evaluatedPolicy
    }

    private func dismissThenCompleteSignIn(user: UserState) {
        guard !isCompletingSignIn else { return }

        isCompletingSignIn = true
        focusedTextField = nil
        router.dismiss(afterPresentationDismiss: {
            completeSignIn(user: user, source: "presentation-dismiss")
        })
    }

    private func completeSignIn(user: UserState, source: String) {
        Defaults[.lastSignedInUserID] = .signedIn(userID: user.id)
        Container.shared.currentUserSession.reset()

        #if DEBUG
        NSLog("EmbySignIn completed source=%@ user=%@ server=%@", source, user.id, user.serverID)
        #endif

        Notifications[.didSignIn].post()
    }

    #if DEBUG
    private func debugSavedSignInSmokeUser() -> UserState? {
        StoredValues[.User.users].first { user in
            user.serverID == viewModel.server.id && (initialUsername.isEmpty || user.username == initialUsername)
        } ?? StoredValues[.User.users].first { user in
            user.serverID == viewModel.server.id
        }
    }
    #endif

    // MARK: - Sign In Section

    @ViewBuilder
    private var signInSection: some View {
        Section {
            #if os(iOS)
            _LoginTextField(L10n.username, text: $username)
                .onSubmit {
                    focusedTextField = .password
                }
                .focused($focusedTextField, equals: .username)
            #else
            TextField(L10n.username, text: $username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedTextField, equals: .username)
                .onSubmit {
                    focusedTextField = .password
                }
            #endif

            SecureField(
                L10n.password,
                text: $password,
                maskToggle: .enabled
            )
            .onSubmit {
                focusedTextField = nil

                viewModel.signIn(
                    username: username,
                    password: password
                )
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedTextField, equals: .password)
        } header: {
            Text(L10n.signInToServer(viewModel.server.name))
        } footer: {
            switch accessPolicy {
            case .requireDeviceAuthentication:
                Label(L10n.userDeviceAuthRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
            case .requirePin:
                Label(L10n.userPinRequiredDescription, systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
            case .none:
                EmptyView()
            }
        }

        if case .signingIn = viewModel.state {
            Button(L10n.cancel, role: .cancel) {
                viewModel.cancel()
            }
            .buttonStyle(.primary)
            .frame(maxHeight: 75)
        } else {
            Button(L10n.signIn) {
                viewModel.signIn(
                    username: username,
                    password: password
                )
            }
            .buttonStyle(.primary)
            .frame(maxHeight: 75)
            .disabled(username.isEmpty)
            .foregroundStyle(
                Color.embyPurple.overlayColor,
                Color.embyPurple
            )
            .opacity(username.isEmpty ? 0.5 : 1)
        }

        if let disclaimer = viewModel.serverDisclaimer {
            Section(L10n.disclaimer) {
                Text(disclaimer)
                    .font(.callout)
            }
        }
    }

    // MARK: - Public Users Section

    @ViewBuilder
    private var publicUsersSection: some View {
        Section(L10n.publicUsers) {
            if viewModel.publicUsers.isEmpty {
                Text(L10n.noPublicUsers)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                #if os(iOS)
                ForEach(viewModel.publicUsers) { user in
                    ChevronButton {
                        username = user.name ?? ""
                        password = ""
                        focusedTextField = .password
                    } label: {
                        LabeledContent {
                            EmptyView()
                        } label: {
                            HStack {
                                UserProfileImage(
                                    userID: user.id,
                                    source: user.profileImageSource(
                                        client: viewModel.server.embySessionClient(userID: user.id ?? ""),
                                        maxWidth: 120
                                    )
                                )
                                .frame(width: 50, height: 50)

                                Text(user.name ?? .emptyDash)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                #else
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 30
                ) {
                    ForEach(viewModel.publicUsers) { user in
                        UserButton(
                            user: user,
                            client: viewModel.server.embySessionClient(userID: user.id ?? "")
                        ) {
                            username = user.name ?? ""
                            password = ""
                            focusedTextField = .password
                        }
                        .environment(\.isOverComplexContent, true)
                    }
                }
                #endif
            }
        }
        .disabled(viewModel.state == .signingIn)
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(iOS)
        List {
            signInSection
            publicUsersSection
        }
        .scrollContentBackground(.hidden)
        .background(EmbyAppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .signingIn) {
            router.dismiss()
        }
        .topBarTrailing {
            if viewModel.state == .signingIn || viewModel.background.is(.gettingPublicData) {
                ProgressView()
            }

            Button(L10n.security, systemImage: "gearshape.fill") {
                router.route(
                    to: .userSecurity(
                        pinHint: $pinHint,
                        accessPolicy: $accessPolicy
                    )
                )
            }
        }
        #else
        SplitLoginWindowView(
            isLoading: viewModel.state == .signingIn,
            backgroundImageSource: viewModel.server.splashScreenImageSource
        ) {
            signInSection
        } trailingContentView: {
            publicUsersSection
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(L10n.signIn.localizedCapitalized)
            .interactiveDismissDisabled(viewModel.state == .signingIn)
            .onReceive(viewModel.events, perform: handleEvent)
            .onFirstAppear {
                focusedTextField = initialUsername.isEmpty ? .username : .password
                viewModel.getPublicData()

                #if DEBUG
                if let credentials = debugRealSignInSmokeCredentials() {
                    username = credentials.username
                    password = credentials.password

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        await viewModel.signIn(
                            username: credentials.username,
                            password: credentials.password
                        )
                    }
                } else if ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInSavedDismissSmoke") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard let user = debugSavedSignInSmokeUser() else {
                            NSLog("USER_SIGN_IN_SAVED_DISMISS_SMOKE_FAIL missing-user")
                            return
                        }
                        dismissThenCompleteSignIn(user: user)
                    }
                } else if ProcessInfo.processInfo.arguments.contains("-EmbyUserSignInDismissSmoke") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        router.dismiss()
                    }
                }
                #endif
            }
            .alert(
                L10n.duplicateUser,
                isPresented: $isPresentingExistingUser,
                presenting: existingUser
            ) { existingUser in

                let userState = existingUser.state.state
                let existingUserAccessPolicy = userState.accessPolicy

                Button(L10n.signIn) {
                    viewModel.saveExisting(
                        user: existingUser,
                        replaceForAccessToken: false,
                        authenticationAction: (
                            authenticationAction!,
                            existingUserAccessPolicy,
                            existingUserAccessPolicy.authenticateReason(
                                user: userState
                            )
                        ),
                        evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
                    )
                }

                Button(L10n.replace) {
                    viewModel.saveExisting(
                        user: existingUser,
                        replaceForAccessToken: true,
                        authenticationAction: (
                            authenticationAction!,
                            existingUserAccessPolicy,
                            existingUserAccessPolicy.authenticateReason(
                                user: userState
                            )
                        ),
                        evaluatedPolicyMap: .init(action: processEvaluatedPolicy)
                    )
                }

                Button(L10n.dismiss, role: .cancel) {}
            } message: { existingUser in
                Text(L10n.duplicateUserSaved(existingUser.state.state.username))
            }
            #if DEBUG
            .onReceive(viewModel.$error) { error in
                guard let error else { return }
                NSLog("EmbySignIn error=%@", error.localizedDescription)
            }
            #endif
            .errorMessage($viewModel.error)
    }
}

#if DEBUG
private extension UserSignInView {

    func debugRealSignInSmokeCredentials() -> (username: String, password: String)? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let username = arguments.value(after: "-EmbyUserSignInRealSmokeUsername"),
              let password = arguments.value(after: "-EmbyUserSignInRealSmokePassword")
        else {
            return nil
        }

        return (username, password)
    }
}

private extension [String] {

    func value(after argument: String) -> String? {
        guard let index = firstIndex(of: argument) else { return nil }
        let valueIndex = self.index(after: index)
        guard indices.contains(valueIndex) else { return nil }
        return self[valueIndex]
    }
}
#endif
