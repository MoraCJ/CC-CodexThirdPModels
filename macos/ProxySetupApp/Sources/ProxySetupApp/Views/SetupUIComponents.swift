import SwiftUI

struct SetupPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct ReadinessRow: View {
    let item: ReadinessItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isReady ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
