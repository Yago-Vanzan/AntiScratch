import Foundation

enum NoteMode: Equatable { case plain, math, sum, average, count, list, timer }

struct NoteResult: Equatable {
    let label: String
    let value: String
}

struct NoteAnalysis: Equatable {
    var mode: NoteMode = .plain
    var results: [NoteResult] = []
    var timerDuration: TimeInterval?
}

enum NoteEngine {
    static func renderInlineResults(in text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard let header = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              header.lowercased().hasPrefix("math:") else { return text }

        var variables: [String: Double] = [:]
        for index in lines.indices.dropFirst() {
            let original = lines[index]
            let trimmed = original.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }

            if let equal = trimmed.firstIndex(of: "=") {
                let expression = String(trimmed[..<equal]).trimmingCharacters(in: .whitespaces)
                let assignment = variableAssignment(in: expression)
                let calculation = assignment?.expression ?? expression
                let rendered: String?
                var numericValue: Double?
                if let converted = conversion(calculation) {
                    rendered = converted.text
                    numericValue = converted.value
                } else if let value = evaluate(calculation, variables: variables) {
                    rendered = format(value)
                    numericValue = value
                } else {
                    rendered = nil
                }
                if let rendered {
                    let indentation = original.prefix { $0 == " " || $0 == "\t" }
                    lines[index] = "\(indentation)\(expression) = \(rendered)"
                }
                if let assignment, let numericValue { variables[assignment.name] = numericValue }
                continue
            }

            if let colon = trimmed.firstIndex(of: ":") {
                let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let expression = String(trimmed[trimmed.index(after: colon)...])
                if let converted = conversion(expression) { variables[name] = converted.value }
                else if let value = evaluate(expression, variables: variables) { variables[name] = value }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func analyze(_ text: String) -> NoteAnalysis {
        let lines = text.components(separatedBy: .newlines)
        let header = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard header.contains(":") else { return NoteAnalysis() }
        let command = header.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
        let body = Array(lines.dropFirst())
        switch command {
        case "math": return NoteAnalysis(mode: .math)
        case "sum": return aggregate(body, average: false)
        case "avg", "average": return aggregate(body, average: true)
        case "count": return count(body)
        case "list": return NoteAnalysis(mode: .list)
        case "timer": return NoteAnalysis(mode: .timer, timerDuration: parseDuration(header))
        default: return NoteAnalysis()
        }
    }

    private static func aggregate(_ lines: [String], average: Bool) -> NoteAnalysis {
        let numbers = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.flatMap(numbers(in:))
        let total = numbers.reduce(0, +)
        let value = average && !numbers.isEmpty ? total / Double(numbers.count) : total
        let mode: NoteMode = average ? .average : .sum
        return NoteAnalysis(mode: mode, results: [NoteResult(label: average ? "Average · \(numbers.count) values" : "Sum · \(numbers.count) values", value: format(value))])
    }

    private static func count(_ lines: [String]) -> NoteAnalysis {
        let active = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let joined = active.joined(separator: "\n")
        return NoteAnalysis(mode: .count, results: [
            NoteResult(label: "Lines", value: "\(active.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)"),
            NoteResult(label: "Words", value: "\(joined.split { $0.isWhitespace }.count)"),
            NoteResult(label: "Characters", value: "\(joined.count)")
        ])
    }

    private static func parseDuration(_ header: String) -> TimeInterval? {
        guard let colon = header.firstIndex(of: ":") else { return nil }
        let raw = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        if let value = Double(raw.dropLast()), let suffix = raw.last {
            if suffix == "h" { return value * 3600 }
            if suffix == "m" { return value * 60 }
            if suffix == "s" { return value }
        }
        return Double(raw).map { $0 * 60 }
    }

    private static func evaluate(_ source: String, variables: [String: Double]) -> Double? {
        var expression = localizedNumbers(in: source.lowercased())
        for (name, value) in variables.sorted(by: { $0.key.count > $1.key.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: name.lowercased())
            let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            expression = expression.replacingOccurrences(of: pattern, with: "(\(value))", options: .regularExpression)
        }
        expression = expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: " x ", with: " * ")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "**", with: "^")
        if let values = percentOperands(in: expression, pattern: #"^\s*([0-9.]+)\s*%\s+of\s+([0-9.]+)\s*$"#) {
            return values.0 / 100 * values.1
        }
        expression = expression.replacingOccurrences(
            of: #"^(.+?)\s*([+-])\s*([0-9.]+)\s*%\s*$"#,
            with: "($1)*(1$2($3/100))",
            options: .regularExpression
        )
        expression = expression.replacingOccurrences(of: #"(\d+(?:\.\d+)?)\s*%"#, with: "($1/100)", options: .regularExpression)
        expression = expression.replacingOccurrences(of: #"[^0-9+\-*/().^\s]"#, with: "", options: .regularExpression)
        expression = powers(in: expression)
        guard !expression.isEmpty,
              expression.range(of: #"^[0-9+\-*/().\s]+$"#, options: .regularExpression) != nil else { return nil }
        var parser = ArithmeticParser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return value
    }

    private static func localizedNumbers(in source: String) -> String {
        var output = source
        if output.contains(",") {
            if output.contains(".") {
                output = output.replacingOccurrences(of: #"(?<=\d)\.(?=\d{3}(?:\D|$))"#, with: "", options: .regularExpression)
            }
            output = output.replacingOccurrences(of: ",", with: ".")
        }
        return output
    }

    private static func variableAssignment(in expression: String) -> (name: String, expression: String)? {
        guard let colon = expression.firstIndex(of: ":") else { return nil }
        let name = String(expression[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(expression[expression.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty else { return nil }
        return (name, value)
    }

    private static func percentOperands(in source: String, pattern: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        let numericGroups = (1..<match.numberOfRanges).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: source) else { return nil }
            return Double(source[range])
        }
        guard numericGroups.count >= 2 else { return nil }
        return (numericGroups[0], numericGroups[1])
    }

    private static func powers(in source: String) -> String {
        var output = source
        let pattern = #"(-?\d+(?:\.\d+)?)\s*\^\s*(-?\d+(?:\.\d+)?)"#
        while let range = output.range(of: pattern, options: .regularExpression) {
            let parts = output[range].split(separator: "^")
            guard parts.count == 2,
                  let base = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let exponent = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { break }
            output.replaceSubrange(range, with: String(pow(base, exponent)))
        }
        return output
    }

    private struct Converted { let value: Double; let text: String }

    private static func conversion(_ source: String) -> Converted? {
        let pattern = #"(-?\d+(?:[.,]\d+)?)\s*([a-zA-Z°\"']+)\s+to\s+([a-zA-Z°\"']+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let valueRange = Range(match.range(at: 1), in: source),
              let fromRange = Range(match.range(at: 2), in: source),
              let toRange = Range(match.range(at: 3), in: source),
              let value = Double(source[valueRange].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let from = unit(String(source[fromRange])), to = unit(String(source[toRange]))
        guard let result = UnitConverter.convert(value, from: from, to: to) else { return nil }
        return Converted(value: result, text: "\(format(result)) \(to)")
    }

    private static func unit(_ raw: String) -> String {
        let value = raw.lowercased()
        let aliases = ["meter":"m", "meters":"m", "metre":"m", "centimeter":"cm", "centimeters":"cm", "kilometer":"km", "kilometers":"km", "inch":"in", "inches":"in", "\"":"in", "foot":"ft", "feet":"ft", "'":"ft", "mile":"mi", "miles":"mi", "pound":"lb", "pounds":"lb", "lbs":"lb", "kilogram":"kg", "kilograms":"kg", "grams":"g", "celsius":"c", "°c":"c", "fahrenheit":"f", "°f":"f", "kelvin":"k"]
        return aliases[value] ?? value
    }

    private static func numbers(in line: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"-?\d+(?:[.,]\d+)?"#) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap {
            Range($0.range, in: line).flatMap { Double(line[$0].replacingOccurrences(of: ",", with: ".")) }
        }
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct ArithmeticParser {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) { characters = Array(source.filter { !$0.isWhitespace }) }

    mutating func parse() -> Double? {
        guard let value = expression(), index == characters.count else { return nil }
        return value
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            index += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            index += 1
            guard let rhs = factor(), op != "/" || rhs != 0 else { return nil }
            value = op == "*" ? value * rhs : value / rhs
        }
        return value
    }

    private mutating func factor() -> Double? {
        if peek() == "+" { index += 1; return factor() }
        if peek() == "-" { index += 1; return factor().map(-) }
        if peek() == "(" {
            index += 1
            guard let value = expression(), peek() == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        var dots = 0
        while let character = peek(), character.isNumber || character == "." {
            if character == "." { dots += 1 }
            guard dots <= 1 else { return nil }
            index += 1
        }
        guard index > start else { return nil }
        return Double(String(characters[start..<index]))
    }

    private func peek() -> Character? { index < characters.count ? characters[index] : nil }
}

private enum UnitConverter {
    static let distance = ["mm": 0.001, "cm": 0.01, "m": 1.0, "km": 1000, "in": 0.0254, "ft": 0.3048, "yd": 0.9144, "mi": 1609.344]
    static let mass = ["mg": 0.000001, "g": 0.001, "kg": 1.0, "oz": 0.028349523, "lb": 0.45359237]
    static let volume = ["ml": 0.001, "l": 1.0, "tsp": 0.00492892, "tbsp": 0.0147868, "cup": 0.236588, "pt": 0.473176, "qt": 0.946353, "gal": 3.78541]

    static func convert(_ value: Double, from: String, to: String) -> Double? {
        for group in [distance, mass, volume] {
            if let source = group[from], let target = group[to] { return value * source / target }
        }
        if ["c", "f", "k"].contains(from), ["c", "f", "k"].contains(to) {
            let celsius = from == "c" ? value : (from == "f" ? (value - 32) * 5 / 9 : value - 273.15)
            return to == "c" ? celsius : (to == "f" ? celsius * 9 / 5 + 32 : celsius + 273.15)
        }
        return nil
    }
}
