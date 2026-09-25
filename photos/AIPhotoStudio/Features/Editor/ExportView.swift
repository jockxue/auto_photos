import SwiftUI

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let project: PhotoProject
    let repository: PhotoProjectRepository

    @State private var format = ExportFormat.jpeg
    @State private var quality = JPEGQuality.high
    @State private var size = ExportSize.original
    @State private var customWidth = 2048
    @State private var customHeight = 2048
    @State private var stage: ExportStage?
    @State private var errorMessage: String?
    @State private var sharePayload: SharePayload?
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                if format == .jpeg {
                    Picker("JPEG Quality", selection: $quality) {
                        ForEach(JPEGQuality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Picker("Size", selection: sizeBinding) {
                    Text("Original").tag("original")
                    Text("4K long edge").tag("4k")
                    Text("2048 long edge").tag("2048")
                    Text("Custom bounding box").tag("custom")
                }
                if case .custom = size {
                    Stepper("Max width \(customWidth)", value: $customWidth, in: 64...20_000)
                    Stepper("Max height \(customHeight)", value: $customHeight, in: 64...20_000)
                    Text("Custom dimensions preserve the cropped aspect ratio and never upscale.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let stage {
                    ProgressView(value: stage.rawValue) {
                        Text(stage == .completed ? "Saved to temporary file" : "Exporting…")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Button("Export") { startExport() }
                    .disabled(exportTask != nil)
                if exportTask != nil {
                    Button("Cancel", role: .destructive) {
                        exportTask?.cancel()
                        exportTask = nil
                    }
                }
            }
            .navigationTitle("Export")
            .toolbar { Button("Close") { dismiss() } }
            .sheet(item: $sharePayload) { ShareSheet(payload: $0) }
        }
    }

    private var sizeBinding: Binding<String> {
        Binding(
            get: {
                switch size {
                case .original: "original"
                case .fourK: "4k"
                case .pixels2048: "2048"
                case .custom: "custom"
                }
            },
            set: {
                switch $0 {
                case "4k": size = .fourK
                case "2048": size = .pixels2048
                case "custom": size = .custom(width: customWidth, height: customHeight)
                default: size = .original
                }
            }
        )
    }

    private func startExport() {
        if case .custom = size {
            size = .custom(width: customWidth, height: customHeight)
        }
        errorMessage = nil
        let service = ExportService(repository: repository)
        let request = ExportRequest(project: project, format: format, jpegQuality: quality, size: size)
        exportTask = Task {
            do {
                let url = try await service.export(request) { value in
                    Task { @MainActor in stage = value }
                }
                sharePayload = SharePayload(fileURL: url)
            } catch is CancellationError {
                errorMessage = ExportError.cancelled.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            exportTask = nil
        }
    }
}
