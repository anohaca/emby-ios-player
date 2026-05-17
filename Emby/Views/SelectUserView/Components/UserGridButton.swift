//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension SelectUserView {

    struct UserGridButton: View {

        @Default(.accentColor)
        private var accentColor

        @Environment(\.isEditing)
        private var isEditing
        @Environment(\.isSelected)
        private var isSelected

        private let user: UserState
        private let server: ServerState
        private let showServer: Bool
        private let action: () -> Void
        private let onDelete: () -> Void

        init(
            user: UserState,
            server: ServerState,
            showServer: Bool,
            action: @escaping () -> Void,
            onDelete: @escaping () -> Void
        ) {
            self.user = user
            self.server = server
            self.showServer = showServer
            self.action = action
            self.onDelete = onDelete
        }

        private var labelForegroundStyle: some ShapeStyle {
            guard isEditing else { return .primary }

            return isSelected ? .primary : .secondary
        }

        private var avatarSide: CGFloat {
            UIDevice.isPhone ? 150 : 190
        }

        private var checkmarkSide: CGFloat {
            UIDevice.isPhone ? 30 : 36
        }

        var body: some View {
            Button(action: action) {
                VStack(spacing: 10) {
                    UserProfileImage(
                        userID: user.id,
                        source: user.profileImageSource(
                            client: server.embySessionClient(userID: user.id, accessToken: user.accessToken)
                        ),
                        pipeline: .Emby.local
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isEditing, isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: checkmarkSide, height: checkmarkSide, alignment: .bottomTrailing)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(accentColor.overlayColor, accentColor)
                        }
                    }
                    .frame(width: avatarSide, height: avatarSide)

                    Text(user.username)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(labelForegroundStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if showServer {
                        Text(server.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: UIDevice.isPhone ? 190 : 240)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !isEditing {
                    Button(
                        L10n.delete,
                        role: .destructive,
                        action: onDelete
                    )
                }
            }
        }
    }
}
