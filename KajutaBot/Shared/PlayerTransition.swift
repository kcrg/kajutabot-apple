import Observation
import SwiftUI

enum PlayerTransitionLocation: Hashable, Sendable { case player, miniPlayer }
enum PlayerTransitionPart: Hashable, Sendable { case artwork, title }

struct PlayerTransitionIdentity: Equatable, Sendable {
    let trackID: String
    let revision: Int
}

fileprivate struct PlayerElementMeasurement: Equatable, Sendable {
    let identity: PlayerTransitionIdentity
    let frame: CGRect
    let cornerRadius: CGFloat
}

/// Tab contents and the system bottom accessory have separate hosting hierarchies.
/// Carry a snapshot above both, using their actual window geometry, rather than
/// assuming matchedGeometryEffect can connect views across those hosts.
@MainActor @Observable
final class PlayerTransition {
    struct Layout: Equatable, Sendable {
        let artwork: CGRect
        let title: CGRect
        let cornerRadius: CGFloat
    }

    struct Flight: Identifiable, Sendable {
        let id = UUID()
        let identity: PlayerTransitionIdentity
        let track: PlaybackTrackResponse
        let sourceLocation: PlayerTransitionLocation
        let destinationLocation: PlayerTransitionLocation
        let source: Layout
        var destination: Layout?
        var isAtDestination = false

        var layout: Layout { isAtDestination ? destination ?? source : source }
        var showsPlayerTitle: Bool {
            (isAtDestination ? destinationLocation : sourceLocation) == .player
        }
    }

    private(set) var flight: Flight?
    @ObservationIgnored private var frames: [PlayerTransitionLocation: [PlayerTransitionPart: PlayerElementMeasurement]] = [:]
    @ObservationIgnored private var rootFrame: CGRect = .zero
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?

    func begin(from: PlayerTransitionLocation?, to: PlayerTransitionLocation?,
               track: PlaybackTrackResponse?, revision: Int, reduceMotion: Bool) {
        let interrupted = flight != nil
        cancel()
        guard !interrupted, !reduceMotion, let from, let to, from != to, let track else { return }
        let identity = PlayerTransitionIdentity(trackID: track.id, revision: revision)
        guard let source = layout(at: from, identity: identity), isVisible(source) else { return }
        // Require fresh destination measurements after the selected tab changes.
        frames.removeValue(forKey: to)
        let next = Flight(identity: identity, track: track, sourceLocation: from,
                          destinationLocation: to, source: source)
        flight = next
        fallbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard let self, self.flight?.id == next.id, self.flight?.destination == nil else { return }
            // The player may be scrolled offscreen or covered by a navigation destination.
            self.cancel()
        }
    }

    fileprivate func record(_ measurement: PlayerElementMeasurement,
                            at location: PlayerTransitionLocation, part: PlayerTransitionPart) {
        frames[location, default: [:]][part] = measurement
        guard let current = flight, current.destinationLocation == location,
              let destination = layout(at: location, identity: current.identity), isVisible(destination) else { return }
        guard current.destination != destination else { return }
        if current.isAtDestination {
            withAnimation(.smooth(duration: 0.15)) { flight?.destination = destination }
        } else {
            flight?.destination = destination
        }
    }

    func setRootFrame(_ frame: CGRect) {
        guard frame != rootFrame else { return }
        rootFrame = frame
        cancel()
    }

    func hides(_ identity: PlayerTransitionIdentity) -> Bool { flight?.identity == identity }

    func animate(id: UUID, destination: Layout) {
        guard flight?.id == id, flight?.destination == destination, flight?.isAtDestination == false else { return }
        withAnimation(.smooth(duration: 0.38), completionCriteria: .removed) {
            flight?.isAtDestination = true
        } completion: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.flight?.id == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        fallbackTask?.cancel()
        fallbackTask = nil
        flight = nil
    }

    private func layout(at location: PlayerTransitionLocation, identity: PlayerTransitionIdentity) -> Layout? {
        guard let artwork = frames[location]?[.artwork], let title = frames[location]?[.title],
              artwork.identity == identity, title.identity == identity else { return nil }
        return Layout(artwork: artwork.frame, title: title.frame, cornerRadius: artwork.cornerRadius)
    }

    private func isVisible(_ layout: Layout) -> Bool {
        layout.artwork.width > 0 && layout.artwork.height > 0 && layout.title.width > 0
            && rootFrame.contains(CGPoint(x: layout.artwork.midX, y: layout.artwork.midY))
            && rootFrame.contains(CGPoint(x: layout.title.midX, y: layout.title.midY))
    }
}

private struct PlayerTransitionElement: ViewModifier {
    @Environment(PlayerTransition.self) private var transition: PlayerTransition?
    let identity: PlayerTransitionIdentity
    let location: PlayerTransitionLocation
    let part: PlayerTransitionPart
    let cornerRadius: CGFloat
    @State private var layoutSignal: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .opacity(transition?.hides(identity) == true ? 0 : 1)
            .background {
                PlayerWindowFrameReader(layoutSignal: layoutSignal, identity: identity, refreshID: transition?.flight?.id) { frame in
                    transition?.record(PlayerElementMeasurement(identity: identity, frame: frame, cornerRadius: cornerRadius),
                                       at: location, part: part)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { layoutSignal = $0 }
    }
}

extension View {
    func playerTransitionElement(track: PlaybackTrackResponse, revision: Int,
                                 location: PlayerTransitionLocation, part: PlayerTransitionPart,
                                 cornerRadius: CGFloat = 0) -> some View {
        modifier(PlayerTransitionElement(identity: PlayerTransitionIdentity(trackID: track.id, revision: revision),
                                         location: location, part: part, cornerRadius: cornerRadius))
    }
}

struct PlayerTransitionOverlay: View {
    let transition: PlayerTransition
    @State private var layoutSignal: CGRect = .zero
    @State private var windowFrame: CGRect = .zero

    var body: some View {
        GeometryReader { _ in
            if let flight = transition.flight {
                let origin = windowFrame.origin
                let layout = flight.layout
                ArtworkView(urlString: flight.track.artworkUrl,
                            layout: .aspectRatio(layout.artwork.width / max(layout.artwork.height, 1)),
                            cornerRadius: layout.cornerRadius)
                    .frame(width: layout.artwork.width, height: layout.artwork.height)
                    .position(x: layout.artwork.midX - origin.x, y: layout.artwork.midY - origin.y)
                ZStack(alignment: .topLeading) {
                    Text(flight.track.title).font(.title2.bold()).lineLimit(2, reservesSpace: true)
                        .opacity(flight.showsPlayerTitle ? 1 : 0)
                    Text(flight.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .opacity(flight.showsPlayerTitle ? 0 : 1)
                }
                .frame(width: layout.title.width, height: layout.title.height, alignment: .topLeading)
                .clipped()
                .position(x: layout.title.midX - origin.x, y: layout.title.midY - origin.y)
                .task(id: flight.destination) {
                    guard let destination = flight.destination else { return }
                    // Wait for accessory placement to settle; geometry updates cancel this task.
                    do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
                    transition.animate(id: flight.id, destination: destination)
                }
            }
        }
        .background {
            PlayerWindowFrameReader(layoutSignal: layoutSignal) { frame in
                windowFrame = frame
                transition.setRootFrame(frame)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { layoutSignal = $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
