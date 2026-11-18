import Foundation
import SwiftUI

enum ExportPreferences {
    private static let formatKey = "filmTone.export.format"
    private static let qualityKey = "filmTone.export.quality"
    private static let originalSizeKey = "filmTone.export.originalSize"
    private static let sizeKey = "filmTone.export.size"
    private static let saveToPhotosKey = "filmTone.export.saveToPhotos"

    static var formatChoice: String {
        get { UserDefaults.standard.string(forKey: formatKey) ?? "jpeg" }
        set { UserDefaults.standard.set(newValue, forKey: formatKey) }
    }

    static var quality: Double {
        get {
            UserDefaults.standard.object(forKey: qualityKey) == nil
                ? 0.8
                : UserDefaults.standard.double(forKey: qualityKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: qualityKey) }
    }

    /// "original", "4k" or "2048". Falls back to the older on/off original-size setting.
    static var sizeChoice: String {
        get {
            if let value = UserDefaults.standard.string(forKey: sizeKey) { return value }
            if UserDefaults.standard.object(forKey: originalSizeKey) != nil,
               !UserDefaults.standard.bool(forKey: originalSizeKey) {
                return "2048"
            }
            return "original"
        }
        set { UserDefaults.standard.set(newValue, forKey: sizeKey) }
    }

    static var saveToPhotos: Bool {
        get {
            UserDefaults.standard.object(forKey: saveToPhotosKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: saveToPhotosKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: saveToPhotosKey) }
    }

    static var format: ExportFormat {
        switch formatChoice {
        case "heic": .heic
        case "png", "tiff": .png
        default: .jpeg
        }
    }

    static var jpegQuality: JPEGQuality {
        switch quality {
        case ..<0.25: .low
        case ..<0.55: .medium
        case ..<0.85: .high
        default: .maximum
        }
    }

    static var size: ExportSize {
        switch sizeChoice {
        case "4k": .fourK
        case "2048": .pixels2048
        default: .original
        }
    }

    static var summary: String {
        var parts = [format.rawValue.uppercased()]
        if format != .png { parts.append(jpegQuality.title) }
        parts.append(L10n.text(sizeTitleKey))
        return parts.joined(separator: " · ")
    }

    private static var sizeTitleKey: String {
        switch size {
        case .fourK: "4K"
        case .pixels2048: "2048 px"
        default: "Original Size"
        }
    }

    static func restoreDefaults() {
        formatChoice = "jpeg"
        quality = 0.8
        sizeChoice = "original"
        saveToPhotos = true
    }
}


struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let project: PhotoProject
    let editState: EditState
    let repository: PhotoProjectRepository
    var preview: CGImage?
    var onReturnHome: () -> Void = {}

    @State private var stage: ExportStage?
    @State private var errorMessage: String?
    @State private var sharePayload: SharePayload?
    @State private var exportedURL: URL?
    @State private var savedToPhotos = false
    @State private var isSavingToPhotos = false
    @State private var exportTask: Task<Void, Never>?
    @State private var operation = ExportOperationState()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    previewImage
                    status
                    actionRow(
                        symbol: savedToPhotos ? "checkmark.circle" : "square.and.arrow.down",
                        title: savedToPhotos ? "Saved to Photos" : "Save to Album",
                        detail: ExportPreferences.summary,
                        action: saveToPhotos
                    )
                    .disabled(savedToPhotos || isSavingToPhotos)
                    .padding(.top, 28)
                    actionRow(
                        symbol: "square.and.arrow.up",
                        title: "Share Photo",
                        detail: "Send or post to another app",
                        action: share
                    )
                    .padding(.top, 10)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(FilmToneTheme.caption)
                            .foregroundStyle(FilmToneTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                        if exportedURL == nil && !operation.isRunning {
                            Button(L10n.text("Retry"), action: startExport)
                                .font(FilmToneTheme.button)
                                .foregroundStyle(FilmToneTheme.accent)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            Button(action: onReturnHome) {
                Text(L10n.text("Return Home"))
                    .font(FilmToneTheme.button)
                    .foregroundStyle(FilmToneTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(FilmToneTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .foregroundStyle(FilmToneTheme.primaryText)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sharePayload) { ShareSheet(payload: $0) }
        .task { startExport() }
        .onDisappear {
            exportTask?.cancel()
            if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
        }
    }

    private var header: some View {
        ZStack {
            Text(L10n.text("Export Photo"))
                .font(FilmToneTheme.pageTitle)
                .lineLimit(1)
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel(L10n.text("Back"))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var previewImage: some View {
        Group {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                FilmToneTheme.chipBackground
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var status: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(FilmToneTheme.accent)
                    .frame(width: 52, height: 52)
                if operation.isRunning {
                    ProgressView()
                        .tint(FilmToneTheme.accentText)
                } else {
                    Image(systemName: exportedURL == nil ? "exclamationmark" : "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(FilmToneTheme.accentText)
                }
            }
            Text(L10n.text(statusTitle))
                .font(.system(size: 22, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var statusTitle: String {
        if operation.isRunning { return "Exporting…" }
        if exportedURL == nil { return "Export Failed" }
        return savedToPhotos ? "Saved to Photos" : "Export Ready"
    }

    private func actionRow(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(title))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                    Text(L10n.text(detail))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FilmToneTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color(red: 0.11, green: 0.12, blue: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(exportedURL == nil || operation.isRunning)
    }

    private func saveToPhotos() {
        guard let exportedURL, !savedToPhotos, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        Task {
            defer { isSavingToPhotos = false }
            do {
                try await PhotoLibrarySaver().save(fileURL: exportedURL)
                savedToPhotos = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func share() {
        guard let exportedURL else { return }
        sharePayload = SharePayload(fileURL: exportedURL, deleteWhenReleased: false)
    }

    private func startExport() {
        guard operation.begin() else { return }
        errorMessage = nil
        let service = ExportService(repository: repository)
        let request = ExportRequest(
            project: project,
            editState: editState,
            format: ExportPreferences.format,
            jpegQuality: ExportPreferences.jpegQuality,
            size: ExportPreferences.size
        )
        let saveAfterExport = ExportPreferences.saveToPhotos
        exportTask = Task {
            do {
                let url = try await service.export(request) { value in
                    Task { @MainActor in stage = value }
                }
                exportedURL = url
                if saveAfterExport {
                    try await PhotoLibrarySaver().save(fileURL: url)
                    savedToPhotos = true
                }
            } catch is CancellationError {
                errorMessage = ExportError.cancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            exportTask = nil
            operation.finish()
        }
    }
}
