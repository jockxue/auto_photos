import SwiftUI

struct ProfileView: View {
    let projects: [PhotoProject]

    @State private var recipes: [Recipe] = []
    @State private var favoriteCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(L10n.text("Profile"))
                    .font(FilmToneTheme.largeTitle)
                    .foregroundStyle(FilmToneTheme.primaryText)

                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                        .frame(width: 58, height: 58)
                        .background(FilmToneTheme.chipBackground, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("FilmTone User"))
                            .font(FilmToneTheme.pageTitle)
                            .foregroundStyle(FilmToneTheme.primaryText)
                        Text(L10n.text("Keep every color idea."))
                            .font(FilmToneTheme.body)
                            .foregroundStyle(FilmToneTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    stat(projects.count, title: "Edited Works")
                    stat(favoriteCount, title: "Favorite Presets")
                    stat(recipes.count, title: "Custom Recipes")
                }

                section("My Creations") {
                    NavigationLink {
                        FavoritePresetsView()
                    } label: {
                        row("camera.filters", title: "Favorite Presets", detail: "Find a color style you like.")
                    }
                    NavigationLink {
                        RecipeListView(recipes: recipes)
                    } label: {
                        row("swatchpalette", title: "My Recipes", detail: "Manage saved custom settings.")
                    }
                }

                section("App Settings") {
                    NavigationLink {
                        ExportDefaultsView()
                    } label: {
                        row("square.and.arrow.up", title: "Export Settings", detail: "Default format, quality, and size.")
                    }
                    NavigationLink {
                        AboutFilmToneView()
                    } label: {
                        row("info.circle", title: "About FilmTone", detail: "Version, help, and feedback.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .buttonStyle(.plain)
        .task { await reloadRecipes() }
        .onAppear { favoriteCount = FavoritePresets.ids().count }
    }

    private func stat(_ value: Int, title: String) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FilmToneTheme.primaryText)
            Text(L10n.text(title))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(FilmToneTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(FilmToneTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(title))
                .font(FilmToneTheme.sectionTitle)
                .foregroundStyle(FilmToneTheme.primaryText)
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
        }
    }

    private func row(_ symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
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
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FilmToneTheme.secondaryText)
        }
    }

    private func reloadRecipes() async {
        recipes = (try? await RecipeStore().fetchAll()) ?? []
    }
}

private enum FavoritePresets {
    private static let key = "filmTone.favoritePresets"

    static func ids() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func contains(_ id: String) -> Bool {
        ids().contains(id)
    }

    static func toggle(_ id: String) {
        var values = ids()
        if values.contains(id) {
            values.remove(id)
        } else {
            values.insert(id)
        }
        UserDefaults.standard.set(Array(values), forKey: key)
    }
}

private struct ExportDefaultsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("filmTone.export.format") private var format = "jpeg"
    @AppStorage("filmTone.export.quality") private var quality = 0.8
    @AppStorage("filmTone.export.originalSize") private var useOriginalSize = true
    @AppStorage("filmTone.export.saveToPhotos") private var saveToPhotos = true
    @AppStorage("filmTone.export.keepExif") private var keepExif = true
    @AppStorage("filmTone.export.keepLocation") private var keepLocation = false

    var body: some View {
        VStack(spacing: 0) {
            pageHeader("Export Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.text("Set your preferred export options for the next export."))
                        .font(.system(size: 12))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                    sectionTitle("File Format")
                    optionBox {
                        formatRow("JPEG", detail: "Small files, good for sharing.", value: "jpeg")
                        formatRow("PNG", detail: "Lossless, files are usually larger.", value: "png")
                        formatRow("TIFF", detail: "Best for a high-quality workflow.", value: "tiff")
                    }
                    sectionTitle("Quality")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("JPEG Compression Quality"))
                            .font(.system(size: 15))
                            .foregroundStyle(FilmToneTheme.primaryText)
                        Slider(value: $quality, in: 0...1)
                            .tint(FilmToneTheme.accent)
                        HStack {
                            Text(L10n.text("Smaller File"))
                            Spacer()
                            Text(L10n.text("Highest Quality"))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.39, green: 0.39, blue: 0.40))
                    }
                    .padding(16)
                    .background(FilmToneTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    sectionTitle("Export Size")
                    optionBox {
                        sizeRow("Original Size", detail: "Keep the original pixel size.", original: true)
                        sizeRow("Shrink Size", detail: "Output a specified long edge.", original: false)
                    }
                    sectionTitle("Other Options")
                    optionBox {
                        toggleRow("Save to Album", detail: "Save to the photo library after export.", isOn: $saveToPhotos)
                        toggleRow("Keep EXIF", detail: "Keep camera and capture details when possible.", isOn: $keepExif)
                        toggleRow("Keep Location", detail: "Include the original GPS location.", isOn: $keepLocation)
                    }
                    Button(action: ExportPreferences.restoreDefaults) {
                        Text(L10n.text("Restore Defaults"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FilmToneTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    Button(action: { dismiss() }) {
                        Text(L10n.text("Done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FilmToneTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(FilmToneTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(L10n.text(key))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(FilmToneTheme.primaryText)
    }

    private func optionBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmToneTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatRow(_ title: String, detail: String, value: String) -> some View {
        Button {
            format = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                radio(format == value)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                    Text(L10n.text(detail))
                        .font(.system(size: 12))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func sizeRow(_ title: String, detail: String, original: Bool) -> some View {
        Button {
            useOriginalSize = original
        } label: {
            HStack(alignment: .top, spacing: 12) {
                radio(useOriginalSize == original)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(title))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                    Text(L10n.text(detail))
                        .font(.system(size: 12))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FilmToneTheme.primaryText)
                Text(L10n.text(detail))
                    .font(.system(size: 12))
                    .foregroundStyle(FilmToneTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                Capsule()
                    .fill(isOn.wrappedValue ? FilmToneTheme.accent : FilmToneTheme.sliderTrack)
                    .frame(width: 48, height: 28)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .padding(2)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func radio(_ selected: Bool) -> some View {
        Circle()
            .strokeBorder(selected ? FilmToneTheme.accent : FilmToneTheme.secondaryText, lineWidth: 1.5)
            .background(Circle().fill(selected ? FilmToneTheme.accent : Color.clear))
            .frame(width: 20, height: 20)
    }
}

private struct FavoritePresetsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = "all"
    @State private var favorites = FavoritePresets.ids()

    private let categories = ["all", "film", "retro", "fresh"]

    var body: some View {
        VStack(spacing: 0) {
            pageHeader("Favorite Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { item in
                        let selected = category == item
                        Button {
                            category = item
                        } label: {
                            Text(L10n.text(categoryTitle(item)))
                                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? FilmToneTheme.accentText : FilmToneTheme.primaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(selected ? FilmToneTheme.accent : FilmToneTheme.chipBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                    ForEach(visibleFilters) { filter in
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(FilmToneTheme.cardBackground)
                                    .frame(height: 168)
                                Button {
                                    FavoritePresets.toggle(filter.id)
                                    favorites = FavoritePresets.ids()
                                } label: {
                                    Image(systemName: favorites.contains(filter.id) ? "heart.fill" : "heart")
                                        .font(.system(size: 16))
                                        .foregroundStyle(favorites.contains(filter.id) ? FilmToneTheme.accent : FilmToneTheme.primaryText)
                                        .padding(10)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(L10n.text(filter.title))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FilmToneTheme.primaryText)
                                .lineLimit(1)
                            Text(filter.id)
                                .font(.system(size: 12))
                                .foregroundStyle(FilmToneTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var visibleFilters: [FilterDefinition] {
        FilterDefinition.all.filter { filter in
            guard filter.id != "original" else { return false }
            switch category {
            case "film": return ["film", "vintage", "fade", "instant", "chrome"].contains(filter.id)
            case "retro": return ["vintage", "instant", "fade", "noir"].contains(filter.id)
            case "fresh": return ["natural", "cool", "vivid"].contains(filter.id)
            default: return true
            }
        }
    }

    private func categoryTitle(_ value: String) -> String {
        switch value {
        case "film": "Film"
        case "retro": "Retro"
        case "fresh": "Fresh"
        default: "All"
        }
    }
}

private struct RecipeListView: View {
    let recipes: [Recipe]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("My Recipes")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("My Color Recipes"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                    Text(L10n.text("Save an idea and reuse the color anytime."))
                        .font(.system(size: 13))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                    HStack {
                        Text(L10n.format("%lld recipes", Int64(recipes.count)))
                            .foregroundStyle(FilmToneTheme.secondaryText)
                        Spacer()
                        Text(L10n.text("Recently Modified"))
                            .foregroundStyle(FilmToneTheme.primaryText)
                    }
                    .font(.system(size: 13))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                if recipes.isEmpty {
                    Text(L10n.text("No saved recipes yet."))
                        .font(FilmToneTheme.body)
                        .foregroundStyle(FilmToneTheme.secondaryText)
                        .padding(16)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                        ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                            recipeCard(recipe, highlighted: index == 0)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(FilmToneTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func recipeCard(_ recipe: Recipe, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FilmToneTheme.cardBackground)
                .frame(height: 108)
            Text(recipe.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilmToneTheme.primaryText)
                .lineLimit(1)
            Text(recipe.createdAt.formatted(date: .numeric, time: .omitted))
                .font(.system(size: 12))
                .foregroundStyle(FilmToneTheme.secondaryText)
            if let filter = recipe.filter {
                Text(L10n.text(FilterDefinition.definition(id: filter.identifier)?.title ?? filter.identifier))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.84, green: 0.84, blue: 0.86))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(FilmToneTheme.chipBackground, in: Capsule())
            }
            Text(L10n.text("Apply Recipe"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlighted ? FilmToneTheme.accentText : FilmToneTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    highlighted ? FilmToneTheme.accent : FilmToneTheme.chipBackground,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }
}

private func pageHeader(_ title: String) -> some View {
    PageHeader(title: title)
}

private struct PageHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(L10n.text(title))
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
}

private struct AboutFilmToneView: View {
    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("FilmTone")
                    .font(FilmToneTheme.largeTitle)
                    .foregroundStyle(FilmToneTheme.primaryText)
                Text(L10n.text("FilmTone brings film color back to every photo. Apply a preset, match a reference, or adjust the light and color yourself."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                Text(L10n.text("Processing stays on this device when possible."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                HStack {
                    Text(L10n.text("Current Version"))
                        .foregroundStyle(FilmToneTheme.secondaryText)
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(FilmToneTheme.primaryText)
                }
                .font(.system(size: 14, weight: .regular))
                Spacer()
            }
            .padding(16)
        }
        .navigationTitle(L10n.text("About FilmTone"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
