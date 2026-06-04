import SwiftUI
import Charts
import SwiftData

// MARK: - StatsView
// Schermata statistiche in stile macOS 26 "Liquid Glass"

struct StatsView: View {
    let books: [Book]
    
    // ── Dati aggregati ────────────────────────────────────────────────
    private var totalMac: Int    { books.filter { $0.fileName != nil }.count }
    private var totalKindle: Int { books.filter { $0.kindleFileName != nil }.count }
    private var totalRead: Int   { books.filter { $0.readingStatus == .read }.count }
    private var totalReading: Int{ books.filter { $0.readingStatus == .reading }.count }
    private var totalToRead: Int { books.filter { $0.readingStatus == .toRead }.count }
    private var missingCovers: Int { books.filter { $0.coverImageData == nil && $0.fileName != nil }.count }
    private var avgRating: Double {
        let rated = books.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.map { $0.rating }.reduce(0, +)) / Double(rated.count)
    }
    private var topRated: [Book] {
        books.filter { $0.rating == 5 }.prefix(5).map { $0 }
    }
    private var formatCounts: [(format: String, count: Int)] {
        Dictionary(grouping: books.filter { $0.fileName != nil }, by: { $0.format.lowercased() })
            .map { (format: $0.key.uppercased(), count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    private var statusData: [(label: String, count: Int, color: Color)] {
        [
            ("Da Leggere", totalToRead, .blue),
            ("In Lettura", totalReading, .orange),
            ("Letti",      totalRead,   .green)
        ].filter { $0.count > 0 }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ── Header ───────────────────────────────────────────
                headerSection
                
                // ── Griglia contatori ────────────────────────────────
                countersGrid
                
                // ── Grafici ──────────────────────────────────────────
                HStack(alignment: .top, spacing: 20) {
                    statusPieCard
                    formatBarCard
                }
                
                // ── Top rated ────────────────────────────────────────
                if !topRated.isEmpty {
                    topRatedSection
                }
                
                // ── Footer ───────────────────────────────────────────
                Text("Basato su \(books.count) libri in libreria")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 480)
    }
    
    // MARK: - Sezioni
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("La tua Libreria")
                    .font(.largeTitle.bold())
                Text("\(books.count) libri totali")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Stelle medie
            if avgRating > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: Double(i) <= avgRating ? "star.fill" : (Double(i) - 0.5 <= avgRating ? "star.leadinghalf.filled" : "star"))
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }
                    Text(String(format: "%.1f media", avgRating))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var countersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(value: totalMac,     label: "Su Mac",           icon: "macwindow",          color: .blue)
            StatCard(value: totalKindle,  label: "Su Kindle",        icon: "ipad",               color: .orange)
            StatCard(value: totalRead,    label: "Letti",            icon: "checkmark.circle",   color: .green)
            StatCard(value: totalReading, label: "In Lettura",       icon: "book.fill",           color: .purple)
            StatCard(value: totalToRead,  label: "Da Leggere",       icon: "bookmark",           color: .indigo)
            StatCard(value: missingCovers,label: "Copertine mancanti",icon: "photo.slash",       color: .red)
        }
    }
    
    private var statusPieCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Stato Lettura", systemImage: "chart.pie.fill")
                    .font(.headline)
                
                if statusData.isEmpty {
                    Text("Nessun dato")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    Chart(statusData, id: \.label) { item in
                        SectorMark(
                            angle: .value("Libri", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(item.color.gradient)
                        .cornerRadius(4)
                    }
                    .frame(height: 160)
                    
                    // Legenda
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(statusData, id: \.label) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.color).frame(width: 8, height: 8)
                                Text(item.label).font(.caption)
                                Spacer()
                                Text("\(item.count)").font(.caption.bold())
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var formatBarCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Per Formato", systemImage: "doc.richtext")
                    .font(.headline)
                
                if formatCounts.isEmpty {
                    Text("Nessun libro Mac")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    Chart(formatCounts, id: \.format) { item in
                        BarMark(
                            x: .value("Formato", item.format),
                            y: .value("Libri", item.count)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(item.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
    }
    
    private var topRatedSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("★ 5 Stelle", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                
                ForEach(topRated) { book in
                    HStack(spacing: 10) {
                        if let data = book.coverImageData, let img = NSImage(data: data) {
                            Image(nsImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 32, height: 48)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 32, height: 48)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title).font(.subheadline.bold()).lineLimit(1)
                            Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { _ in
                                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Componenti condivisi

struct StatCard: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color
    
    @State private var appeared = false
    
    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                Text("\(value)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
