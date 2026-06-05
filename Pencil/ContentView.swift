import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import Quartz

enum ViewStyle {
    case list, grid
}

enum SortType: String, CaseIterable {
    case title = "Titolo"
    case author = "Autore"
    case dateAdded = "Data di Aggiunta"
    case dateModified = "Data di Modifica"
}

enum LibrarySource: String, CaseIterable {
    case mac = "Libreria Mac"
    case kindle = "Libreria Kindle"
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @Query private var books: [Book]
    
    // Il nostro gestore del Kindle
    @State private var kindleManager = KindleManager()
    
    @State private var librarySource: LibrarySource = .mac
    @State private var selectedBooks: Set<Book> = []
    @State private var viewStyle: ViewStyle = .grid
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var sortType: SortType = .title
    @State private var sortAscending: Bool = true
    
    // Stato per la barra di ricerca
    @State private var searchText: String = ""
    
    // Questa è la variabile che probabilmente era saltata!
    @State private var isImportingFiles = false
    
    @State private var showKindlePreviewerAlert = false
    @AppStorage("hideKindlePreviewerAlert") private var hideKindlePreviewerAlert = false
    
    // Alert per errori di conversione (es. EPUB corrotto)
    @State private var showConversionErrorAlert = false
    @State private var showConversionSuccessAlert = false
    
    // STATO PER DRAG & DROP POPOVER
    @State private var showKindleDropPopover: Bool = false
    @State private var kindleIconTargeted: Bool = false
    @State private var draggedBooks: [Book] = []
    
    // STATO PER INFO SHEET
    @State private var showInfoSheet: Bool = false
    
    // STATO PER FETCH COPERTINE IN MASSA
    @State private var isBulkFetchingCovers: Bool = false
    @State private var bulkFetchProgress: String = ""
    
    // STATO PER ESPORTAZIONE
    @State private var isExporting: Bool = false
    
    // SISTEMA TOAST
    @State private var toasts: [AppToast] = []
    
    // NUOVI STATI
    @State private var statusFilter: ReadingStatus? = nil   // nil = tutti
    @State private var showStats: Bool = false
    @State private var showGoodreadsImport: Bool = false
    @State private var showQuickLook: Bool = false
    @State private var quickLookBook: Book? = nil
    
    @State private var hideKindleBooks: Bool = false
    @State private var showConversionQueue: Bool = false
    
    var sortedBooks: [Book] {
        let filtered = books.filter { book in
            guard book.modelContext != nil, !book.isDeleted else { return false }
            let fName = book.fileName
            let kName = book.kindleFileName
            let isKOnly = (fName == nil && kName != nil)
            let isSync  = (fName != nil && kName != nil)
            let matchesSource = (librarySource == .mac) ? !isKOnly : (isKOnly || isSync)
            if !matchesSource { return false }
            
            if librarySource == .mac && hideKindleBooks && isSync { return false }
            
            // Filtro per stato di lettura
            if let filter = statusFilter, book.readingStatus != filter { return false }
            
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return book.title.lowercased().contains(q) ||
                   book.author.lowercased().contains(q) ||
                   book.tags.contains { $0.lowercased().contains(q) }
        }
        return filtered.sorted { b1, b2 in
            switch sortType {
            case .title:        return sortAscending ? b1.title < b2.title : b1.title > b2.title
            case .author:       return sortAscending ? b1.author < b2.author : b1.author > b2.author
            case .dateAdded:    return sortAscending ? b1.dateAdded < b2.dateAdded : b1.dateAdded > b2.dateAdded
            case .dateModified: return sortAscending ? b1.dateModified < b2.dateModified : b1.dateModified > b2.dateModified
            }
        }
    }
    var body: some View {
        Group {
            if viewStyle == .list {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    listView
                        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                } detail: {
                    listDetailView
                }
                .navigationTitle("Libreria Pencil")
                .searchable(text: $searchText, prompt: "Cerca titolo, autore o tag...")
                .toolbar { toolbarContent }
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        // Barra filtro stato lettura
                        statusFilterBar
                        gridView
                    }
                    .navigationTitle("Libreria Pencil")
                    .searchable(text: $searchText, prompt: "Cerca titolo, autore o tag...")
                    .toolbar { toolbarContent }
                }
            }
        }
        // OVERLAY TOAST
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                ForEach(toasts) { toast in
                    ToastView(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 16)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toasts)
        }
        // Sheet statistiche
        .sheet(isPresented: $showStats) {
            NavigationStack {
                StatsView(books: books.filter { $0.modelContext != nil && !$0.isDeleted })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Chiudi") { showStats = false }
                        }
                    }
                    .navigationTitle("Statistiche")
            }
        }
        // Quick Look
        .sheet(isPresented: $showQuickLook) {
            if let book = quickLookBook, let fileName = book.fileName {
                let url = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
                QuickLookSheet(url: url)
            }
        }
        .onChange(of: viewStyle) { oldValue, newValue in
            if newValue == .grid {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
        .onAppear {
            columnVisibility = viewStyle == .grid ? .detailOnly : .all
            let isInstalled = FileManager.default.fileExists(atPath: "/Applications/Kindle Previewer 3.app/Contents/lib/fc/bin/kindlegen")
            if !isInstalled && !hideKindlePreviewerAlert { showKindlePreviewerAlert = true }
            // Indicizza tutti i libri su Spotlight all'avvio
            let validBooks = books.filter { $0.modelContext != nil && !$0.isDeleted }
            SpotlightManager.reindexAll(books: validBooks)
        }
        .background {
            Button("Seleziona Tutto") {
                if selectedBooks.count == sortedBooks.count && !sortedBooks.isEmpty {
                    selectedBooks.removeAll()
                } else {
                    selectedBooks = Set(sortedBooks)
                }
            }
                .keyboardShortcut("a", modifiers: .command).opacity(0)
        }
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.epub, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let imported = handleDrop(items: urls)
                if imported { showToast(.success, title: "Importazione avviata", subtitle: "I file verranno aggiunti alla libreria") }
            case .failure(let error):
                showToast(.error, title: "Importazione fallita", subtitle: error.localizedDescription)
            }
        }
        // Import Goodreads CSV
        .fileImporter(isPresented: $showGoodreadsImport, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                url.startAccessingSecurityScopedResource()
                let (imp, skip) = BookImporter.importFromGoodreadsCSV(url: url, existingBooks: Array(books))
                url.stopAccessingSecurityScopedResource()
                showToast(imp > 0 ? .success : .warning,
                    title: "\(imp) libri importati da Goodreads",
                    subtitle: skip > 0 ? "\(skip) già presenti saltati" : nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goodreadsImportCompleted)) { note in
            if let newBooks = note.userInfo?["books"] as? [Book] {
                for book in newBooks {
                    modelContext.insert(book)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fixZLibraryTitles)) { _ in
            var fixedCount = 0
            for book in books {
                if book.modelContext != nil && !book.isDeleted {
                    let cleaned = BookImporter.cleanZLibraryTitle(title: book.title, currentAuthor: book.author)
                    if cleaned.0 != book.title || cleaned.1 != book.author {
                        book.title = cleaned.0
                        book.author = cleaned.1
                        book.dateModified = Date()
                        fixedCount += 1
                    }
                }
            }
            if fixedCount > 0 {
                showToast(.success, title: "Titoli corretti", subtitle: "\(fixedCount) libri aggiornati")
            } else {
                showToast(.info, title: "Nessun titolo da correggere", subtitle: "Tutti i titoli sono a posto")
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                kindleManager.checkConnection(modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Barra filtro stato lettura
    var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StatusPill(label: "Tutti", count: books.filter { $0.modelContext != nil && !$0.isDeleted }.count,
                           color: .primary, isSelected: statusFilter == nil) {
                    withAnimation(.spring(response: 0.3)) { statusFilter = nil }
                }
                ForEach(ReadingStatus.allCases, id: \.self) { s in
                    let cnt = books.filter { $0.modelContext != nil && !$0.isDeleted && $0.readingStatus == s }.count
                    StatusPill(label: s.rawValue, count: cnt,
                               color: statusPillColor(s), isSelected: statusFilter == s) {
                        withAnimation(.spring(response: 0.3)) {
                            statusFilter = (statusFilter == s) ? nil : s
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
    
    private func statusPillColor(_ s: ReadingStatus) -> Color {
        switch s {
        case .toRead:  return .blue
        case .reading: return .orange
        case .read:    return .green
        case .abandoned: return .red
        }
    }
    
    // Estratto per evitare timeout del type-checker Swift (errore 111)
    @ViewBuilder
    private var listDetailView: some View {
        if selectedBooks.count == 1, let book = selectedBooks.first {
            BookDetailView(book: book)
        } else if selectedBooks.count > 1 {
            Text("\(selectedBooks.count) libri selezionati")
                .font(.title)
                .foregroundStyle(.secondary)
        } else {
            Text("Seleziona un libro o usa il tasto +")
                .foregroundStyle(.secondary)
        }
    }
    
    enum DropMethod { case cloud, usb }

    
    // Nuovo handler: usa draggedBooks
    private func handleKindleMethod(_ method: DropMethod) {
        showKindleDropPopover = false
        let booksToSend = draggedBooks
        draggedBooks = []
        guard !booksToSend.isEmpty else { return }
        
        if method == .cloud {
            for book in booksToSend {
                kindleManager.sendViaEmail(book: book)
            }
            showToast(.success, title: "Inviati via Email", subtitle: "\(booksToSend.count) libri in elaborazione")
        } else if method == .usb {
            kindleManager.addToQueue(books: booksToSend, modelContext: modelContext)
            showConversionQueue = true
            showToast(.info, title: "Inviati alla coda", subtitle: "\(booksToSend.count) libri in elaborazione")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 1. STATO KINDLE
        ToolbarItem(placement: .navigation) {
            Button {
                if !kindleManager.conversionQueue.isEmpty {
                    showConversionQueue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: kindleManager.isConnected ? "ipad.and.arrow.forward" : "ipad")
                        .foregroundColor(kindleIconTargeted ? .orange : (kindleManager.isConnected ? .green : .secondary))
                        .scaleEffect(kindleIconTargeted ? 1.25 : 1.0)
                        .animation(.spring(response: 0.3), value: kindleIconTargeted)
                    
                    if kindleManager.isConnected {
                        if kindleManager.isConverting {
                            ProgressView().controlSize(.small)
                            Text("Conversione...").font(.caption).bold().foregroundColor(.orange)
                        } else {
                            Text("Kindle").font(.caption).bold().foregroundColor(.green)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .popover(isPresented: $showConversionQueue, arrowEdge: .top) {
                ConversionQueueView(kindleManager: kindleManager)
            }
            .help("Trascina un libro qui per inviarlo al Kindle")
            // Usa onDrop(of: .item) — accetta QUALSIASI drag senza leggere dati
            // Il libro viene passato tramite la variabile draggedBooks
            .onDrop(of: [.item], isTargeted: $kindleIconTargeted) { _ in
                if !draggedBooks.isEmpty {
                    showKindleDropPopover = true
                }
                return true
            }
            .popover(isPresented: $showKindleDropPopover, arrowEdge: .bottom) {
                KindleDropPopoverView(kindleManager: kindleManager, onSelect: { method in
                    handleKindleMethod(method)
                })
            }
        }
        
        if kindleManager.isConnected {
            // TASTO REFRESH
            if !kindleManager.isConverting {
                ToolbarItem(placement: .automatic) {
                    Button {
                        kindleManager.scanKindleDocuments(modelContext: modelContext)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Aggiorna Libreria Kindle")
                }
                
                // TASTO ESPULSIONE
                ToolbarItem(placement: .automatic) {
                    Button {
                        kindleManager.ejectKindle()
                    } label: {
                        Image(systemName: "eject.fill")
                    }
                    .help("Espelli Kindle in sicurezza")
                }
            }
            
            // CODA DI CONVERSIONE (sempre visibile se c'è coda)
            if !kindleManager.conversionQueue.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showConversionQueue.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            if kindleManager.isConverting {
                                ProgressView().controlSize(.small)
                            }
                            Image(systemName: "list.bullet.rectangle.portrait")
                        }
                    }
                    .help("Mostra coda di conversione")
                }
            }
        }
        
        if librarySource == .mac && kindleManager.isConnected {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $hideKindleBooks) {
                    Label("Nascondi libri sul Kindle", systemImage: hideKindleBooks ? "ipad.slash" : "ipad")
                }
                .toggleStyle(.button)
                .help("Nascondi dalla libreria Mac i libri che sono già presenti sul Kindle")
            }
        }
        
        // 2. SELETTORE LIBRERIA (Centrale)
        ToolbarItem(placement: .principal) {
            Picker("Libreria", selection: $librarySource) {
                Text("Mac").tag(LibrarySource.mac)
                
                // Nascondiamo direttamente il tab se non è connesso
                if kindleManager.isConnected {
                    Text("Kindle").tag(LibrarySource.kindle)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .onChange(of: kindleManager.isConnected) { oldValue, newValue in
                if !newValue && librarySource == .kindle {
                    librarySource = .mac // Torna al Mac se scolleghiamo il Kindle
                }
            }
        }
        
        // 2.5 PULSANTI AZIONE
        ToolbarItemGroup(placement: .primaryAction) {
            Button { isImportingFiles = true } label: {
                Label("Aggiungi Libro", systemImage: "plus")
            }
            .help("Importa file dal Mac")
            .disabled(librarySource == .kindle)
            
            Button { showInfoSheet = true } label: {
                Label("Informazioni", systemImage: "info.circle")
            }
            .help("Modifica informazioni libro selezionato")
            .disabled(selectedBooks.count != 1)
            .sheet(isPresented: $showInfoSheet) {
                if let book = selectedBooks.first {
                    NavigationStack {
                        BookDetailView(book: book)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Chiudi") { showInfoSheet = false }
                                }
                            }
                    }
                    .frame(minWidth: 600, minHeight: 500)
                }
            }
            
            // Quick Look anteprima
            Button {
                quickLookBook = selectedBooks.first
                showQuickLook = true
            } label: {
                Label("Anteprima", systemImage: "eye")
            }
            .help("Anteprima rapida del file")
            .disabled(selectedBooks.count != 1 || selectedBooks.first?.fileName == nil)
            
            // Statistiche
            Button { showStats = true } label: {
                Label("Statistiche", systemImage: "chart.pie.fill")
            }
            .help("Statistiche della libreria")
            
            // Import da Goodreads
            Button { showGoodreadsImport = true } label: {
                Label("Import Goodreads", systemImage: "square.and.arrow.down.on.square")
            }
            .help("Importa da Goodreads CSV")
            .disabled(librarySource == .kindle)
            
            if librarySource == .kindle && kindleManager.isConnected {
                Button {
                    for book in selectedBooks {
                        let ok = kindleManager.importFromKindle(book: book)
                        if ok { showToast(.success, title: "Importato", subtitle: book.title) }
                    }
                    selectedBooks.removeAll()
                } label: {
                    Label("Importa nel Mac", systemImage: "square.and.arrow.down")
                }
                .help("Copia i libri selezionati dal Kindle alla libreria Mac")
                .disabled(selectedBooks.isEmpty)
            }
            
            Button {
                for book in selectedBooks { deleteBook(book) }
                selectedBooks.removeAll()
            } label: {
                Label("Elimina Selezionati", systemImage: "trash")
            }
            .help("Elimina i libri selezionati")
            .disabled(selectedBooks.isEmpty)
        }
        
        // 3. ORDINAMENTO E VISUALIZZAZIONE (Rimangono nel loro gruppo naturale)
        ToolbarItemGroup(placement: .primaryAction) {
            // MENU ORDINAMENTO
            Menu {
                Picker("Ordina per", selection: $sortType) {
                    ForEach(SortType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                }
                Divider()
                Toggle(isOn: $sortAscending) { Text(sortAscending ? "Ordine Crescente" : "Ordine Decrescente") }
            } label: { Label("Ordina", systemImage: "arrow.up.arrow.down") }
            
            // PULSANTE AGGIORNA COPERTINE IN MASSA
            Button {
                bulkFetchAllCovers()
            } label: {
                if isBulkFetchingCovers {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(bulkFetchProgress).font(.caption).lineLimit(1)
                    }
                } else {
                    Label("Aggiorna Copertine", systemImage: "photo.badge.arrow.down")
                }
            }
            .help("Cerca e scarica automaticamente le copertine mancanti per tutti i libri")
            .disabled(isBulkFetchingCovers || librarySource == .kindle)
            
            // SELETTORE VISTA
            Picker("Visualizzazione", selection: $viewStyle) {
                Image(systemName: "list.bullet").tag(ViewStyle.list)
                Image(systemName: "square.grid.2x2").tag(ViewStyle.grid)
            }
            .pickerStyle(.segmented)
            
            // IMPOSTAZIONI
            Button {
                try? openSettings()
            } label: {
                Label("Impostazioni", systemImage: "gear")
            }
            .help("Apri Impostazioni")
        }
    }

    
    // Lista in vista lista: usa onDrag per esportare
    var listView: some View {
        List(selection: $selectedBooks) {
            ForEach(sortedBooks) { book in
                HStack(spacing: 10) {
                    if let imageData = book.coverImageData, let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage).resizable().scaledToFill().frame(width: 40, height: 60).clipped().cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)).frame(width: 40, height: 60)
                    }
                    VStack(alignment: .leading) {
                        Text(book.title).font(.headline).lineLimit(1)
                        Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if book.isLocalOnly {
                        Image(systemName: "macwindow").foregroundStyle(.secondary)
                    } else if book.isKindleOnly {
                        Image(systemName: "ipad").foregroundStyle(.secondary)
                    } else if book.isSynced {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .opacity((book.isKindleOnly && !kindleManager.isConnected) ? 0.5 : 1.0)
                .onDrag {
                    if selectedBooks.contains(book) && selectedBooks.count > 1 {
                        draggedBooks = Array(selectedBooks)
                    } else {
                        draggedBooks = [book]
                    }
                    return makeItemProvider(for: book)
                }
                .tag(book)
                .contextMenu {
                    bookContextMenu(for: book)
                }
            }
            .onDelete(perform: deleteBooksFromList)
        }
        .dropDestination(for: URL.self) { items, _ in handleDrop(items: items) }
    }
    
    // MARK: - VISUALIZZAZIONE A GRIGLIA
    var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 30) {
                ForEach(sortedBooks) { book in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink(destination: BookDetailView(book: book)) {
                            GridBookCell(book: book, isKindleConnected: kindleManager.isConnected)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            if selectedBooks.contains(book) { selectedBooks.remove(book) }
                            else { selectedBooks.insert(book) }
                        } label: {
                            Image(systemName: selectedBooks.contains(book) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundColor(selectedBooks.contains(book) ? .blue : .white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.3)).padding(2))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedBooks.contains(book) ? Color.blue : Color.clear, lineWidth: 4)
                    )
                    .onDrag {
                        if selectedBooks.contains(book) && selectedBooks.count > 1 {
                            draggedBooks = Array(selectedBooks)
                        } else {
                            draggedBooks = [book]
                        }
                        return makeItemProvider(for: book)
                    }
                    .contextMenu {
                        bookContextMenu(for: book)
                    }
                }
            }
            .padding()
        }
        .dropDestination(for: URL.self) { items, _ in handleDrop(items: items) }
        .alert("Kindle Previewer Richiesto", isPresented: $showKindlePreviewerAlert) {
            Button("Scarica ORA") {
                if let url = URL(string: "https://kdp.amazon.com/it_IT/help/topic/G202131170") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Non mostrare più") { hideKindlePreviewerAlert = true }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Per convertire e inviare i file nativamente sul tuo Kindle, hai bisogno del convertitore ufficiale di Amazon.\n\nScarica l'app gratuita 'Kindle Previewer 3' cliccando sul bottone qui sotto e installala.")
        }
        .alert("Errore di Conversione", isPresented: $showConversionErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Si è verificato un errore durante la conversione del file (spesso a causa di un file EPUB difettoso con link o indici corrotti). Il file originale non è stato modificato, ma la conversione per Kindle è fallita.")
        }
        .alert("Conversione Riuscita", isPresented: $showConversionSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Il file è stato convertito e inviato con successo al tuo Kindle!")
        }
        .onChange(of: librarySource) {
            selectedBooks.removeAll()
        }
    }
    
    // MARK: - FETCH COPERTINE IN MASSA
    private func bulkFetchAllCovers() {
        let booksWithoutCover = books.filter { book in
            guard book.modelContext != nil, !book.isDeleted else { return false }
            return book.coverImageData == nil && book.fileName != nil
        }
        
        guard !booksWithoutCover.isEmpty else {
            showToast(.info, title: "Copertine già presenti", subtitle: "Tutti i libri hanno già una copertina")
            return
        }
        
        isBulkFetchingCovers = true
        bulkFetchProgress = "0/\(booksWithoutCover.count)"
        
        Task {
            var found = 0
            for (index, book) in booksWithoutCover.enumerated() {
                await MainActor.run {
                    bulkFetchProgress = "\(index + 1)/\(booksWithoutCover.count)"
                }
                if let data = await BookImporter.fetchCoverFromOpenLibrary(title: book.title, author: book.author) {
                    await MainActor.run {
                        book.coverImageData = data
                        book.dateModified = Date()
                        found += 1
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await MainActor.run {
                isBulkFetchingCovers = false
                bulkFetchProgress = ""
                let missed = booksWithoutCover.count - found
                if found > 0 && missed == 0 {
                    showToast(.success, title: "\(found) copertine trovate!", subtitle: "Tutti i libri hanno ora una copertina")
                } else if found > 0 {
                    showToast(.warning, title: "\(found) trovate, \(missed) non trovate", subtitle: "Alcuni titoli non sono su Open Library")
                } else {
                    showToast(.error, title: "Nessuna copertina trovata", subtitle: "I titoli non corrispondono nel database")
                }
            }
        }
    }
    
    // MARK: - ESPORTAZIONE
    private func makeItemProvider(for book: Book) -> NSItemProvider {
        let provider = NSItemProvider()
        
        let safeTitle  = book.title.replacingOccurrences(of: "/", with: "-")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeAuthor = book.author.replacingOccurrences(of: "/", with: "-")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatStr  = book.format.isEmpty ? "epub" : book.format
        let exportName = "\(safeTitle) - \(safeAuthor).\(formatStr)"
        
        // macOS usa questo come nome del file quando si posa il drag su Finder/Scrivania
        provider.suggestedName = exportName
        
        // ── 1. Rappresentazione testo (per il drop interno sull'icona Kindle) ──────
        // SwiftUI dropDestination(for: String.self) legge "public.utf8-plain-text"
        let internalID = "pencil-book://\(book.title) - \(book.author)"
        let textData   = internalID.data(using: .utf8)
        
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(textData, nil)
            return nil
        }
        
        // ── 2. Dati grezzi del file (per Finder / Scrivania) ─────────────────────
        // NON usiamo registerFileRepresentation né NSItemProvider(contentsOf:)
        // perché entrambi tentano di condividere un file-URL attraverso il sandbox
        // (entitlement com.apple.security.temporary-exception.files.absolute-path)
        // che causa "Sandbox extension data required" e l'URL corrotto.
        // registerDataRepresentation con i byte del file è sandbox-safe al 100%.
        if let fileName = book.fileName {
            let sourceURL = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
            if let fileData = try? Data(contentsOf: sourceURL) {
                // UTType specifico per il formato (epub → org.idpf.epub-container, pdf → com.adobe.pdf …)
                let fileTypeID = UTType(filenameExtension: formatStr)?.identifier
                               ?? UTType.data.identifier
                
                provider.registerDataRepresentation(
                    forTypeIdentifier: fileTypeID,
                    visibility: .all
                ) { completion in
                    completion(fileData, nil)
                    return nil
                }
            }
        }
        
        return provider
    }
    
    private func exportSelectedBooks() {
        let booksToExport = selectedBooks.filter { $0.fileName != nil }
        guard !booksToExport.isEmpty else { return }
        
        let panel = NSOpenPanel()
        panel.title = "Scegli cartella di destinazione"
        panel.message = "I libri selezionati verranno copiati in questa cartella"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Esporta qui"
        
        guard panel.runModal() == .OK, let destFolder = panel.url else { return }
        
        isExporting = true
        Task {
            var exported = 0
            for book in booksToExport {
                guard let fileName = book.fileName else { continue }
                let safeTitle  = book.title.replacingOccurrences(of: "/", with: "-")
                let safeAuthor = book.author.replacingOccurrences(of: "/", with: "-")
                let formatStr  = book.format.isEmpty ? "epub" : book.format
                let sourceURL  = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
                let destURL    = destFolder.appendingPathComponent("\(safeTitle) - \(safeAuthor).\(formatStr)")
                var finalURL = destURL
                var counter = 1
                while FileManager.default.fileExists(atPath: finalURL.path) {
                    finalURL = destFolder.appendingPathComponent("\(safeTitle) - \(safeAuthor) (\(counter)).\(formatStr)")
                    counter += 1
                }
                if (try? FileManager.default.copyItem(at: sourceURL, to: finalURL)) != nil {
                    exported += 1
                }
            }
            await MainActor.run {
                isExporting = false
                if exported > 0 {
                    NSWorkspace.shared.open(destFolder)
                    showToast(.success, title: "\(exported) libri esportati", subtitle: "Cartella aperta in Finder")
                } else {
                    showToast(.error, title: "Esportazione fallita", subtitle: "Impossibile copiare i file")
                }
            }
        }
    }
    
    // MARK: - TOAST
    func showToast(_ type: AppToast.ToastType, title: String, subtitle: String? = nil) {
        let t = AppToast(type: type, title: title, subtitle: subtitle)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            toasts.append(t)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                toasts.removeAll { $0.id == t.id }
            }
        }
    }
    
    // MARK: - FUNZIONI DI UTILITÀ
    private func handleDrop(items: [URL]) -> Bool {
        let validExtensions = ["epub", "pdf"]
        let validItems = items.filter { validExtensions.contains($0.pathExtension.lowercased()) }
        if validItems.isEmpty { return false }
        
        let container = modelContext.container
        let existingBooks = Array(books)
        
        Task {
            let backgroundContext = ModelContext(container)
            var imported = 0
            var skipped  = 0
            
            for url in validItems {
                let hasAccess = url.startAccessingSecurityScopedResource()
                if let bookData = await BookImporter.importAndCopyFile(from: url) {
                    // Controllo duplicati
                    if BookImporter.checkDuplicate(title: bookData.title, author: bookData.author, books: existingBooks) {
                        skipped += 1
                        // Elimina il file copiato nel frattempo
                        BookImporter.deleteFile(named: bookData.fileName)
                    } else {
                        let newBook = Book(title: bookData.title, author: bookData.author,
                                          format: bookData.format, fileName: bookData.fileName,
                                          coverImageData: bookData.coverImageData)
                        backgroundContext.insert(newBook)
                        try? backgroundContext.save()
                        SpotlightManager.index(book: newBook)
                        imported += 1
                    }
                }
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            
            await MainActor.run {
                if skipped > 0 {
                    showToast(.warning,
                              title: "\(imported) importati, \(skipped) duplicati",
                              subtitle: "I duplicati non sono stati aggiunti")
                }
            }
        }
        return true
    }
    
    private func deleteBook(_ book: Book) {
        if librarySource == .mac {
            if let fileName = book.fileName {
                BookImporter.deleteFile(named: fileName)
                book.fileName = nil
            }
            if book.kindleFileName == nil {
                modelContext.delete(book)
            }
            showToast(.success, title: "Libro eliminato", subtitle: book.title)
        } else {
            if kindleManager.isConnected {
                kindleManager.deleteFromKindle(book: book, context: modelContext)
                showToast(.success, title: "Eliminato dal Kindle", subtitle: book.title)
            } else {
                showToast(.error, title: "Kindle non connesso", subtitle: "Collega il Kindle per eliminare")
            }
        }
        if selectedBooks.contains(book) { selectedBooks.remove(book) }
    }
    private func deleteBooksFromList(offsets: IndexSet) { for index in offsets { deleteBook(sortedBooks[index]) } }
    
    // MARK: - COMPONENTI CONTEXT MENU
    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        
        // ── INFORMAZIONI & ANTEPRIMA ───────────────────────────────────
        Button {
            selectedBooks = [book]
            showInfoSheet = true
        } label: {
            Label("Informazioni e Modifica…", systemImage: "info.circle")
        }
        
        if book.fileName != nil {
            Button {
                quickLookBook = book
                showQuickLook = true
            } label: {
                Label("Anteprima rapida", systemImage: "eye")
            }
        }
        
        Divider()
        
        // ── STATO DI LETTURA ──────────────────────────────────────────
        Menu {
            ForEach(ReadingStatus.allCases, id: \.self) { status in
                Button {
                    book.readingStatus = status
                    book.dateModified = Date()
                    if status == .reading && book.startedDate == nil { book.startedDate = Date() }
                    if status == .read   && book.finishedDate == nil { book.finishedDate = Date() }
                    showToast(.success, title: "Stato aggiornato", subtitle: "\(book.title) → \(status.rawValue)")
                } label: {
                    Label(status.rawValue, systemImage:
                          book.readingStatus == status ? "checkmark" : status.icon)
                }
            }
        } label: {
            Label("Stato lettura: \(book.readingStatus.rawValue)", systemImage: book.readingStatus.icon)
        }
        
        // ── VALUTAZIONE ────────────────────────────────────────────────
        Menu {
            Button { book.rating = 0; book.dateModified = Date() } label: {
                Label("Nessuna", systemImage: book.rating == 0 ? "checkmark" : "xmark")
            }
            Divider()
            ForEach(1...5, id: \.self) { n in
                Button {
                    book.rating = n; book.dateModified = Date()
                } label: {
                    Label(String(repeating: "★", count: n), systemImage: book.rating == n ? "checkmark" : "star")
                }
            }
        } label: {
            Label(book.rating == 0 ? "Valutazione" : String(repeating: "★", count: book.rating),
                  systemImage: "star")
        }
        
        Divider()
        
        // ── COPERTINA ─────────────────────────────────────────────────
        if !book.isKindleOnly {
            Button {
                Task {
                    if let data = await BookImporter.fetchCoverFromOpenLibrary(title: book.title, author: book.author) {
                        await MainActor.run {
                            book.coverImageData = data
                            book.dateModified = Date()
                            showToast(.success, title: "Copertina trovata", subtitle: book.title)
                        }
                    } else {
                        await MainActor.run {
                            showToast(.warning, title: "Copertina non trovata", subtitle: book.title)
                        }
                    }
                }
            } label: {
                Label("Cerca copertina online", systemImage: "sparkle.magnifyingglass")
            }
            
            if book.coverImageData != nil {
                Button(role: .destructive) {
                    book.coverImageData = nil
                    book.dateModified = Date()
                } label: {
                    Label("Rimuovi copertina", systemImage: "photo.slash")
                }
            }
            
            Divider()
        }
        
        // ── ESPORTAZIONE ──────────────────────────────────────────────
        if book.fileName != nil {
            Button {
                selectedBooks = [book]
                exportSelectedBooks()
            } label: {
                Label("Esporta su Finder…", systemImage: "square.and.arrow.up")
            }
        }
        
        // ── KINDLE ────────────────────────────────────────────────────
        if book.fileName != nil {
            if ["epub", "pdf"].contains(book.format) {
                Button {
                    kindleManager.sendViaEmail(book: book)
                    showToast(.success, title: "Inviato via Email", subtitle: book.title)
                } label: {
                    Label("Invia via Cloud (Email Amazon)", systemImage: "envelope")
                }
            }
            
            if kindleManager.isConnected {
                Button {
                    Task {
                        let installed = FileManager.default.fileExists(atPath: "/Applications/Kindle Previewer 3.app/Contents/lib/fc/bin/kindlegen")
                        if !installed && !hideKindlePreviewerAlert {
                            await MainActor.run { showKindlePreviewerAlert = true }
                        } else {
                            await MainActor.run {
                                kindleManager.addToQueue(books: [book], modelContext: modelContext)
                                showConversionQueue = true
                                showToast(.info, title: "Inviato alla coda", subtitle: book.title)
                            }
                        }
                    }
                } label: {
                    Label("Converti e invia via USB (AZW3)", systemImage: "cable.connector")
                }
            }
        }
        
        if book.isKindleOnly && kindleManager.isConnected {
            Button {
                let ok = kindleManager.importFromKindle(book: book)
                showToast(ok ? .success : .error,
                          title: ok ? "Importato nel Mac" : "Importazione fallita",
                          subtitle: book.title)
            } label: {
                Label("Importa nel Mac", systemImage: "square.and.arrow.down")
            }
        }
        
        Divider()
        
        // ── ELIMINA ───────────────────────────────────────────────────
        Button(role: .destructive) {
            if selectedBooks.contains(book) {
                for b in selectedBooks { deleteBook(b) }
                selectedBooks.removeAll()
            } else {
                deleteBook(book)
            }
        } label: {
            Label(
                selectedBooks.count > 1 && selectedBooks.contains(book)
                    ? "Elimina \(selectedBooks.count) libri"
                    : "Elimina",
                systemImage: "trash"
            )
        }
    }
}

// MARK: - POPOVER DROP KINDLE (ora con pulsanti, non zone di drop)
struct KindleDropPopoverView: View {
    var kindleManager: KindleManager
    var onSelect: (ContentView.DropMethod) -> Void
    @State private var cloudHovered = false
    @State private var usbHovered = false
    
    var body: some View {
        HStack(spacing: 0) {
            // CLOUD
            Button { onSelect(.cloud) } label: {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(cloudHovered ? 0.22 : 0.12))
                            .frame(width: 64, height: 64)
                            .animation(.easeInOut(duration: 0.15), value: cloudHovered)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.blue)
                    }
                    Text("Via Cloud")
                        .font(.headline)
                    Text("(Email Amazon)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140, height: 160)
                .contentShape(Rectangle())
                .background(cloudHovered ? Color.blue.opacity(0.07) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { cloudHovered = $0 }
            
            Divider()
            
            // USB
            if kindleManager.isConnected {
                Button { onSelect(.usb) } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(usbHovered ? 0.22 : 0.12))
                                .frame(width: 64, height: 64)
                                .animation(.easeInOut(duration: 0.15), value: usbHovered)
                            Image(systemName: "cable.connector")
                                .font(.system(size: 30))
                                .foregroundStyle(.green)
                        }
                        Text("Via USB")
                            .font(.headline)
                        Text("(Converti in AZW3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 140, height: 160)
                    .contentShape(Rectangle())
                    .background(usbHovered ? Color.green.opacity(0.07) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { usbHovered = $0 }
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: 64, height: 64)
                        Image(systemName: "cable.connector")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                    Text("Via USB")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("(Kindle non collegato)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140, height: 160)
            }
        }
    }
}
struct GridBookCell: View {
    var book: Book
    var isKindleConnected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Copertina
            ZStack(alignment: .bottom) {
                ZStack(alignment: .topTrailing) {
                    if let imageData = book.coverImageData, let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable().scaledToFill()
                            .aspectRatio(2/3, contentMode: .fit)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 2, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color.secondary.opacity(0.15), Color.secondary.opacity(0.05)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "book.closed").font(.title2)
                                    Text(book.format.uppercased()).font(.caption2.bold())
                                }
                                .foregroundStyle(.tertiary)
                            )
                    }
                    
                    // Badge sorgente (top trailing)
                    Group {
                        if book.isSynced {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if book.isKindleOnly {
                            Image(systemName: "ipad").foregroundStyle(.white)
                        }
                    }
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(6)
                }
                
                // Progress bar (solo se In Lettura)
                if book.readingStatus == .reading && book.readingProgress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.4))
                            Rectangle()
                                .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * book.readingProgress)
                        }
                        .frame(height: 3)
                        .cornerRadius(2)
                    }
                    .frame(height: 3)
                }
            }
            
            // Testo
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(book.author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    // Pill stato lettura
                    StatusBadge(status: book.readingStatus)
                    Spacer()
                    // Stelline (compatte)
                    if book.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...book.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity((book.isKindleOnly && !isKindleConnected) ? 0.5 : 1.0)
    }
}

// Badge compatto per lo stato di lettura
struct StatusBadge: View {
    let status: ReadingStatus
    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(statusColor.gradient))
    }
    private var statusColor: Color {
        switch status {
        case .toRead:  return .blue
        case .reading: return .orange
        case .read:    return .green
        case .abandoned: return .red
        }
    }
}

struct BookDetailView: View {
    @Bindable var book: Book
    @State private var isFetchingCover = false
    @State private var fetchCoverResult: String? = nil
    @State private var newTag: String = ""
    
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 30) {
                // ── Colonna Sinistra: Copertina ──────────────────────────────
                VStack(spacing: 12) {
                    ZStack {
                        if let imageData = book.coverImageData, let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable().scaledToFit()
                                .frame(width: 180, height: 270)
                                .cornerRadius(10)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.4),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .frame(width: 180, height: 270)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.07)))
                                .overlay(VStack(spacing: 10) {
                                    Image(systemName: book.isKindleOnly ? "ipad" : "photo")
                                        .font(.largeTitle)
                                    Text(book.isKindleOnly ? "Nessuna copertina" : "Trascina qui la copertina")
                                        .multilineTextAlignment(.center)
                                        .font(.callout)
                                }.foregroundStyle(.secondary))
                        }
                    }
                    .dropDestination(for: URL.self) { items, _ in
                        if book.isKindleOnly { return false }
                        for url in items {
                            if ["jpg","jpeg","png","webp"].contains(url.pathExtension.lowercased()) {
                                if let raw = try? Data(contentsOf: url) {
                                    book.coverImageData = BookImporter.normalizeBookCover(raw) ?? raw
                                    book.dateModified = Date()
                                    return true
                                }
                            }
                        }
                        return false
                    }
                    
                    if !book.isKindleOnly {
                        Button {
                            isFetchingCover = true; fetchCoverResult = nil
                            Task {
                                let data = await BookImporter.fetchCoverFromOpenLibrary(title: book.title, author: book.author)
                                await MainActor.run {
                                    if let data { book.coverImageData = data; book.dateModified = Date(); fetchCoverResult = "✅ Trovata" }
                                    else { fetchCoverResult = "❌ Non trovata" }
                                    isFetchingCover = false
                                }
                            }
                        } label: {
                            if isFetchingCover { ProgressView().controlSize(.small) }
                            else { Label("Cerca copertina", systemImage: "sparkle.magnifyingglass") }
                        }
                        .buttonStyle(.borderedProminent).disabled(isFetchingCover)
                        if let r = fetchCoverResult { Text(r).font(.caption).foregroundStyle(.secondary) }
                    }
                    if book.coverImageData != nil {
                        Button(role: .destructive) { book.coverImageData = nil; book.dateModified = Date() } label: {
                            Label("Rimuovi", systemImage: "trash")
                        }.disabled(book.isKindleOnly)
                    }
                }
                
                // ── Colonna Destra: Form ─────────────────────────────────────
                Form {
                    if book.isKindleOnly {
                        Section {
                            Text("⚠️ Libro solo su Kindle. Per modificare i metadati, importalo prima nel Mac.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    
                    Section("Informazioni Principali") {
                        TextField("Titolo",  text: $book.title).onChange(of: book.title)  { book.dateModified = Date() }.disabled(book.isKindleOnly)
                        TextField("Autore",  text: $book.author).onChange(of: book.author) { book.dateModified = Date() }.disabled(book.isKindleOnly)
                        TextField("Formato", text: $book.format).disabled(book.isKindleOnly)
                    }
                    
                    // ── Stato di lettura ──────────────────────────────────
                    Section("Lettura") {
                        Picker("Stato", selection: $book.readingStatus) {
                            ForEach(ReadingStatus.allCases, id: \.self) { s in
                                Label(s.rawValue, systemImage: s.icon).tag(s)
                            }
                        }
                        .onChange(of: book.readingStatus) {
                            book.dateModified = Date()
                            if book.readingStatus == .reading && book.startedDate == nil { book.startedDate = Date() }
                            if book.readingStatus == .read && book.finishedDate == nil { book.finishedDate = Date() }
                        }
                        
                        if book.readingStatus == .reading {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Progresso")
                                    Spacer()
                                    Text("\(Int(book.readingProgress * 100))%")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                                Slider(value: $book.readingProgress, in: 0...1) { _ in
                                    book.dateModified = Date()
                                }
                                .tint(.orange)
                            }
                        }
                        
                        if let d = book.startedDate {
                            LabeledContent("Iniziato") {
                                Text(d.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let d = book.finishedDate {
                            LabeledContent("Terminato") {
                                Text(d.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // ── Valutazione ────────────────────────────────────────
                    Section("Valutazione") {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= book.rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= book.rating ? Color.yellow : Color.secondary)
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.2)) {
                                            book.rating = (book.rating == star) ? 0 : star
                                            book.dateModified = Date()
                                        }
                                    }
                                    .scaleEffect(star <= book.rating ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.2), value: book.rating)
                            }
                            if book.rating > 0 {
                                Text("\(book.rating)/5")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        }
                    }
                    
                    // ── Trama ───────────────────────────────────────────────
                    Section("Trama") {
                        HStack {
                            Button("Cerca online") {
                                Task {
                                    if let plot = await BookImporter.fetchPlotFromITunes(title: book.title, author: book.author) {
                                        await MainActor.run {
                                            book.plot = plot
                                            book.dateModified = Date()
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        TextEditor(text: $book.plot)
                            .frame(minHeight: 100)
                            .onChange(of: book.plot) { book.dateModified = Date() }
                    }
                    
                    // ── Tag ───────────────────────────────────────────────
                    Section("Tag") {
                        // Chips esistenti
                        if !book.tags.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(book.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.system(size: 12))
                                        Button { book.tags.removeAll { $0 == tag }; book.dateModified = Date() } label: {
                                            Image(systemName: "xmark").font(.system(size: 9))
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1))
                                }
                            }
                        }
                        // Campo aggiunta tag
                        HStack {
                            TextField("Aggiungi tag...", text: $newTag)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addTag() }
                            Button("Aggiungi") { addTag() }
                                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(24)
        }
        .navigationTitle(book.title)
    }
    
    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !book.tags.contains(t) else { newTag = ""; return }
        book.tags.append(t)
        book.dateModified = Date()
        newTag = ""
    }
}

// Layout a flusso per i tag chip
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}



// MARK: - COMPONENTI UI NUOVI

// Pill per filtrare per stato lettura
struct StatusPill: View {
    let label: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? .white.opacity(0.25) : color.opacity(0.15)))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.clear)))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}

// Quick Look nativo per EPUB/PDF
struct QuickLookSheet: View {
    let url: URL
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            QuickLookPreviewSwiftUI(url: url)
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

struct QuickLookPreviewSwiftUI: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.previewItem = url as QLPreviewItem
        return v
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}

// MARK: - HELPER: Drag & Drop identifiers only (no more broken Transferable)
// Il drag ora usa onDrag+NSItemProvider direttamente nelle view list/grid.

// MARK: - SISTEMA TOAST
struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let subtitle: String?
    
    enum ToastType {
        case success, error, warning, info
        
        var color: Color {
            switch self {
            case .success: return .green
            case .error:   return .red
            case .warning: return .orange
            case .info:    return .blue
            }
        }
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error:   return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }
    }
}

struct ToastView: View {
    let toast: AppToast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(toast.type.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let sub = toast.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(toast.type.color.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: 340)
    }
}

// MARK: - CODA DI CONVERSIONE
struct ConversionQueueView: View {
    var kindleManager: KindleManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Coda di Conversione")
                    .font(.headline)
                Spacer()
                if !kindleManager.conversionQueue.isEmpty {
                    Button("Pulisci completati") {
                        kindleManager.clearCompletedJobs()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding()
            .background(.bar)
            
            if kindleManager.conversionQueue.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessuna conversione in coda")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(kindleManager.conversionQueue) { job in
                        HStack(spacing: 12) {
                            Group {
                                switch job.status {
                                case .waiting:
                                    Image(systemName: "clock")
                                        .foregroundColor(.secondary)
                                case .converting:
                                    ProgressView().controlSize(.small)
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                case .failed(_):
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.book.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                if case .failed(let err) = job.status {
                                    Text(err)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                } else {
                                    Text(job.book.author)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            
                            // Bottone per annullare/rimuovere
                            Button {
                                kindleManager.cancelJob(id: job.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rimuovi dalla coda")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 300, maxHeight: 600)
            }
        }
        .frame(width: 380)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
