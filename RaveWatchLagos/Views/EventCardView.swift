import SwiftUI

// MARK: - Colours (Flutter's fixed pairs — they read in both themes)

extension Color {
    /// The "new" accent bar's violet — brand purple, readable on both
    /// the night and light themes.
    static let newViolet = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
    /// Deep purple (the follow action colour, `Colors.deepPurple`).
    static let deepPurple = Color(red: 0x67 / 255, green: 0x3A / 255, blue: 0xB7 / 255)
    /// Green (the attend action colour, `Colors.green`).
    static let attendGreen = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    /// Free-entry green: greenAccent shade400 on dark, green shade700 on light.
    static func freeGreen(dark: Bool) -> Color {
        dark ? Color(red: 0x00 / 255, green: 0xE6 / 255, blue: 0x76 / 255)
             : Color(red: 0x38 / 255, green: 0x8E / 255, blue: 0x3C / 255)
    }
}

// MARK: - Event card

/// Feed card, ported from `lib/widgets/event_card.dart`. Entry price is
/// first-class: always on the card. There is deliberately NO flyer image
/// on cards, and NO price filtering anywhere in the app.
///
/// - Name + entry price (bold; green if free) on one row.
/// - Date BOLD + venue + area + day flag.
/// - Ticket row (ticketNote, or "Tickets available online — open event
///   for the link") when a link or note exists.
/// - Chips: type (fixed pairs), ticket status, genres, Deal (amber,
///   black bold text) when the entry is ≤ ₦5,000 or free, "New promoter"
///   when the promoter is unproven with no repeat-edition marker.
/// - Footer: following row (bell) on top, attending row (people) below
///   with the share button; each count line only at 1+; the footer
///   shows only when the share button or any count > 0.
/// - A violet 6pt bar down the left edge when the event is new — a
///   property of the tile itself, overlaying the edge without changing
///   the content layout, so nothing shifts when the marker clears.
///
/// The counts come from the caller: the live Supabase totals overlaid
/// on the feed-published counts (see EventStore).
struct EventCardView: View {
    let event: Event
    let attendingCount: Int?
    let followingCount: Int?
    let isNew: Bool
    let onShare: (() -> Void)?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 0) {
                    // Name + entry price.
                    HStack(alignment: .top) {
                        Text(event.name)
                            .font(.headline)
                            .fontWeight(.regular)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Text(event.entryPriceDisplay)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(event.isFree
                                ? Color.freeGreen(dark: colorScheme == .dark)
                                : Color.primary)
                    }

                    // Date (BOLD) · venue · area · day flag.
                    Text(dateLine)
                        .font(.subheadline)
                        .padding(.top, 4)

                    // Ticket row.
                    if event.ticketLink != nil || event.ticketNote != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "ticket")
                                .font(.caption)
                            Text(event.ticketNote ?? "Tickets available online — open event for the link")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                    }

                    // Chips.
                    chips
                        .padding(.top, 6)

                    // Footer rows.
                    if onShare != nil || (followingCount ?? 0) > 0 || (attendingCount ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            if let followingCount, followingCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "bell")
                                        .font(.caption)
                                    Text(followingCount == 1 ? "1 user following" : "\(followingCount) users following")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            if onShare != nil || (attendingCount ?? 0) > 0 {
                                HStack(spacing: 4) {
                                    if let attendingCount, attendingCount > 0 {
                                        Image(systemName: "person.2")
                                            .font(.caption)
                                        Text(attendingCount == 1 ? "1 user attending" : "\(attendingCount) users attending")
                                            .font(.caption)
                                    } else {
                                        Spacer()
                                    }
                                    Spacer()
                                    if let onShare {
                                        Button(action: onShare) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.body)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Share event")
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

                if isNew {
                    Color.newViolet
                        .frame(width: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var dateLine: AttributedString {
        var result = AttributedString(event.dateLabel)
        result.font = .subheadline.bold()
        var rest = AttributedString(" · \(event.venueName ?? "Venue TBA") · \(event.area ?? "")")
        rest.font = .subheadline
        result += rest
        if let flag = event.dayFlag() {
            var flagPart = AttributedString(" · \(flag)")
            flagPart.font = .subheadline
            result += flagPart
        }
        return result
    }

    private var chips: some View {
        // A wrapping chip row (SwiftUI has no Wrap — use a flexible flow).
        ChipFlow(spacing: 6) {
            if event.spansBothScenes {
                chip("Rave + Club Party", background: Color(red: 0x7B / 255, green: 0x1F / 255, blue: 0xA2 / 255), foreground: .white, bold: true)
            } else if event.eventType == .club {
                chip("Club Party", background: Color(red: 0x30 / 255, green: 0x3F / 255, blue: 0x9F / 255), foreground: .white, bold: true)
            } else {
                chip("Rave", background: Color(red: 0x51 / 255, green: 0x2D / 255, blue: 0xA8 / 255), foreground: .white, bold: true)
            }
            chip(event.ticketStatus.label)
            ForEach(event.genres, id: \.self) { genre in
                chip(genre)
            }
            if event.isDeal {
                chip("Deal", background: Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255), foreground: .black, bold: true)
            }
            if event.showNewPromoterTag {
                chip("New promoter")
            }
        }
    }

    private func chip(_ text: String, background: Color? = nil, foreground: Color? = nil, bold: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(bold ? .semibold : .regular)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background ?? Color.primary.opacity(0.08))
            .foregroundStyle(foreground ?? Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

/// A wrapping row of chips (Flutter's `Wrap`), implemented with the
/// iOS 16 `Layout` protocol: children flow left-to-right, wrapping to
/// the next line when the row is full.
struct ChipFlow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to the
/// next line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + spacing + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + spacing + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Feed card swipe

/// Feed card swipe, ported from the feed's `Dismissible` (threshold
/// 0.3 both ways): swipe right = Follow (deepPurple, bell), swipe left
/// = Attend (green, calendar check). The card springs back — it is
/// never dismissed. Sounds: tick on right, click on left.
struct FeedCardSwipe<Content: View>: View {
    let onFollow: () -> Void
    let onAttend: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var cardWidth: CGFloat = 360

    var body: some View {
        GeometryReader { geometry in
            ZStack {
            // Action panels behind the card.
            HStack(spacing: 0) {
                ZStack {
                    Color.deepPurple
                    if offset > 0 {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.white)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                Spacer()
                ZStack {
                    Color.attendGreen
                    if offset < 0 {
                        Image(systemName: "calendar.badge.checkmark")
                            .foregroundStyle(.white)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            offset = value.translation.width
                        }
                        .onEnded { value in
                            finishDrag(translation: value.translation.width)
                        }
                )
            }
            .onAppear { cardWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, newWidth in
                cardWidth = newWidth
            }
        }
    }

    private func finishDrag(translation: CGFloat) {
        // Dismissible threshold: 0.3 of the card width, both ways.
        let threshold = 0.3 * cardWidth
        if translation > threshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            onFollow()
        } else if translation < -threshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            onAttend()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
        }
    }
}

// MARK: - List card swipe (Following / Attending tabs)

/// Card swipe on the Following/Attending tabs, ported from
/// `lib/widgets/list_card_swipe.dart`: right = Share (blue panel, the
/// card stays), left = Delete (red panel, the card leaves, snackbar
/// with Undo, 3s). Tick on share, click on delete.
struct ListCardSwipe<Content: View>: View {
    let onShare: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var leaving = false
    @State private var cardWidth: CGFloat = 360

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                ZStack {
                    Color.blue
                    if offset > 0 {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                Spacer()
                ZStack {
                    Color.red
                    if offset < 0 {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            content()
                .offset(x: offset)
                .opacity(leaving ? 0 : 1)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            offset = value.translation.width
                        }
                        .onEnded { value in
                            finishDrag(translation: value.translation.width)
                        }
                )
            }
            .onAppear { cardWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, newWidth in
                cardWidth = newWidth
            }
        }
    }

    private func finishDrag(translation: CGFloat) {
        // Same 0.3-of-width threshold as the feed swipes.
        let threshold = 0.3 * cardWidth
        if translation > threshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            onShare()
        } else if translation < -threshold {
            withAnimation(.easeOut(duration: 0.25)) {
                offset = -UIScreen.main.bounds.width
                leaving = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onDelete()
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = 0 }
        }
    }
}
