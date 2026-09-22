import SwiftUI

struct DiscordTargetPicker: View {
    let app: AppState
    var showGuildPicker = true

    var body: some View {
        VStack(spacing: 14) {
            if showGuildPicker {
                Menu {
                    ForEach(app.guilds) { guild in
                        Button {
                            app.selectGuild(guild.id)
                        } label: {
                            if app.selectedGuildId == guild.id {
                                Label(guild.name, systemImage: "checkmark")
                            } else {
                                Text(guild.name)
                            }
                        }
                    }
                } label: {
                    SelectionRow(
                        icon: "server.rack",
                        title: "Serwer Discord",
                        value: app.selectedGuild?.name ?? "Wybierz serwer"
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                if app.voiceChannels.isEmpty {
                    Text(app.isLoadingVoiceChannels ? "Ładowanie…" : "Brak kanałów głosowych")
                } else {
                    ForEach(app.voiceChannels) { channel in
                        Button {
                            app.selectVoiceChannel(channel.id)
                        } label: {
                            if app.selectedVoiceChannelId == channel.id {
                                Label(channel.name, systemImage: "checkmark")
                            } else {
                                Text(channel.name)
                            }
                        }
                    }
                }
            } label: {
                SelectionRow(
                    icon: "waveform.circle",
                    title: "Kanał głosowy",
                    value: app.selectedVoiceChannel?.name ?? (app.isLoadingVoiceChannels ? "Ładowanie…" : "Wybierz kanał")
                )
            }
            .buttonStyle(.plain)
            .disabled(app.selectedGuildId == nil || app.isLoadingVoiceChannels)
        }
    }
}

private struct SelectionRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
