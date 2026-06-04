import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftData

// MARK: - Spotlight Manager
// Indicizza i libri della libreria Pencil su CoreSpotlight,
// rendendoli ricercabili da Cmd+Space come qualsiasi file macOS.

struct SpotlightManager {
    
    private static let domainID = "com.pencilapp.books"
    
    // ── Indicizza un singolo libro ────────────────────────────────────────
    static func index(book: Book) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title           = book.title
        attributeSet.contentDescription = "di \(book.author) • \(book.format.uppercased()) • \(book.readingStatus.rawValue)"
        attributeSet.keywords        = [book.title, book.author, book.format] + book.tags
        attributeSet.creator         = book.author
        attributeSet.kind            = book.format.uppercased()
        
        if let coverData = book.coverImageData {
            attributeSet.thumbnailData = coverData
        }
        
        // ID stabile basato su titolo+autore
        let identifier = spotlightID(for: book)
        let item = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainID,
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture
        
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error { print("⚠️ Spotlight index error: \(error)") }
        }
    }
    
    // ── Rimuove un libro dall'indice ─────────────────────────────────────
    static func deindex(book: Book) {
        let id = spotlightID(for: book)
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id]) { error in
            if let error { print("⚠️ Spotlight deindex error: \(error)") }
        }
    }
    
    // ── Re-indicizza tutta la libreria ────────────────────────────────────
    static func reindexAll(books: [Book]) {
        // Prima cancella tutto il dominio
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID]) { _ in
            let items = books.compactMap { book -> CSSearchableItem? in
                guard book.modelContext != nil, !book.isDeleted else { return nil }
                let attrSet = CSSearchableItemAttributeSet(contentType: .content)
                attrSet.title               = book.title
                attrSet.contentDescription  = "di \(book.author) • \(book.format.uppercased())"
                attrSet.keywords            = [book.title, book.author] + book.tags
                attrSet.creator             = book.author
                if let data = book.coverImageData { attrSet.thumbnailData = data }
                
                return CSSearchableItem(
                    uniqueIdentifier: spotlightID(for: book),
                    domainIdentifier: domainID,
                    attributeSet: attrSet
                )
            }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error { print("⚠️ Spotlight reindex error: \(error)") }
                else { print("✅ Spotlight: \(items.count) libri indicizzati") }
            }
        }
    }
    
    // ── Svuota l'indice ───────────────────────────────────────────────────
    static func clearIndex() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID]) { _ in }
    }
    
    // ── ID stabile ────────────────────────────────────────────────────────
    static func spotlightID(for book: Book) -> String {
        "\(domainID).\(book.title)-\(book.author)".replacingOccurrences(of: " ", with: "_")
    }
}
