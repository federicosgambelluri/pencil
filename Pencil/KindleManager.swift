import Foundation
import SwiftUI
import AppKit // Serve per NSSharingService (per le email)
import SwiftData

@Observable
class KindleManager {
    var isConnected: Bool = false
    var kindleURL: URL? = nil
    
    // Variabile per mostrare all'utente che l'app sta lavorando in background
    var isConverting: Bool = false
    
    // --- 1. RILEVAMENTO USB E SCANSIONE ---
    func checkConnection(modelContext: ModelContext) {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) ?? []
        
        let kindle = paths.first(where: { $0.lastPathComponent.lowercased() == "kindle" })
        
        DispatchQueue.main.async {
            if let kindle = kindle {
                if !self.isConnected {
                    self.isConnected = true
                    self.kindleURL = kindle
                    // Quando viene collegato, scansioniamo per trovare i libri
                    self.scanKindleDocuments(modelContext: modelContext)
                }
            } else {
                if self.isConnected {
                    self.isConnected = false
                    self.kindleURL = nil
                    // Non cancelliamo i file dal DB qui, restano visibili ma "offline" (semi-trasparenti)
                }
            }
        }
    }
    
    // --- 1.6 ESPULSIONE ---
    func ejectKindle() {
        guard let url = kindleURL else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            DispatchQueue.main.async {
                self.isConnected = false
                self.kindleURL = nil
                print("Kindle espulso con successo!")
            }
        } catch {
            print("Errore durante l'espulsione: \(error.localizedDescription)")
        }
    }
    
    // --- 1.5. SCANSIONE DEL KINDLE ---
    func scanKindleDocuments(modelContext: ModelContext) {
        guard let kindleRoot = kindleURL else { return }
        let documentsURL = kindleRoot.appendingPathComponent("documents")
        
        // Usa un enumeratore per cercare ricorsivamente anche nelle sottocartelle (es. Downloads)
        guard let enumerator = FileManager.default.enumerator(at: documentsURL, includingPropertiesForKeys: nil) else { return }
        
        let descriptor = FetchDescriptor<Book>()
        guard let existingBooks = try? modelContext.fetch(descriptor) else { return }
        
        var foundKindleFileNames = Set<String>()
        
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            guard ["azw3", "mobi", "pdf", "epub", "kfx"].contains(ext) else { continue }
            
            let fileName = file.lastPathComponent
            // Ignora i file di configurazione o dizionari nascosti
            if fileName.hasPrefix(".") || fileName.contains("dictionary") { continue }
            
            // Calcoliamo il percorso relativo rispetto alla cartella documents (es. "Autore/Libro.mobi")
            let kName = file.path.replacingOccurrences(of: documentsURL.path + "/", with: "")
            
            foundKindleFileNames.insert(kName)
            
            let nameWithoutExt = file.deletingPathExtension().lastPathComponent
            let components = kName.components(separatedBy: "/")
            
            var title: String = nameWithoutExt
            var author: String = "Sconosciuto"
            
            // 1. Rimuovi l'hash finale (es. _A704D7F9A8914E0D9E2654E417A3D6C6 o _B0050C47RA)
            if let range = title.range(of: "_[A-Z0-9]{10,32}$", options: .regularExpression) {
                title.removeSubrange(range)
            }
            
            // 2. Se usa lo standard "Titolo - Autore", diamo priorità a quello
            if title.contains(" - ") {
                let nameParts = title.components(separatedBy: " - ")
                if nameParts.count >= 2 {
                    title = nameParts[0].trimmingCharacters(in: .whitespaces)
                    author = nameParts[1].trimmingCharacters(in: .whitespaces)
                }
            } else {
                // 3. Deducila dalla cartella, ignorando cartelle di sistema come Downloads o Items01
                if components.count >= 2 {
                    let folderName = components[components.count - 2]
                    let ignoredFolders = ["Downloads", "Items01", "documents", ".cache"]
                    if !ignoredFolders.contains(folderName) {
                        author = folderName
                    }
                }
            }
            
            // Cerchiamo un match nel database
            if let matchedBook = existingBooks.first(where: {
                $0.kindleFileName == kName ||
                $0.kindleFileName == fileName || // per retrocompatibilità col vecchio formato DB
                ($0.title == title && $0.author == author) ||
                ($0.fileName != nil && ($0.fileName! as NSString).deletingPathExtension == nameWithoutExt)
            }) {
                if matchedBook.kindleFileName != kName {
                    matchedBook.kindleFileName = kName
                }
            } else {
                // Libro nuovo trovato SOLO sul Kindle
                let newBook = Book(title: title, author: author, format: ext, fileName: nil, kindleFileName: kName)
                modelContext.insert(newBook)
            }
        }
        
        // Pulizia: se un libro risulta sul Kindle ma il file fisico non c'è più
        for book in existingBooks {
            if let kName = book.kindleFileName, !foundKindleFileNames.contains(kName) {
                book.kindleFileName = nil
                
                // Se questo libro esisteva SOLO sul Kindle e ora è stato eliminato dal dispositivo,
                // lo eliminiamo anche dal DB locale.
                if book.fileName == nil {
                    modelContext.delete(book)
                }
            }
        }
    }
    
    // --- 2. INVIO STANDARD VIA USB (Per i PDF) ---
    func sendBook(_ book: Book) -> Bool {
        guard isConnected, let kindleRoot = kindleURL, let fileName = book.fileName else { return false }
        
        let sourceURL = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
        let safeTitle = book.title.replacingOccurrences(of: "/", with: "-")
        let safeAuthor = book.author.replacingOccurrences(of: "/", with: "-")
        
        // Strutturiamo meglio il Kindle: salviamo i file dentro una cartella con il nome dell'autore
        let authorFolder = kindleRoot.appendingPathComponent("documents/\(safeAuthor)")
        
        if !FileManager.default.fileExists(atPath: authorFolder.path) {
            try? FileManager.default.createDirectory(at: authorFolder, withIntermediateDirectories: true)
        }
        
        let destinationURL = authorFolder.appendingPathComponent("\(safeTitle) - \(safeAuthor).\(book.format)")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("Libro inviato con successo al Kindle via USB!")
            return true
        } catch {
            print("Errore durante l'invio al Kindle: \(error)")
            return false
        }
    }
    
    // --- 3. OPZIONE 1: INVIO VIA EMAIL (Cloud Amazon) ---
    func sendViaEmail(book: Book) {
        guard let fileName = book.fileName else { return }
        let sourceURL = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
        
        // Copia l'email negli appunti
        let savedEmail = UserDefaults.standard.string(forKey: "kindleEmail") ?? ""
        if !savedEmail.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(savedEmail, forType: .string)
            print("Email Kindle copiata negli appunti: \(savedEmail)")
        }
        
        // Apre la finestra standard di composizione email del Mac con il file in allegato
        let sharingService = NSSharingService(named: .composeEmail)
        sharingService?.perform(withItems: [sourceURL])
    }
    
    // --- 3.5 IMPORTA DAL KINDLE AL MAC ---
    func importFromKindle(book: Book) -> Bool {
        guard isConnected, let kindleRoot = kindleURL, let kName = book.kindleFileName else { return false }
        
        let sourceURL = kindleRoot.appendingPathComponent("documents/\(kName)")
        let ext = sourceURL.pathExtension.lowercased()
        let safeFileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = BookImporter.getLibraryFolder().appendingPathComponent(safeFileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            DispatchQueue.main.async { book.fileName = safeFileName }
            print("Importato dal Kindle con successo!")
            return true
        } catch {
            print("Errore durante l'importazione: \(error)")
            return false
        }
    }
    
    // --- 3.6 ELIMINA DAL KINDLE ---
    func deleteFromKindle(book: Book, context: ModelContext) {
        guard let kindleRoot = kindleURL, let kName = book.kindleFileName else { return }
        let fileURL = kindleRoot.appendingPathComponent("documents/\(kName)")
        do {
            try FileManager.default.removeItem(at: fileURL)
            DispatchQueue.main.async {
                book.kindleFileName = nil
                if book.fileName == nil {
                    context.delete(book)
                }
            }
            print("Libro eliminato fisicamente dal Kindle!")
        } catch {
            print("Errore durante l'eliminazione dal Kindle: \(error)")
        }
    }

    // --- 4. OPZIONE 2: CONVERSIONE E INVIO USB (Usando Kindle Previewer 3) ---
    func convertAndSendToUSB(book: Book) async -> Bool {
        guard isConnected, let kindleRoot = kindleURL, let fileName = book.fileName else { return false }
        
        DispatchQueue.main.async { self.isConverting = true }
        
        let kindlePreviewerCLI = "/Applications/Kindle Previewer 3.app/Contents/lib/fc/bin/kindlegen"
        guard FileManager.default.fileExists(atPath: kindlePreviewerCLI) else {
            print("❌ Kindle Previewer 3 non trovato")
            DispatchQueue.main.async { self.isConverting = false }
            return false
        }
        
        let sourceURL  = BookImporter.getLibraryFolder().appendingPathComponent(fileName)
        let safeTitle  = book.title.replacingOccurrences(of: "/", with: "-")
        let safeAuthor = book.author.replacingOccurrences(of: "/", with: "-")
        
        let authorFolder = kindleRoot.appendingPathComponent("documents/\(safeAuthor)")
        if !FileManager.default.fileExists(atPath: authorFolder.path) {
            try? FileManager.default.createDirectory(at: authorFolder, withIntermediateDirectories: true)
        }
        let destinationURL = authorFolder.appendingPathComponent("\(safeTitle) - \(safeAuthor).mobi")
        
        // Esegui su thread in background per poter usare waitUntilExit()
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return false }
            
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            // Copia l'EPUB originale
            let sourceEPUB = tempDir.appendingPathComponent("source.epub")
            guard let _ = try? FileManager.default.copyItem(at: sourceURL, to: sourceEPUB) else {
                DispatchQueue.main.async { self.isConverting = false }
                return false
            }
            
            // Pre-processa: corregge il NCX (causa principale del E24010)
            let inputEPUB = self.preprocessEPUB(at: sourceEPUB, in: tempDir)
            
            // kindlegen crea <nome_senza_ext>.mobi nella stessa cartella dell'input
            let outputMobi = inputEPUB.deletingPathExtension().appendingPathExtension("mobi")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: kindlePreviewerCLI)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            process.arguments = [inputEPUB.path]
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("❌ Impossibile avviare kindlegen: \(error)")
                DispatchQueue.main.async { self.isConverting = false }
                return false
            }
            
            let output   = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus
            print("kindlegen exit=\(exitCode)\n\(output)")
            
            let fileExists = FileManager.default.fileExists(atPath: outputMobi.path)
            let fileSize   = (try? FileManager.default.attributesOfItem(atPath: outputMobi.path))?[.size] as? Int ?? 0
            // exit 0 = successo, exit 1 = successo con warning CSS/link non critici
            let success    = exitCode < 2 && fileExists && fileSize > 1000
            
            if success {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: outputMobi, to: destinationURL)
                    print("✅ Inviato al Kindle: \(destinationURL.lastPathComponent)")
                } catch {
                    print("❌ Errore copia sul Kindle: \(error)")
                }
            } else {
                print("❌ Fallito — exit=\(exitCode) fileExists=\(fileExists) size=\(fileSize)")
            }
            
            DispatchQueue.main.async { self.isConverting = false }
            return success
        }.value
    }
    
    /// Pre-processa un EPUB prima di passarlo a kindlegen:
    /// estrae il ZIP, corregge i file NCX rimuovendo i fragment #anchor
    /// dai <content src> (causa del E24010 / TOC non risolvibile),
    /// poi ricompatta come EPUB valido.
    private func preprocessEPUB(at sourceURL: URL, in tempDir: URL) -> URL {
        let extractDir = tempDir.appendingPathComponent("epub_extracted")
        let fixedURL   = tempDir.appendingPathComponent("fixed.epub")
        
        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // 1. Estrai l'EPUB (è un file ZIP)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-o", sourceURL.path, "-d", extractDir.path]
        try? unzip.run()
        unzip.waitUntilExit()
        
        guard unzip.terminationStatus == 0 else {
            print("⚠️ Unzip EPUB fallito, uso originale")
            return sourceURL
        }
        
        // 2. Correggi i file NCX: rimuovi i fragment #anchor dai content src
        //    Esempio: src="OEBPS/p000_cover.xhtml#cover" → src="OEBPS/p000_cover.xhtml"
        //    Questo risolve l'errore E24010 di kindlegen.
        if let enumerator = FileManager.default.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "ncx" {
                guard var ncx = try? String(contentsOf: file, encoding: .utf8) else { continue }
                
                // Regex: <content ... src="percorso#frammento" .../>
                // Cattura tutto fino al # e rimuove #frammento
                ncx = ncx.replacingOccurrences(
                    of: "(<content\\b[^>]*\\bsrc=\"[^\"#]+)#[^\"]+\"",
                    with: "$1\"",
                    options: .regularExpression
                )
                try? ncx.write(to: file, atomically: true, encoding: .utf8)
                print("✅ NCX corretto: \(file.lastPathComponent)")
            }
        }
        
        // 3. Ricompatta come EPUB valido:
        //    Il file "mimetype" DEVE essere primo e NON compresso (spec EPUB)
        let zip1 = Process()
        zip1.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip1.currentDirectoryURL = extractDir
        zip1.arguments = ["-X", "-0", fixedURL.path, "mimetype"]  // -0 = nessuna compressione
        try? zip1.run()
        zip1.waitUntilExit()
        
        let zip2 = Process()
        zip2.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip2.currentDirectoryURL = extractDir
        zip2.arguments = ["-rg", fixedURL.path, ".", "-x", "mimetype"]
        try? zip2.run()
        zip2.waitUntilExit()
        
        if FileManager.default.fileExists(atPath: fixedURL.path) {
            print("✅ EPUB pre-processato correttamente")
            return fixedURL
        }
        
        print("⚠️ Ricompressione EPUB fallita, uso originale")
        return sourceURL
    }
}
