//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import SwiftUI

struct SettingsView: View {

    @Router
    var router

    #if os(iOS)
    @Default(.userAccentColor)
    private var accentColor
    #else
    @Default(.accentColor)
    private var accentColor
    #endif

    @StateObject
    private var viewModel = SettingsViewModel()

    // MARK: - Body

    var body: some View {
        Form(image: .embyBlobBlue) {
            serverSection
            videoPlayerSection
            customizeSection
            diagnosticsSection
        }
        #if os(iOS)
        .navigationTitle(L10n.settings)
        .navigationBarCloseButton {
            router.dismiss()
        }
        #endif
    }

    // MARK: - Server Section

    @ViewBuilder
    private var serverSection: some View {
        if let userSession = viewModel.userSession {
            Section {
                UserProfileRow(user: userSession.user.data) {
                    router.route(to: .localUserSettings(viewModel: viewModel))
                }

                ChevronButton(
                    L10n.server,
                    action: {
                        router.route(to: .editServer(server: userSession.server))
                    }
                ) {
                    EmptyView()
                } subtitle: {
                    Label {
                        Text(userSession.server.name)
                    } icon: {
                        if !userSession.server.isVersionCompatible {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                    }
                    .labelStyle(.sectionFooterWithImage(imageStyle: .orange))
                }

                #if os(iOS)
                if userSession.user.data.policy?.isAdministrator == true {
                    ChevronButton(L10n.dashboard) {
                        router.route(to: .adminDashboard)
                    }
                }
                #endif
            }

            Section {
                Button(L10n.switchUser) {
                    UIDevice.impact(.medium)
                    viewModel.signOut()
                    router.dismiss()
                }
                .buttonStyle(.primary)
                .foregroundStyle(accentColor.overlayColor, accentColor)
            }
        }
    }

    // MARK: - Video Player Section

    @ViewBuilder
    private var videoPlayerSection: some View {
        Section(L10n.videoPlayer) {
            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            ChevronButton(L10n.subtitle) {
                router.route(to: .subtitleSettings)
            }

        }
    }

    // MARK: - Customization Section

    @ViewBuilder
    private var customizeSection: some View {
        Section {
            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)

            ChevronButton(L10n.advanced) {
                router.route(to: .customizeSettingsView)
            }
        } header: {
            Text(L10n.customize)
        } footer: {
            Text(L10n.viewsMayRequireRestart)
        }
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {

            if ExperimentalSettingsView.isEnabled {
                ChevronButton(L10n.experimental) {
                    router.route(to: .experimentalSettings)
                }
            }

            ChevronButton(L10n.logs) {
                router.route(to: .log)
            }

            ChevronButton("缓存统计") {
                router.route(to: .cacheStatistics)
            }

            #if DEBUG
            ChevronButton("Debug") {
                router.route(to: .debugSettings)
            }
            #endif
        }
    }
}
