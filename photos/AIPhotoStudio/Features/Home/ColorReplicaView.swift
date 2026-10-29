import SwiftUI

struct ColorReplicaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reference: PickedPhoto?
    @State private var target: PickedPhoto?
    @State private var mode: MatchMode = .natural
    @State private var picking: PhotoSlot?
    @State private var editorImage: OriginalImage?

    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(L10n.text("Use a photo you like to define another photo's color."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    photoPane(
                        title: "Reference A",
                        photo: reference,
                        action: { picking = .reference }
                    )
                    photoPane(
                        title: "Target B",
                        photo: target,
                        action: { picking = .target }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Text(L10n.text("Match Method"))
                    .font(FilmToneTheme.sectionTitle)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                VStack(spacing: 8) {
                    ForEach(MatchMode.allCases) { item in
                        modeRow(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("You can still adjust the result by hand."))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(red: 0.94, green: 0.84, blue: 0.64))
                    Text(L10n.text("The result is editable color settings, not a redrawn photo."))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(red: 0.80, green: 0.72, blue: 0.57))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(red: 0.24, green: 0.20, blue: 0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer(minLength: 16)
                Button(action: startMatch) {
                    Text(L10n.text("Start Matching"))
                        .font(FilmToneTheme.button)
                        .foregroundStyle(FilmToneTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(FilmToneTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(target == nil)
                .opacity(target == nil ? 0.4 : 1)
                .padding(.horizontal, 16)
                Text(L10n.text("Processing stays on this device when possible."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { picking != nil },
            set: { if !$0 { picking = nil } }
        )) {
            PhotoSelectionView { photos in
                guard let photo = photos.first, let picking else { return }
                switch picking {
                case .reference: reference = photo
                case .target: target = photo
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { editorImage != nil },
            set: { if !$0 { editorImage = nil } }
        )) {
            if let editorImage {
                EditorView(original: editorImage, initialTool: .recipe)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text(L10n.text("Match Colors"))
                .font(FilmToneTheme.pageTitle)
                .foregroundStyle(FilmToneTheme.primaryText)
                .lineLimit(1)
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel(L10n.text("Back"))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func photoPane(title: String, photo: PickedPhoto?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(FilmToneTheme.primaryText)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FilmToneTheme.chipBackground)
                .frame(height: 118)
                .overlay {
                    Image(systemName: photo == nil ? "photo" : "photo.fill")
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
            Button(action: action) {
                Text(L10n.text("Change Photo"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(FilmToneTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(FilmToneTheme.chipBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmToneTheme.featureCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func modeRow(_ item: MatchMode) -> some View {
        let selected = mode == item
        return Button {
            mode = item
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? FilmToneTheme.accent : FilmToneTheme.secondaryText, lineWidth: 1.5)
                    .background(Circle().fill(selected ? FilmToneTheme.accent : Color.clear))
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(item.titleKey))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                    Text(L10n.text(item.detailKey))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(Color(red: 0.09, green: 0.09, blue: 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func startMatch() {
        guard let target else { return }
        editorImage = ImageSourceFactory.decode(data: target.data, maximumDimension: 2048)
            ?? ImageSourceFactory.makeTestImage()
    }
}

private enum PhotoSlot: Hashable {
    case reference
    case target
}

private enum MatchMode: String, CaseIterable, Identifiable {
    case natural
    case film
    case precise

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .natural: "Natural Match"
        case .film: "Film Match"
        case .precise: "Precise Color"
        }
    }

    var detailKey: String {
        switch self {
        case .natural: "Keep the target photo's light and subject color."
        case .film: "Bring across more of the reference photo's character."
        case .precise: "Match tone and contrast more strongly."
        }
    }
}
