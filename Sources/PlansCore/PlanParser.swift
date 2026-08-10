import Foundation

public enum PlanParser {
    private static let metadataMissing = "metadata_missing"
    private static let requiredSections = [
        "Overview",
        "Context",
        "Implementation Steps",
        "Validation Commands",
        "Acceptance Criteria",
        "Risks / Open Questions"
    ]
    private static let noncanonicalSections: Set<String> = [
        "Testing Strategy", "Validation", "Acceptance", "Outcome Contract",
        "Проверки", "Валидация", "Критерии приёмки", "Критерии приемки",
        "Итоги реализации", "Итог реализации"
    ]

    public static func parse(
        fileURL: URL,
        relativePath: String,
        bucket: PlanBucket,
        now: Date = Date()
    ) -> PlanRecord {
        guard
            let data = try? Data(contentsOf: fileURL),
            let content = String(data: data, encoding: .utf8)
        else {
            return invalidRecord(
                fileURL: fileURL,
                relativePath: relativePath,
                bucket: bucket,
                errors: ["unparseable_plan"]
            )
        }

        let view = StructuralView(content)
        let structuralLines = view.lines
        let firstContent = structuralLines.first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let title = firstContent?.text.hasPrefix("# ") == true
            ? String(firstContent!.text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            : fileURL.deletingPathExtension().lastPathComponent

        var errors: [String] = []
        if firstContent?.text.hasPrefix("# ") != true || title.isEmpty {
            appendUnique("unparseable_plan", to: &errors)
        }
        if view.unclosedFence {
            appendUnique("unclosed_code_fence", to: &errors)
        }

        let firstSectionLine = structuralLines.first { $0.text.hasPrefix("## ") }?.number ?? Int.max
        let metadataRows = structuralLines.compactMap { line -> (String, String, Int)? in
            guard line.number < firstSectionLine, let field = metadataField(line.text) else { return nil }
            return (field.key, field.value, line.number)
        }
        let knownFields: Set<String> = ["Plan-Version", "Status", "Created", "Completed", "Scope"]
        var metadata: [String: String] = [:]
        var seen: Set<String> = []

        for row in metadataRows {
            guard knownFields.contains(row.0) else {
                appendUnique("unknown_metadata_field", to: &errors)
                continue
            }
            if !seen.insert(row.0).inserted {
                appendUnique("duplicate_metadata_field", to: &errors)
            } else {
                metadata[row.0] = row.1
            }
        }

        let expectedMetadata = bucket == .completed
            ? ["Plan-Version", "Status", "Created", "Completed", "Scope"]
            : ["Plan-Version", "Status", "Created", "Scope"]
        if expectedMetadata.contains(where: { metadata[$0]?.isEmpty ?? true }) {
            appendUnique("missing_required_metadata", to: &errors)
        }
        let recognizedOrder = metadataRows.map(\.0).filter(knownFields.contains)
        if recognizedOrder != expectedMetadata {
            appendUnique("invalid_metadata_order", to: &errors)
        }
        if structuralLines.contains(where: { line in
            guard line.number > firstSectionLine, let field = metadataField(line.text) else { return false }
            return knownFields.contains(field.key)
        }) {
            appendUnique("metadata_after_sections", to: &errors)
        }

        let planVersion = metadata["Plan-Version"] ?? metadataMissing
        if planVersion != "1" {
            appendUnique("unsupported_plan_version", to: &errors)
        }

        let status = metadata["Status"] ?? metadataMissing
        let created = metadata["Created"] ?? metadataMissing
        let completed = metadata["Completed"] ?? metadataMissing
        let scope = metadata["Scope"] ?? metadataMissing

        if !isValidDate(created) || (completed != metadataMissing && !isValidDate(completed)) {
            appendUnique("invalid_date", to: &errors)
        }
        if completed != metadataMissing, created != metadataMissing, completed < created {
            appendUnique("completed_before_created", to: &errors)
        }
        if !allowedStatuses(for: bucket).contains(status) {
            appendUnique(knownStatuses.contains(status) ? "bucket_status_mismatch" : "invalid_status", to: &errors)
        }

        validateFilename(fileURL.lastPathComponent, relativePath: relativePath, bucket: bucket, created: created, errors: &errors)

        let sectionRows = structuralLines.compactMap { line -> (String, Int)? in
            guard line.text.hasPrefix("## ") else { return nil }
            return (String(line.text.dropFirst(3)).trimmingCharacters(in: .whitespaces), line.number)
        }
        var sectionCounts: [String: Int] = [:]
        for section in sectionRows {
            sectionCounts[section.0, default: 0] += 1
            if noncanonicalSections.contains(section.0) {
                appendUnique("noncanonical_section", to: &errors)
            }
        }
        if sectionCounts.values.contains(where: { $0 > 1 }) {
            appendUnique("duplicate_section", to: &errors)
        }
        let completedRequired = bucket == .completed ? ["Completion Notes"] : []
        let allRequired = requiredSections + completedRequired
        if allRequired.contains(where: { sectionCounts[$0] == nil }) {
            appendUnique("missing_required_section", to: &errors)
        }
        let presentRequired = sectionRows.map(\.0).filter { allRequired.contains($0) }
        if presentRequired != allRequired.filter({ presentRequired.contains($0) }) {
            appendUnique("invalid_section_order", to: &errors)
        }

        var currentSection: String?
        var checkboxTotal = 0
        var checkboxDone = 0
        var openSteps: [String] = []
        for line in structuralLines {
            if line.text.hasPrefix("## ") {
                currentSection = String(line.text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let checkbox = checkbox(line.text) else { continue }
            if currentSection != "Implementation Steps" {
                appendUnique("checkbox_outside_implementation_steps", to: &errors)
                continue
            }
            checkboxTotal += 1
            if checkbox.done {
                checkboxDone += 1
            } else {
                openSteps.append(checkbox.text)
            }
        }

        if bucket == .completed, !openSteps.isEmpty {
            appendUnique("completed_open_steps", to: &errors)
        }
        if let validationBody = sectionBody("Validation Commands", rows: sectionRows, rawLines: view.rawLines) {
            let lower = validationBody.lowercased()
            if !containsFence(validationBody) && !lower.contains("manual") {
                appendUnique("empty_validation_commands", to: &errors)
            }
        }
        if bucket == .completed,
           let completionBody = sectionBody("Completion Notes", rows: sectionRows, rawLines: view.rawLines),
           completionBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendUnique("empty_completion_notes", to: &errors)
        }
        let structuralContent = structuralLines.map(\.text).joined(separator: "\n").lowercased()
        if structuralContent.contains("<script")
            || structuralContent.contains("<html")
            || structuralContent.contains("<!doctype html") {
            appendUnique("raw_executable_html", to: &errors)
        }

        var warnings: [String] = []
        if status == "draft" { warnings.append("status_draft") }
        if status == "blocked" { warnings.append("status_blocked") }
        if status == "paused" { warnings.append("status_paused") }

        let progress = checkboxTotal == 0 ? nil : Int((Double(checkboxDone) / Double(checkboxTotal) * 100).rounded())
        return PlanRecord(
            relativePath: relativePath,
            absolutePath: fileURL.path,
            bucket: bucket,
            parseState: errors.isEmpty ? .parsed : .invalidPlan,
            planVersion: planVersion,
            title: title,
            status: status,
            created: created,
            completed: completed,
            scope: scope,
            checkboxTotal: checkboxTotal,
            checkboxDone: checkboxDone,
            progressPercent: progress,
            nextOpenStep: openSteps.first,
            lintErrors: errors,
            lintWarnings: warnings,
            daysSinceModified: daysSinceModified(fileURL, now: now)
        )
    }

    private static let knownStatuses: Set<String> = ["backlog", "active", "draft", "blocked", "paused", "completed"]

    private static func allowedStatuses(for bucket: PlanBucket) -> Set<String> {
        switch bucket {
        case .backlog: return ["backlog"]
        case .active: return ["active", "draft", "blocked", "paused"]
        case .completed: return ["completed"]
        }
    }

    private static func validateFilename(
        _ filename: String,
        relativePath: String,
        bucket: PlanBucket,
        created: String,
        errors: inout [String]
    ) {
        let components = relativePath.split(separator: "/").map(String.init)
        let direct = components.count == 4
            && components[0] == "docs"
            && components[1] == "plans"
            && components[2] == bucket.rawValue
            && components[3] == filename
        let pattern = #"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$"#
        if !direct || filename.range(of: pattern, options: .regularExpression) == nil {
            appendUnique("invalid_filename", to: &errors)
            return
        }
        let filenameDate = String(filename.prefix(10))
        if created != metadataMissing, filenameDate != created {
            appendUnique("filename_created_mismatch", to: &errors)
        }
    }

    private static func invalidRecord(
        fileURL: URL,
        relativePath: String,
        bucket: PlanBucket,
        errors: [String]
    ) -> PlanRecord {
        PlanRecord(
            relativePath: relativePath,
            absolutePath: fileURL.path,
            bucket: bucket,
            parseState: .invalidPlan,
            planVersion: metadataMissing,
            title: fileURL.deletingPathExtension().lastPathComponent,
            status: metadataMissing,
            created: metadataMissing,
            completed: metadataMissing,
            scope: metadataMissing,
            checkboxTotal: 0,
            checkboxDone: 0,
            progressPercent: nil,
            nextOpenStep: nil,
            lintErrors: errors,
            lintWarnings: [],
            daysSinceModified: nil
        )
    }

    private static func metadataField(_ text: String) -> (key: String, value: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let key = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
        guard key.range(of: #"^[A-Za-z][A-Za-z-]*$"#, options: .regularExpression) != nil else { return nil }
        let value = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func checkbox(_ text: String) -> (done: Bool, text: String)? {
        let pattern = #"^- \[([ xX])\] (.+)$"#
        guard let match = text.firstMatch(pattern) else { return nil }
        return (match[1].lowercased() == "x", match[2].trimmingCharacters(in: .whitespaces))
    }

    private static func sectionBody(
        _ name: String,
        rows: [(String, Int)],
        rawLines: [String]
    ) -> String? {
        guard let index = rows.firstIndex(where: { $0.0 == name }) else { return nil }
        let start = rows[index].1
        let end = index + 1 < rows.count ? rows[index + 1].1 - 1 : rawLines.count
        guard start < end else { return "" }
        return rawLines[start..<end].joined(separator: "\n")
    }

    private static func containsFence(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            fence(String(line)) != nil
        }
    }

    private static func isValidDate(_ value: String) -> Bool {
        guard value != metadataMissing,
              value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private static func daysSinceModified(_ fileURL: URL, now: Date) -> Int? {
        guard
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
            let modified = values.contentModificationDate
        else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: modified, to: now).day ?? 0)
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        if !values.contains(value) { values.append(value) }
    }

    private struct StructuralLine {
        let text: String
        let number: Int
    }

    private struct StructuralView {
        let lines: [StructuralLine]
        let rawLines: [String]
        let unclosedFence: Bool

        init(_ content: String) {
            rawLines = content.components(separatedBy: .newlines)
            var result: [StructuralLine] = []
            var opening: (character: Character, count: Int)?

            for (offset, line) in rawLines.enumerated() {
                if let current = opening {
                    if let candidate = PlanParser.fence(line),
                       candidate.character == current.character,
                       candidate.count >= current.count,
                       candidate.trailing.isEmpty {
                        opening = nil
                    }
                    continue
                }
                if let candidate = PlanParser.fence(line) {
                    opening = (candidate.character, candidate.count)
                    continue
                }
                result.append(StructuralLine(text: line, number: offset + 1))
            }

            lines = result
            unclosedFence = opening != nil
        }
    }

    private static func fence(_ line: String) -> (character: Character, count: Int, trailing: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let trailing = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return (first, count, trailing)
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = expression.firstMatch(in: self, range: range), match.range == range else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: self) else { return "" }
            return String(self[range])
        }
    }
}
