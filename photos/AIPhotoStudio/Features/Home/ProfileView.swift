import SwiftUI

struct ProfileView: View {
    let projects: [PhotoProject]

    @State private var recipes: [Recipe] = []

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
                    stat(0, title: "Favorite Presets")
                    stat(recipes.count, title: "Custom Recipes")
                }

                section("My Creations") {
                    NavigationLink {
                        ProfileListView(
                            title: "Favorite Presets",
                            empty: "No favorite presets yet."
                        )
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

private struct ProfileListView: View {
    let title: String
    let empty: String

    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            Text(L10n.text(empty))
                .font(FilmToneTheme.body)
                .foregroundStyle(FilmToneTheme.secondaryText)
                .padding(24)
        }
        .navigationTitle(L10n.text(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecipeListView: View {
    let recipes: [Recipe]

    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            if recipes.isEmpty {
                Text(L10n.text("No saved recipes yet."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
            } else {
                List(recipes) { recipe in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title)
                            .foregroundStyle(FilmToneTheme.primaryText)
                        Text(recipe.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(FilmToneTheme.caption)
                            .foregroundStyle(FilmToneTheme.secondaryText)
                    }
                    .listRowBackground(FilmToneTheme.cardBackground)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(L10n.text("My Recipes"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExportDefaultsView: View {
    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("JPEG · High Quality"))
                    .font(FilmToneTheme.sectionTitle)
                    .foregroundStyle(FilmToneTheme.primaryText)
                Text(L10n.text("Exports keep the original size. Format and quality can be changed in a later update."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                Spacer()
            }
            .padding(16)
        }
        .navigationTitle(L10n.text("Export Settings"))
        .navigationBarTitleDisplayMode(.inline)
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
