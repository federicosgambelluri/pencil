import Foundation
import PDFKit
import CoreServices
import AppKit
// Nuova libreria Apple per generare le anteprime (copertine) dei file!
import QuickLookThumbnailing

struct BookImporter {
    
    static func getLibraryFolder() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportFolder = paths[0]
        let libraryFolder = appSupportFolder.appendingPathComponent("PencilLibrary")
        
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try? FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        return libraryFolder
    }
    
    // Converte NSImage in JPEG compresso all'80%
    private static func convertToJPEGData(image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
    
    /// Normalizza qualsiasi immagine di copertina a un formato standard 400x600 JPEG.
    /// Questo garantisce che tutte le copertine abbiano le stesse dimensioni, indipendentemente
    /// dalla fonte (Open Library, EPUB, PDF, immagine trascinata).
    static func normalizeBookCover(_ data: Data) -> Data? {
        guard let sourceImage = NSImage(data: data) else { return nil }
        
        let targetWidth: CGFloat  = 400
        let targetHeight: CGFloat = 600
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        
        // Calcola il rettangolo di crop per mantenere le proporzioni del soggetto principale
        let srcSize = sourceImage.size
        let srcRatio  = srcSize.width / srcSize.height
        let destRatio = targetWidth / targetHeight
        
        var drawRect = CGRect(origin: .zero, size: srcSize)
        if srcRatio > destRatio {
            // Immagine più larga: croppa i lati
            let newWidth = srcSize.height * destRatio
            drawRect = CGRect(x: (srcSize.width - newWidth) / 2, y: 0,
                              width: newWidth, height: srcSize.height)
        } else {
            // Immagine più alta: croppa in alto e in basso
            let newHeight = srcSize.width / destRatio
            drawRect = CGRect(x: 0, y: (srcSize.height - newHeight) / 2,
                              width: srcSize.width, height: newHeight)
        }
        
        // Disegna l'immagine ritagliata e ridimensionata
        let result = NSImage(size: targetSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: drawRect,
            operation: .copy,
            fraction: 1.0
        )
        result.unlockFocus()
        
        return convertToJPEGData(image: result)
    }
    
    // NOTA LA PAROLA 'async': Significa che questa funzione può richiedere del tempo
    // e verrà eseguita in background senza bloccare il Mac.
    static func importAndCopyFile(from originalURL: URL) async -> (title: String, author: String, format: String, fileName: String, coverImageData: Data?)? {
        var title = originalURL.deletingPathExtension().lastPathComponent
        var author = "Autore Sconosciuto"
        let format = originalURL.pathExtension.lowercased()
        
        // Nuova variabile per ospitare la copertina
        var coverData: Data? = nil
        
        if format == "pdf" {
            if let pdfDocument = PDFDocument(url: originalURL) {
                // Estrazione Testo PDF
                if let docAttributes = pdfDocument.documentAttributes {
                    if let pdfTitle = docAttributes[PDFDocumentAttribute.titleAttribute] as? String, !pdfTitle.isEmpty { title = pdfTitle }
                    if let pdfAuthor = docAttributes[PDFDocumentAttribute.authorAttribute] as? String, !pdfAuthor.isEmpty { author = pdfAuthor }
                }
                
                // Estrazione Copertina PDF (pagina 1) + normalizzazione
                if let firstPage = pdfDocument.page(at: 0) {
                    let thumbnailImage = firstPage.thumbnail(of: CGSize(width: 800, height: 1200), for: .mediaBox)
                    if let rawData = convertToJPEGData(image: thumbnailImage) {
                        coverData = normalizeBookCover(rawData) ?? rawData
                    }
                }
            }
        } else if format == "epub" {
            // Estrazione Testo EPUB
            if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, originalURL as CFURL) {
                if let mdTitle = MDItemCopyAttribute(mdItem, kMDItemTitle) as? String { title = mdTitle }
                if let mdAuthors = MDItemCopyAttribute(mdItem, kMDItemAuthors) as? [String], let firstAuthor = mdAuthors.first { author = firstAuthor }
            }
            
            // NUOVO: Estrazione Copertina EPUB tramite QuickLook
            let size = CGSize(width: 800, height: 1200)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0 // Usa la densità dei pixel del tuo schermo
            let request = QLThumbnailGenerator.Request(fileAt: originalURL, size: size, scale: scale, representationTypes: .thumbnail)
            
            do {
                let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if let rawData = convertToJPEGData(image: thumbnail.nsImage) {
                    coverData = normalizeBookCover(rawData) ?? rawData
                }
            } catch {
                print("L'EPUB non ha una copertina estraibile: \(error)")
            }
            
        } else {
            return nil
        }
        
        // Pulizia finale per file Z-Library
        let cleaned = cleanZLibraryTitle(title: title, currentAuthor: author)
        title = cleaned.0
        author = cleaned.1
        
        let uniqueID = UUID().uuidString
        let newFileName = "\(uniqueID).\(format)"
        let destinationURL = getLibraryFolder().appendingPathComponent(newFileName)
        
        do {
            try FileManager.default.copyItem(at: originalURL, to: destinationURL)
            // Restituiamo i dati estratti come "Tupla", non come Oggetto SwiftData
            return (title: title, author: author, format: format, fileName: newFileName, coverImageData: coverData)
        } catch {
            return nil
        }
    }
    
    static func cleanZLibraryTitle(title: String, currentAuthor: String) -> (String, String) {
        var newTitle = title
        var newAuthor = currentAuthor
        
        // Rimuove "(z-library.sk, 1lib.sk, z-lib.sk)" o simili
        if let range = newTitle.range(of: "\\s*\\(z-library.*?\\)", options: .regularExpression) {
            newTitle.removeSubrange(range)
        }
        if let range = newTitle.range(of: "\\s*\\(1lib.*?\\)", options: .regularExpression) {
            newTitle.removeSubrange(range)
        }
        if let range = newTitle.range(of: "\\s*\\(z-lib.*?\\)", options: .regularExpression) {
            newTitle.removeSubrange(range)
        }
        
        // Estrae l'autore dalle parentesi finali es. "(Pif)"
        if let match = newTitle.range(of: "\\s*\\(([^)]+)\\)$", options: .regularExpression) {
            let extractedAuthor = String(newTitle[match]).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
            newTitle.removeSubrange(match)
            newAuthor = extractedAuthor
        }
        
        // Rimuove la doppia ripetizione dell'autore tra parentesi quadre: "Ashlee Vance [Vance, Ashlee]"
        if let bracketMatch = newAuthor.range(of: "\\s*\\[.*?\\]", options: .regularExpression) {
            newAuthor.removeSubrange(bracketMatch)
        }
        
        return (newTitle.trimmingCharacters(in: .whitespaces), newAuthor.trimmingCharacters(in: .whitespaces))
    }
    
    static func deleteFile(named fileName: String) {
        let fileURL = getLibraryFolder().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Copertina automatica via Open Library (gratuito, nessuna API key)
    /// Cerca una copertina su openlibrary.org tramite titolo e autore.
    /// Restituisce i dati JPEG della copertina, o nil se non trovata.
    static func fetchCoverFromOpenLibrary(title: String, author: String) async -> Data? {
        // Step 1: Cerca l'ISBN tramite l'API di ricerca
        let query = "\(title) \(author)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURLString = "https://openlibrary.org/search.json?q=\(query)&limit=5&fields=isbn,cover_i"
        
        guard let searchURL = URL(string: searchURLString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let docs = json?["docs"] as? [[String: Any]] ?? []
            
            // Strategia 1: usa cover_i (ID interno Open Library)
            for doc in docs {
                if let coverId = doc["cover_i"] as? Int {
                    let coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg")!
                    let (imageData, response) = try await URLSession.shared.data(from: coverURL)
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                       imageData.count > 1000 {
                        // Normalizza al formato standard 400x600
                        return normalizeBookCover(imageData) ?? imageData
                    }
                }
            }
            
            // Strategia 2: usa il primo ISBN disponibile
            for doc in docs {
                if let isbns = doc["isbn"] as? [String], let isbn = isbns.first {
                    let coverURL = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg")!
                    let (imageData, response) = try await URLSession.shared.data(from: coverURL)
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                       imageData.count > 1000 {
                        return normalizeBookCover(imageData) ?? imageData
                    }
                }
            }
            
        } catch {
            print("Open Library fetch error: \(error)")
        }
        
        return nil
    }
    
    // MARK: - API iTunes per la trama
    static func fetchPlotFromITunes(title: String, author: String) async -> String? {
        let query = "\(title) \(author)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(query)&media=ebook&country=IT"
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let results = json?["results"] as? [[String: Any]],
                   let firstItem = results.first,
                   let description = firstItem["description"] as? String {
                    
                    // Rimuovi tag HTML e decodifica entità base
                    let cleanString = description
                        .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "&amp;", with: "&")
                    
                    return cleanString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("Errore fetch plot da iTunes: \(error)")
        }
        return nil
    }
    
    // MARK: - Rilevamento duplicati
    /// Restituisce true se esiste già un libro con lo stesso titolo e autore
    static func checkDuplicate(title: String, author: String, books: [Book]) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let a = author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return books.contains { b in
            b.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == t &&
            b.author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == a
        }
    }
    
    // MARK: - Import Goodreads CSV
    /// Importa metadati dalla lista esportata da Goodreads (File > Export Library in Goodreads).
    /// Crea record Book SENZA file fisico (solo metadati: titolo, autore, valutazione, stato).
    /// Restituisce (imported, skipped).
    static func importFromGoodreadsCSV(url: URL, existingBooks: [Book]) -> (imported: Int, skipped: Int) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return (0, 0) }
        let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return (0, 0) }
        
        // Legge intestazioni
        let headers = parseCSVLine(lines[0])
        func col(_ name: String) -> Int? { headers.firstIndex(where: { $0.lowercased().contains(name.lowercased()) }) }
        
        let titleIdx  = col("title")
        let authorIdx = col("author")
        let ratingIdx = col("my rating")
        let shelfIdx  = col("exclusive shelf")
        
        guard let ti = titleIdx, let ai = authorIdx else { return (0, 0) }
        
        var imported = 0
        var skipped  = 0
        var newBooks: [Book] = []
        
        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count > max(ti, ai) else { continue }
            
            let title  = fields[ti].trimmingCharacters(in: .whitespacesAndNewlines)
            let author = fields[ai].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            
            // Salta duplicati
            if checkDuplicate(title: title, author: author, books: existingBooks + newBooks) {
                skipped += 1
                continue
            }
            
            let rating = ratingIdx.flatMap { fields.count > $0 ? Int(fields[$0]) : nil } ?? 0
            let shelf  = shelfIdx.flatMap  { fields.count > $0 ? fields[$0] : nil } ?? ""
            
            let status: ReadingStatus
            switch shelf.lowercased() {
            case "read":            status = .read
            case "currently-reading": status = .reading
            default:                status = .toRead
            }
            
            let book = Book(
                title: title,
                author: author,
                format: "epub",   // Goodreads non conosce il formato fisico
                fileName: nil,    // Nessun file fisico — solo metadati
                readingStatus: status,
                rating: min(rating, 5)
            )
            newBooks.append(book)
            imported += 1
        }
        
        // I Book vengono restituiti ma devono essere inseriti nel modelContext dal chiamante
        // Usiamo una notifica per passarli (i ModelContext non sono thread-safe cross-struct)
        NotificationCenter.default.post(
            name: .goodreadsImportCompleted,
            object: nil,
            userInfo: ["books": newBooks]
        )
        
        return (imported, skipped)
    }
    
    // Parser CSV minimale che gestisce campi tra virgolette
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                if inQuotes && line.index(after: i) < line.endIndex && line[line.index(after: i)] == "\"" {
                    current.append("\"")
                    i = line.index(after: i)
                } else {
                    inQuotes.toggle()
                }
            } else if c == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
    
    // MARK: - Backup automatico
    /// Copia il file .sqlite del database in Application Support/PencilApp/Backups/
    static func performBackup() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL   = appSupport.appendingPathComponent("PencilApp/Library.sqlite")
        let backupDir  = appSupport.appendingPathComponent("PencilApp/Backups")
        
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let name = "Library_\(formatter.string(from: Date())).sqlite"
        let dest = backupDir.appendingPathComponent(name)
        
        do {
            for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
                let src = appSupport.appendingPathComponent("PencilApp/Library.\(ext)")
                let dst = backupDir.appendingPathComponent("Library_\(formatter.string(from: Date())).\(ext)")
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }
            print("✅ Backup eseguito")
            
            // Mantieni solo gli ultimi 10 backup
            let files = (try? FileManager.default.contentsOfDirectory(
                at: backupDir, includingPropertiesForKeys: [.creationDateKey], options: []
            )) ?? []
            let sorted = files.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2
            }
            for old in sorted.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
        } catch {
            print("⚠️ Backup fallito: \(error)")
        }
    }
    
    // MARK: - Export/Import Completo Libreria
    static func exportFullLibrary(to destFolder: URL) async -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbBase = appSupport.appendingPathComponent("PencilApp")
        let libFolder = getLibraryFolder()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let backupDir = destFolder.appendingPathComponent("Pencil_Backup_\(formatter.string(from: Date()))")
        
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            
            let dbDest = backupDir.appendingPathComponent("Database")
            try FileManager.default.createDirectory(at: dbDest, withIntermediateDirectories: true)
            for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
                let file = dbBase.appendingPathComponent("Library.\(ext)")
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.copyItem(at: file, to: dbDest.appendingPathComponent("Library.\(ext)"))
                }
            }
            
            let filesDest = backupDir.appendingPathComponent("Files")
            try FileManager.default.copyItem(at: libFolder, to: filesDest)
            
            return true
        } catch {
            print("Export error: \(error)")
            return false
        }
    }
    
    static func importFullLibrary(from sourceFolder: URL) async -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbBase = appSupport.appendingPathComponent("PencilApp")
        let libFolder = getLibraryFolder()
        
        let dbSource = sourceFolder.appendingPathComponent("Database/Library.sqlite")
        let filesSource = sourceFolder.appendingPathComponent("Files")
        
        guard FileManager.default.fileExists(atPath: dbSource.path) else { return false }
        
        do {
            for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
                let file = dbBase.appendingPathComponent("Library.\(ext)")
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            }
            for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
                let sourceFile = sourceFolder.appendingPathComponent("Database/Library.\(ext)")
                if FileManager.default.fileExists(atPath: sourceFile.path) {
                    try FileManager.default.copyItem(at: sourceFile, to: dbBase.appendingPathComponent("Library.\(ext)"))
                }
            }
            
            if FileManager.default.fileExists(atPath: filesSource.path) {
                let items = try FileManager.default.contentsOfDirectory(at: filesSource, includingPropertiesForKeys: nil)
                for item in items {
                    let dest = libFolder.appendingPathComponent(item.lastPathComponent)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: item, to: dest)
                }
            }
            
            return true
        } catch {
            print("Import error: \(error)")
            return false
        }
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let goodreadsImportCompleted = Notification.Name("goodreadsImportCompleted")
    static let fixZLibraryTitles = Notification.Name("fixZLibraryTitles")
}

