import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Sistema"
    case light = "Chiaro"
    case dark = "Scuro"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("kindleEmail") private var kindleEmail: String = ""
    
    var body: some View {
        TabView {
            // TAB GENERALE
            Form {
                Section {
                    Picker("Tema Applicazione:", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .padding()
            .tabItem {
                Label("Generale", systemImage: "gearshape")
            }
            
            // TAB KINDLE
            Form {
                Section {
                    TextField("Email Kindle:", text: $kindleEmail)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    Text("L'email del tuo Kindle (es: tuo_nome@kindle.com). Quando invii un libro via Cloud, questo indirizzo verrà automaticamente copiato negli appunti per incollarlo comodamente nella mail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .tabItem {
                Label("Kindle", systemImage: "ipad")
            }
            
            // TAB ISTRUZIONI
            InstructionsView()
            .tabItem {
                Label("Guida", systemImage: "questionmark.circle")
            }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Vista Istruzioni
struct InstructionsView: View {
    @State private var selectedSection: InstructionSection = .libreria
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar sinistra
            VStack(alignment: .leading, spacing: 4) {
                Text("Argomenti")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                
                ForEach(InstructionSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                                .frame(width: 20)
                                .foregroundStyle(selectedSection == section ? .white : section.color)
                            Text(section.title)
                                .font(.system(size: 13))
                                .foregroundStyle(selectedSection == section ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedSection == section ? section.color : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
                
                Spacer()
            }
            .frame(width: 160)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Contenuto a destra
            ScrollView {
                selectedSection.content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

enum InstructionSection: String, CaseIterable, Identifiable {
    case libreria, importazione, lettura, copertine, kindle, esportazione, scorciatoie
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .libreria:     return "La Libreria"
        case .importazione: return "Importare Libri"
        case .lettura:      return "Stato & Rating"
        case .copertine:    return "Copertine"
        case .kindle:       return "Kindle"
        case .esportazione: return "Esportare"
        case .scorciatoie:  return "Scorciatoie"
        }
    }
    
    var icon: String {
        switch self {
        case .libreria:     return "books.vertical"
        case .importazione: return "square.and.arrow.down"
        case .lettura:      return "star.leadinghalf.filled"
        case .copertine:    return "photo"
        case .kindle:       return "ipad"
        case .esportazione: return "square.and.arrow.up"
        case .scorciatoie:  return "command"
        }
    }
    
    var color: Color {
        switch self {
        case .libreria:     return .blue
        case .importazione: return .green
        case .lettura:      return .yellow
        case .copertine:    return .purple
        case .kindle:       return .orange
        case .esportazione: return .teal
        case .scorciatoie:  return .gray
        }
    }
    
    @ViewBuilder
    var content: some View {
        switch self {
        case .libreria:     LibreriaInstructions()
        case .importazione: ImportazioneInstructions()
        case .lettura:      LetturaInstructions()
        case .copertine:    CopertineInstructions()
        case .kindle:       KindleInstructions()
        case .esportazione: EsportazioneInstructions()
        case .scorciatoie:  ScorciatoieInstructions()
        }
    }
}

// MARK: - Sezioni contenuto

struct LibreriaInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "books.vertical.fill", color: .blue, title: "La Libreria", subtitle: "Gestisci e visualizza i tuoi libri")
            
            InstructionCard(icon: "square.grid.2x2", color: .blue, title: "Vista Griglia") {
                Text("Visualizza i libri come copertine. Ogni copertina mostra il **badge stato** (Da Leggere / In Lettura / Letto) e le **stelline** di valutazione. Se stai leggendo un libro, una barra arancione mostra il progresso in fondo alla copertina.")
            }
            InstructionCard(icon: "list.bullet", color: .indigo, title: "Vista Lista") {
                Text("Mostra titolo, autore e badge di stato. Seleziona più libri tenendo ⌘ o ⇧ premuto.")
            }
            InstructionCard(icon: "line.3.horizontal.decrease.circle", color: .cyan, title: "Filtri Stato") {
                Text("Usa le pill colorate sotto la toolbar per filtrare la libreria: **Tutti**, **Da Leggere**, **In Lettura**, **Letti**. Il numero mostra quanti libri sono in ogni categoria.")
            }
            InstructionCard(icon: "magnifyingglass", color: .gray, title: "Ricerca") {
                Text("Usa la barra di ricerca per filtrare per **titolo**, **autore** o **tag** in tempo reale. Puoi anche cercare i libri da **Spotlight** (⌘+Spazio) — Pencil li indicizza automaticamente.")
            }
            InstructionCard(icon: "arrow.right.circle", color: .mint, title: "Tasto Destro (Menu contestuale)") {
                Text("Clic destro su qualsiasi libro per accedere a **tutte** le azioni disponibili: modifica info, anteprima, cambia stato, valuta, cerca copertina, esporta, invia al Kindle, elimina — senza usare la toolbar.")
            }
        }
    }
}

struct ImportazioneInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "square.and.arrow.down.fill", color: .green, title: "Importare Libri", subtitle: "Più modi per aggiungere libri")
            
            InstructionCard(icon: "plus", color: .green, title: "Pulsante +") {
                Text("Clicca **+** nella toolbar per aprire il pannello di selezione file. Puoi selezionare più file EPUB o PDF contemporaneamente.")
            }
            InstructionCard(icon: "arrow.down.to.line", color: .teal, title: "Drag & Drop dall'esterno") {
                Text("Trascina uno o più file EPUB o PDF direttamente sulla libreria da Finder, Safari o qualsiasi altra app. I **duplicati** vengono rilevati automaticamente e non vengono aggiunti due volte.")
            }
            InstructionCard(icon: "tablecells", color: .orange, title: "Importa da Goodreads CSV") {
                Text("Esporta la tua libreria da **goodreads.com** (Account → Importa ed esporta → Esporta libreria) e importa il CSV con il pulsante ↓ nella toolbar. Titoli, autori, stato di lettura e valutazioni vengono importati automaticamente.")
            }
            InstructionCard(icon: "info.circle", color: .blue, title: "Metadati automatici") {
                Text("Pencil estrae automaticamente **titolo**, **autore** e **copertina** da ogni file importato usando i metadati interni dell'EPUB o la prima pagina del PDF.")
            }
            InstructionCard(icon: "externaldrive.badge.timemachine", color: .gray, title: "Backup automatico") {
                Text("Pencil esegue automaticamente un backup del database ogni 7 giorni nella cartella **Application Support/Pencil/Backups/**. Vengono mantenuti gli ultimi 10 backup.")
            }
        }
    }
}

// NUOVA sezione Stato & Rating
struct LetturaInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "star.leadinghalf.filled", color: .yellow, title: "Stato & Rating", subtitle: "Tieni traccia della tua lettura")
            
            InstructionCard(icon: "book.pages", color: .blue, title: "Stato di Lettura") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Da Leggere — in lista d'attesa", systemImage: "book.closed").font(.caption)
                    Label("In Lettura — attualmente aperto", systemImage: "book").font(.caption)
                    Label("Letto — completato", systemImage: "checkmark.seal").font(.caption)
                    Text("\nCambia lo stato dal pannello Info (clic destro → **Informazioni e Modifica…**) o direttamente dal menu contestuale → **Stato lettura**. Le date di inizio e fine vengono registrate automaticamente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            InstructionCard(icon: "slider.horizontal.3", color: .orange, title: "Progresso Lettura") {
                Text("Quando un libro è **In Lettura**, appare uno **slider 0–100%** nel pannello Info. La percentuale viene mostrata anche come barra arancione in fondo alla copertina nella vista griglia.")
            }
            InstructionCard(icon: "star.fill", color: .yellow, title: "Valutazione a Stelle") {
                Text("Assegna da 1 a 5 stelle toccando le stelle nel pannello Info. Tocca la stessa stella per azzerarla. Puoi anche valutare rapidamente con tasto destro → **Valutazione**.")
            }
            InstructionCard(icon: "tag", color: .purple, title: "Tag Personalizzati") {
                Text("Aggiungi **tag** liberi nel pannello Info (es. \"fantasy\", \"da rileggere\", \"regalo\"). I tag compaiono come chip colorati e puoi cercarli dalla barra di ricerca.")
            }
            InstructionCard(icon: "chart.bar", color: .indigo, title: "Statistiche Libreria") {
                Text("Clicca l'icona **📊** nella toolbar per vedere le statistiche: distribuzione degli stati di lettura, formati presenti, e i tuoi 5 libri con il rating più alto.")
            }
        }
    }
}

struct CopertineInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "photo.fill", color: .purple, title: "Copertine", subtitle: "Automatiche, manuali o in massa")
            
            InstructionCard(icon: "sparkle.magnifyingglass", color: .purple, title: "Cerca in automatico (singola)") {
                Text("Apri i dettagli di un libro (tasto ℹ o doppio click) e clicca **\"Cerca copertina\"**. Pencil la cerca su **Open Library** (database gratuito con milioni di libri) usando titolo e autore.")
            }
            InstructionCard(icon: "photo.badge.arrow.down", color: .indigo, title: "Aggiorna tutte in massa") {
                Text("Clicca il pulsante **\"Aggiorna Copertine\"** nella barra in alto. Pencil cercherà automaticamente le copertine mancanti per tutti i libri, uno alla volta, senza sovrascrivere quelle già presenti.")
            }
            InstructionCard(icon: "cursorarrow.and.square.on.square.dashed", color: .pink, title: "Trascina manualmente") {
                Text("Apri i dettagli di un libro e trascina un'immagine (JPG, PNG, WebP) direttamente sull'area della copertina. Funziona da Finder, da Safari o da qualsiasi altra fonte.")
            }
            InstructionCard(icon: "crop", color: .orange, title: "Formato standardizzato") {
                Text("Tutte le copertine vengono automaticamente normalizzate a **400×600 px** (proporzione 2:3, formato libro standard) indipendentemente dalla fonte, così la libreria sarà sempre uniforme.")
            }
        }
    }
}

struct KindleInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "ipad.and.arrow.forward", color: .orange, title: "Kindle", subtitle: "Invia libri al tuo dispositivo")
            
            InstructionCard(icon: "cable.connector", color: .orange, title: "Connessione via Cavo") {
                Text("Collega il Kindle al Mac con il cavo USB. Pencil lo rileva automaticamente in pochi secondi e mostra l'indicatore verde **\"Kindle\"** in alto a sinistra.")
            }
            InstructionCard(icon: "arrow.down.to.line.circle", color: .green, title: "Drag & Drop sull'icona Kindle") {
                Text("Trascina uno o più libri **sopra l'icona Kindle** (📱) nella barra in alto. Apparirà un popover con due opzioni:\n• **☁️ Via Cloud (Email)**: invia all'app Kindle tramite email Amazon\n• **🔌 Via USB (AZW3)**: converte e copia fisicamente sul dispositivo collegato")
            }
            InstructionCard(icon: "arrow.right.circle", color: .blue, title: "Tasto Destro (Context Menu)") {
                Text("Clicca col tasto destro su qualsiasi libro per accedere alle stesse opzioni di invio, più l'opzione **\"Importa nel Mac\"** per i libri Kindle-only.")
            }
            InstructionCard(icon: "square.and.arrow.down", color: .teal, title: "Importa dal Kindle") {
                Text("Passa alla vista **Kindle** dal selettore in alto. Seleziona uno o più libri e clicca **\"Importa nel Mac\"** nella barra in alto per copiarli nella libreria Mac.")
            }
            InstructionCard(icon: "eject.fill", color: .red, title: "Espulsione Sicura") {
                Text("Prima di scollegare il Kindle, clicca il pulsante **⏏** nella barra per espellerlo in modo sicuro ed evitare la corruzione dei file.")
            }
        }
    }
}

struct EsportazioneInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "square.and.arrow.up.fill", color: .teal, title: "Esportare", subtitle: "Porta i tuoi libri ovunque")
            
            InstructionCard(icon: "cursorarrow.and.square.on.square.dashed", color: .teal, title: "Drag & Drop su Finder") {
                Text("Trascina qualsiasi libro dalla libreria su Finder, la Scrivania o qualsiasi altra cartella. Il file viene esportato con il nome **\"Titolo - Autore.formato\"** in formato originale (EPUB o PDF).")
            }
            InstructionCard(icon: "square.and.arrow.up", color: .blue, title: "Pulsante Esporta") {
                Text("Seleziona uno o più libri e clicca **\"Esporta\"** nella barra in alto. Si aprirà un pannello per scegliere la cartella di destinazione. Al termine, la cartella si aprirà automaticamente in Finder.")
            }
            InstructionCard(icon: "doc.fill", color: .purple, title: "Formato di esportazione") {
                Text("I libri vengono esportati nel loro **formato originale** (EPUB o PDF) esattamente come sono stati importati. Per convertire in AZW3 usa l'opzione di invio USB al Kindle.")
            }
        }
    }
}

struct ScorciatoieInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(icon: "command", color: .gray, title: "Scorciatoie da Tastiera", subtitle: "Diventa velocissimo")
            
            ShortcutRow(keys: ["⌘", "A"],     description: "Seleziona tutti i libri visibili")
            ShortcutRow(keys: ["⌘", "click"], description: "Aggiungi / rimuovi dalla selezione")
            ShortcutRow(keys: ["⇧", "click"], description: "Seleziona un intervallo (vista lista)")
            ShortcutRow(keys: ["⌫", "Delete"],description: "Elimina i libri selezionati")
            ShortcutRow(keys: ["⌘", "F"],     description: "Apri la barra di ricerca")
            ShortcutRow(keys: ["Esc"],         description: "Chiudi la ricerca / deseleziona")
            ShortcutRow(keys: ["tasto destro"], description: "Menu contestuale con tutte le azioni disponibili")
            
            Divider().padding(.vertical, 4)
            
            InstructionCard(icon: "command.square", color: .gray, title: "Tip: Spotlight") {
                Text("Tutti i libri della libreria sono indicizzati su **Spotlight** (⌘+Spazio). Cerca il titolo o l'autore e premi Invio per aprire Pencil direttamente sul libro.")
            }
        }
    }
}

// MARK: - Componenti UI condivisi

struct InstructionHeader: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
        Divider()
    }
}

struct InstructionCard<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                content
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShortcutRow: View {
    let keys: [String]
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                        )
                }
            }
            .frame(width: 120, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
