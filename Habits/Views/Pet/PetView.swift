import SwiftUI

/// Карточка питомца для профиля и главного экрана.
struct PetCard: View {
    @Environment(HabitStore.self) private var store
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let pet = store.data.wallet.pet {
                    let xp = Pets.xp(pet, data: store.data)
                    let stage = PetStage.stage(xp: xp)
                    let mood = Pets.mood(pet, data: store.data)
                    PetAvatar(pet: pet, stage: stage, mood: mood, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pet.name).font(.headline)
                        Text("\(stage.title) · \(mood.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let next = stage.next {
                            ProgressView(value: Double(xp - stage.threshold), total: Double(next.threshold - stage.threshold))
                                .tint(.orange)
                        }
                    }
                } else {
                    Text(verbatim: "🥚")
                        .font(.system(size: 44))
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get a pet").font(.headline)
                        Text("It grows with every habit you check off.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.primary)
            .card(padding: 14, cornerRadius: 22)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Экран питомца: рост, настроение, кормление и выбор вида.
struct PetView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpecies = "cat"
    @State private var name = ""
    @State private var renaming = false
    @State private var renameText = ""
    @State private var phrase: Int?
    @State private var hearts = 0
    @State private var showingPaywall = false
    @State private var notEnough = false

    private let grid = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let pet = store.data.wallet.pet {
                        petSection(pet)
                    } else {
                        adoptSection
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle(store.data.wallet.pet?.name ?? String(localized: "Pet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    SparkBadge(amount: store.economy.balance)
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("Rename", isPresented: $renaming) {
                TextField("Name", text: $renameText)
                Button("Save") { store.renamePet(renameText) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Not enough sparks", isPresented: $notEnough) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check off habits to earn more.")
            }
        }
    }

    // MARK: Есть питомец

    @ViewBuilder
    private func petSection(_ pet: PetState) -> some View {
        let xp = Pets.xp(pet, data: store.data)
        let stage = PetStage.stage(xp: xp)
        let mood = Pets.mood(pet, data: store.data)

        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                PetAvatar(pet: pet, stage: stage, mood: mood, size: 200)
                    .id("\(pet.species)-\(stage.rawValue)")
                    .onTapGesture { pat() }
                    .sensoryFeedback(.impact(weight: .light), trigger: hearts)
                HeartsBurst(trigger: hearts)
                if let phrase {
                    Text(Pets.phrases[phrase])
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.background).shadow(color: .black.opacity(0.12), radius: 4, y: 2))
                        .offset(y: -18)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Button {
                renameText = pet.name
                renaming = true
            } label: {
                HStack(spacing: 6) {
                    Text(pet.name).font(.title2.weight(.bold))
                    Image(systemName: "pencil").font(.footnote).foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
            }
            Text("\(stage.title) · \(mood.title)")
                .foregroundStyle(.secondary)
            if let next = stage.next {
                VStack(spacing: 4) {
                    ProgressView(value: Double(xp - stage.threshold), total: Double(next.threshold - stage.threshold))
                        .tint(.orange)
                        .frame(maxWidth: 240)
                    Text("\(next.threshold - xp) more to \(next.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Your pet grows with every habit you check off and gets sad when you disappear for a few days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }

        Button {
            if store.feedsToday >= Sparks.feedsPerDay { return }
            withAnimation(.snappy) {
                if store.feedPet() { hearts += 1 } else { notEnough = true }
            }
        } label: {
            HStack {
                Text(verbatim: "🍓")
                Text(store.feedsToday >= Sparks.feedsPerDay ? String(localized: "Full for today") : String(localized: "Feed"))
                Spacer()
                if store.feedsToday < Sparks.feedsPerDay {
                    SparkBadge(amount: Sparks.feedPrice)
                }
            }
            .font(.headline)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glassProminent)
        .disabled(store.feedsToday >= Sparks.feedsPerDay)

        speciesGrid(current: pet.species)
    }

    private func pat() {
        hearts += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            phrase = Pets.phrases.indices.randomElement()
        }
        let shown = phrase
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if phrase == shown {
                withAnimation { phrase = nil }
            }
        }
    }

    private func speciesGrid(current: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Species").font(.title3.weight(.bold))
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(Pets.all) { species in
                    speciesTile(species, selected: species.id == current) {
                        guard species.id != current else { return }
                        if species.needsPro && !store.data.isPro {
                            showingPaywall = true
                        } else if !store.setPetSpecies(species) {
                            notEnough = true
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speciesTile(_ species: PetSpecies, selected: Bool, action: @escaping () -> Void) -> some View {
        let owned = Pets.isOwned(species, data: store.data)
        return Button(action: action) {
            VStack(spacing: 4) {
                Text(species.baby).font(.system(size: 38))
                Text(species.title).font(.caption.weight(.medium)).lineLimit(1)
                if !owned {
                    if species.needsPro {
                        ProBadge().scaleEffect(0.8)
                    } else if let price = species.price {
                        SparkBadge(amount: price, font: .caption2.weight(.bold))
                    }
                }
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.opacity(0.7)))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .opacity(owned ? 1 : 0.75)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Нет питомца

    private var adoptSection: some View {
        VStack(spacing: 18) {
            Text(verbatim: "🥚")
                .font(.system(size: 110))
                .padding(.top, 10)
            Text("Adopt a pet")
                .font(.title.weight(.bold))
            Text("It hatches from an egg and grows with every habit you check off. Feed it with sparks and don't leave it alone for long.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(Pets.all.filter { Pets.isOwned($0, data: store.data) }) { species in
                    speciesTile(species, selected: species.id == selectedSpecies) {
                        selectedSpecies = species.id
                    }
                }
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            Button {
                withAnimation(.snappy) { store.adoptPet(species: selectedSpecies, name: name) }
            } label: {
                Text("Adopt")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            Text("More species are available for sparks and with Pro.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Сердечки, которые взлетают при поглаживании и кормлении.
struct HeartsBurst: View {
    let trigger: Int
    @State private var items: [UUID] = []

    var body: some View {
        ZStack {
            ForEach(items, id: \.self) { id in
                FloatingHeart(seed: id.hashValue)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            let id = UUID()
            items.append(id)
            Task {
                try? await Task.sleep(for: .seconds(1.3))
                items.removeAll { $0 == id }
            }
        }
    }
}

private struct FloatingHeart: View {
    let seed: Int
    @State private var up = false

    var body: some View {
        let dx = CGFloat(seed % 80) - 40
        Text(verbatim: "❤️")
            .font(.title2)
            .offset(x: up ? dx : 0, y: up ? -50 : 60)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.3 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) { up = true }
            }
    }
}
