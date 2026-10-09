import SwiftUI
import AppKit

// MARK: - App Icon Helper

@MainActor
public enum AppIconHelper {
    public static func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let img = NSImage(named: "AppIcon") {
            return img
        }
        if let appIcon = NSApplication.shared.applicationIconImage {
            return appIcon
        }
        return nil
    }
}

// MARK: - About View

public struct AboutView: View {
    @State private var isHoveringLink = false
    @State private var didCopyRepo = false

    private let repoURL = "https://github.com/ParitoshChaudhari/NetGaugeMac"
    private let appVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.6"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1.0.6"
        return "Version \(v) (\(b))"
    }()

    public init() {}

    public var body: some View {
        ZStack {
            // Notes Paper Canvas Base
            NotesTheme.bgBase
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header spacer for macOS window traffic lights
                Spacer()
                    .frame(height: 28)

                // App Icon with Amber Accent Border
                ZStack {
                    if let nsImg = AppIconHelper.loadAppIcon() {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(NotesTheme.accent)
                    }
                }
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(NotesTheme.borderAccent, lineWidth: 1.5)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)

                Spacer()
                    .frame(height: 14)

                // App Name
                Text("NetGauge")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NotesTheme.textPrimary)

                Spacer()
                    .frame(height: 4)

                // Version Badge
                Text(appVersion)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotesTheme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(NotesTheme.bgCardHover)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(NotesTheme.border, lineWidth: 0.8)
                    }

                Spacer()
                    .frame(height: 16)

                // Author Name
                Text("Paritosh Chaudhari")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)

                Spacer()
                    .frame(height: 6)

                // App Description
                Text("A native real-time network usage monitor with tiered SQLite retention strategy.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(NotesTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)

                Spacer()
                    .frame(height: 20)

                // Clickable Repository Link Button
                Link(destination: URL(string: repoURL)!) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isHoveringLink ? NotesTheme.accentHover : NotesTheme.accent)

                        Text("ParitoshChaudhari/NetGaugeMac")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isHoveringLink ? NotesTheme.textPrimary : NotesTheme.textPrimary.opacity(0.9))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(isHoveringLink ? NotesTheme.accentHover : NotesTheme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isHoveringLink ? NotesTheme.accentBg.opacity(1.8) : NotesTheme.accentBg)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(isHoveringLink ? NotesTheme.accent : NotesTheme.accentBorder, lineWidth: 1)
                    }
                    .shadow(color: isHoveringLink ? NotesTheme.accent.opacity(0.2) : Color.clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringLink = hovering
                    }
                }
                .help("Open NetGauge GitHub Repository in browser")
                .contextMenu {
                    Button("Copy Repository URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(repoURL, forType: .string)
                        didCopyRepo = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            didCopyRepo = false
                        }
                    }
                }

                if didCopyRepo {
                    Text("Copied URL to clipboard!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotesTheme.green)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                Spacer()

                // Divider Line
                Rectangle()
                    .fill(NotesTheme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 28)

                Spacer()
                    .frame(height: 12)

                // Legal / Copyright Notice
                Text("Copyright © 2026 Paritosh Chaudhari. All rights reserved.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NotesTheme.textMuted)

                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(width: 340, height: 410)
    }
}
