import Combine
import Foundation
import PromiseKit
import PMKFoundation
import Path

public typealias ProcessOutput = (status: Int32, out: String, err: String)

extension Process {
    @discardableResult
    static func sudo(password: String? = nil, _ executable: Path, workingDirectory: URL? = nil, _ arguments: String...) -> Promise<ProcessOutput> {
        var arguments = [executable.string] + arguments
        if password != nil {
            arguments.insert("-S", at: 0)
        } 
        return run(Path.root.usr.bin.sudo.url, workingDirectory: workingDirectory, input: password, arguments)
    }

    @discardableResult
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) -> Promise<ProcessOutput> {
        return run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    @discardableResult
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) -> Promise<ProcessOutput> {
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments
        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe.fileHandleForReading
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }
        return process.launch(.promise).map { std in 
            let output = String(data: std.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: std.err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, output, error)
        }
    }
    
    @discardableResult
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) -> AnyPublisher<ProcessOutput, Error> {
        return run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    @discardableResult
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) -> AnyPublisher<ProcessOutput, Error> {
        Deferred {
            Future<ProcessOutput, Error> { promise in
                let process = Process()
                process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
                process.executableURL = executable
                process.arguments = arguments
                
                let (stdout, stderr) = (Pipe(), Pipe())
                process.standardOutput = stdout
                process.standardError = stderr
                
                if let input = input {
                    let inputPipe = Pipe()
                    process.standardInput = inputPipe.fileHandleForReading
                    inputPipe.fileHandleForWriting.write(Data(input.utf8))
                    inputPipe.fileHandleForWriting.closeFile()
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()

                    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                    promise(.success((process.terminationStatus, output, error)))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .subscribe(on: DispatchQueue.global())
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}
