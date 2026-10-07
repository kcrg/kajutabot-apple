import SwiftUI

struct DiscordSelectionView: View {
    let app: AppState
    let done: () -> Void

    var body: some View {
        List {
            if !app.isGuest {
                Section(.discordServer) {
                    ForEach(app.guilds) { guild in
                        Button { app.selectGuild(guild.id) } label: {
                            HStack {
                                ArtworkView(urlString: guild.iconUrl, layout: .square(36), cornerRadius: 8)
                                Text(guild.name).foregroundStyle(Color.primary)
                                Spacer()
                                if app.selectedGuildId == guild.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(app.selectedGuildId == guild.id ? .isSelected : [])
                    }
                }
            }
            Section(.voiceChannel) {
                if app.isLoadingVoiceChannels {
                    ProgressView { Text(.loading) }
                } else if app.voiceChannels.isEmpty {
                    Text(app.selectedGuildId == nil ? String(localized: .chooseServer) : String(localized: .noVoiceChannels))
                        .foregroundStyle(.secondary)
                    Button(.refresh) { app.refreshGuilds() }
                } else {
                    ForEach(app.voiceChannels) { channel in
                        Button { app.selectVoiceChannel(channel.id) } label: {
                            HStack {
                                Label(channel.name, systemImage: "waveform.circle").foregroundStyle(Color.primary)
                                Spacer()
                                if app.selectedVoiceChannelId == channel.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(app.selectedVoiceChannelId == channel.id ? .isSelected : [])
                    }
                }
            }
        }
        .adaptiveContentWidth(AppLayout.settingsContentMaxWidth)
        .navigationTitle(.serverChannelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(.cancel, action: done) }
            ToolbarItem(placement: .confirmationAction) { Button(.done, action: done).disabled(!app.hasDiscordTarget || app.isLoadingVoiceChannels) }
        }
        .operationError(app)
    }
}
