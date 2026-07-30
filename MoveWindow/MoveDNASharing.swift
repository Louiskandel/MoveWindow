import SwiftUI
import UIKit

struct MoveDNAShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

@MainActor
struct MoveDNAShareService {
    func makeShareItem(for profile: MoveDNAProfile) throws -> MoveDNAShareItem {
        let renderer = ImageRenderer(content: MoveDNACardView(profile: profile))
        renderer.scale = 3

        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            throw MoveDNAShareError.renderingFailed
        }

        let safeActivityName = profile.activity.rawValue.lowercased()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("movedna-\(safeActivityName).png")
        try data.write(to: fileURL, options: .atomic)
        return MoveDNAShareItem(fileURL: fileURL)
    }
}

enum MoveDNAShareError: Error {
    case renderingFailed
}

struct MoveDNACardView: View {
    let profile: MoveDNAProfile

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo, Color.blue, Color.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 260, height: 260)
                .offset(x: 145, y: -180)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: 190)

            VStack(spacing: 20) {
                Text("MY MOVEDNA")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.85))

                Image(systemName: profile.activity.symbolName)
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 112)
                    .background(.white.opacity(0.16), in: Circle())

                VStack(spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("My sweet spot is \(profile.temperatureRangeLabel)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }

                HStack(spacing: 8) {
                    ForEach(Array(profile.badges.prefix(2)), id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                }

                Spacer()

                Text("Learned from \(profile.checkInCount) real outings")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                Text("MoveWindow")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(34)
        }
        .frame(width: 360, height: 450)
        .clipped()
    }
}

struct MoveDNAShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [
                "This is my MoveDNA — weather that actually fits how I move.",
                fileURL
            ],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
