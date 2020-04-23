import Foundation

class DataIter: IteratorProtocol {
    let data: Data
    var position: Data.Index

    init(_ data: Data) {
        self.data = data
        self.position = data.startIndex
    }

    func next() -> UInt8? {
        guard position != data.endIndex
        else { return nil }

        let res = data[position]
        position = data.index(after: position)
        return res
    }
}

class UTF8LineParser {
    private let lf = Unicode.Scalar(0x0A)
    private let cr = Unicode.Scalar(0x0D)
    private let replacement = String(Unicode.UTF8.decode(Unicode.UTF8.encodedReplacementCharacter))

    var utf8Parser = Unicode.UTF8.ForwardParser()
    var remainder: Data = Data()
    var currentString: String = ""
    var seenCr = false

    func append(_ body: Data) -> [String] {
        let data = remainder + body
        var dataIter = DataIter(data)
        var remainderPos = data.endIndex
        var lines: [String] = []

        Decode: while true {
            switch utf8Parser.parseScalar(from: &dataIter) {
            case .valid(let v):
                let scalar = Unicode.UTF8.decode(v)
                if seenCr {
                    lines.append(currentString)
                    currentString = ""
                    seenCr = false
                    if scalar == lf {
                        continue
                    }
                }
                if scalar == cr {
                    seenCr = true
                } else if scalar == lf {
                    lines.append(currentString)
                    currentString = ""
                } else {
                    currentString.append(String(scalar))
                }
            case .emptyInput:
                break Decode
            case .error(let len):
                if dataIter.position == data.endIndex {
                    // Error at end of block, carry over in case of split code point
                    remainderPos = data.index(data.endIndex, offsetBy: -len)
                } else {
                    // Invalid character, replace with replacement character
                    if seenCr {
                        lines.append(currentString)
                        currentString = ""
                        seenCr = false
                    }
                    currentString.append(replacement)
                }
            }
        }

        remainder = data.subdata(in: remainderPos..<data.endIndex)
        return lines
    }

    func closeAndReset() -> [String] {
        var lines: [String] = []

        if seenCr {
            lines.append(currentString)
            currentString = ""
        }

        if !remainder.isEmpty {
            currentString.append(replacement)
            remainder = Data()
        }

        if !currentString.isEmpty {
            lines.append(currentString)
        }

        currentString = ""
        seenCr = false

        return lines
    }
}
