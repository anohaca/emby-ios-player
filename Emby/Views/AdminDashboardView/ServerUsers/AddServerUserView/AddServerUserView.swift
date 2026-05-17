//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct AddServerUserView: View {

    private enum Field {
        case username
        case password
        case confirmPassword
    }

    @FocusState
    private var focusedfield: Field?

    @Router
    private var router

    @State
    private var confirmPassword: String = ""
    @State
    private var isCompletingAdd: Bool = false
    @State
    private var password: String = ""
    @State
    private var username: String = ""

    @StateObject
    private var viewModel = AddServerUserViewModel()

    private var isValid: Bool {
        username.isNotEmpty && password == confirmPassword
    }

    private var isBusy: Bool {
        viewModel.state == .addingUser && !isCompletingAdd
    }

    private func completeAdd(user: UserDto) {
        guard !isCompletingAdd else { return }

        isCompletingAdd = true
        focusedfield = nil
        viewModel.cancel()

        router.dismiss()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            Notifications[.didAddServerUser].post(user)
        }
    }

    // MARK: - Body

    var body: some View {
        List {

            Section {
                TextField(L10n.username, text: $username) {
                    focusedfield = .password
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)
                .focused($focusedfield, equals: .username)
                .disabled(isBusy)
            } header: {
                Text(L10n.username)
            } footer: {
                if username.isEmpty {
                    Label(L10n.usernameRequired, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }
            }

            Section(L10n.password) {
                SecureField(
                    L10n.password,
                    text: $password,
                    maskToggle: .enabled
                )
                .onSubmit {
                    focusedfield = .confirmPassword
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)
                .focused($focusedfield, equals: .password)
                .disabled(isBusy)
            }

            Section {
                SecureField(
                    L10n.confirmPassword,
                    text: $confirmPassword,
                    maskToggle: .enabled
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)
                .focused($focusedfield, equals: .confirmPassword)
                .disabled(isBusy)
            } header: {
                Text(L10n.confirmPassword)
            } footer: {
                if password != confirmPassword {
                    Label(L10n.passwordsDoNotMatch, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }
            }
        }
        .animation(.linear(duration: 0.1), value: isValid)
        .interactiveDismissDisabled(isBusy)
        .navigationTitle(L10n.newUser.localizedCapitalized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: isBusy) {
            router.dismiss()
        }
        .onFirstAppear {
            focusedfield = .username

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-EmbyAddServerUserCompleteSmoke") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))

                    var user = UserDto()
                    user.id = "debug-add-server-user-complete-smoke"
                    user.name = "debug-add-server-user-complete-smoke"
                    completeAdd(user: user)
                }
            }
            #endif
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case let .created(newUser):
                UIDevice.feedback(.success)
                completeAdd(user: newUser)
            }
        }
        .topBarTrailing {
            if isBusy {
                ProgressView()
                Button(L10n.cancel) {
                    viewModel.cancel()
                }
                .buttonStyle(.toolbarPill(.red))
            } else {
                Button(L10n.save) {
                    viewModel.add(username: username, password: password)
                }
                .buttonStyle(.toolbarPill)
                .disabled(!isValid)
            }
        }
        .errorMessage($viewModel.error) {
            focusedfield = .username
        }
    }
}
