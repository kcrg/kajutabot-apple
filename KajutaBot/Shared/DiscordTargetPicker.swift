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
                        title: .discordServer,
                        value: app.selectedGuild.map { SelectionValue.verbatim($0.name) } ?? .localized(.chooseServer)
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                if app.voiceChannels.isEmpty {
                    Text(app.isLoadingVoiceChannels ? String(localized: .loading) : String(localized: .noVoiceChannels))
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
                    title: .voiceChannel,
                    value: app.selectedVoiceChannel.map { SelectionValue.verbatim($0.name) } ?? .localized(app.isLoadingVoiceChannels ? LocalizedStringResource.loading : .chooseChannel)
                )
            }
            .buttonStyle(.plain)
            .disabled(app.selectedGuildId == nil || app.isLoadingVoiceChannels)
        }
    }
}

private enum SelectionValue {
    case localized(LocalizedStringResource)
    case verbatim(String)

    @ViewBuilder
    var text: some View {
        switch self {
        case let .localized(resource): Text(resource)
        case let .verbatim(value): Text(verbatim: value)
        }
    }
}

private struct SelectionRow: View {
    let icon: String
    let title: LocalizedStringResource
    let value: SelectionValue

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
                value.text
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
