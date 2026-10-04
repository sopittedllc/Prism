import Foundation
import Darwin

enum BoundedCommandError: Error, Equatable { case invalidInput, launchFailed, io, timeout, outputTooLarge, nonzeroExit, cleanupFailed, diagnosticOutput }

/// Internal synchronous helper for fixed read-only system commands, never audio/UI callbacks.
/// Owns and reaps its child PID; no shell, inherited input, or unbounded wait.
enum BoundedCommand {
    static func read(_ executable: String, arguments: [String], limit: Int, seconds: Double = 5, rejectDiagnostics: Bool = false) throws -> Data {
        try Task.checkCancellation()
        guard limit > 0, seconds.isFinite, seconds > 0,
              !([executable] + arguments).contains(where: { $0.utf8.contains(0) }) else { throw BoundedCommandError.invalidInput }
        let pipe = try CommandPipe()
        defer { pipe.closeAll() }
        let diagnostics = try rejectDiagnostics ? CommandPipe() : nil
        defer { diagnostics?.closeAll() }
        let input = pipe.input, output = pipe.output
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw BoundedCommandError.launchFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addclose(&actions, input) == 0,
              posix_spawn_file_actions_addclose(&actions, output) == 0 else { throw BoundedCommandError.launchFailed }
        if let diagnostics {
            guard posix_spawn_file_actions_adddup2(&actions, diagnostics.output, STDERR_FILENO) == 0,
                  posix_spawn_file_actions_addclose(&actions, diagnostics.input) == 0,
                  posix_spawn_file_actions_addclose(&actions, diagnostics.output) == 0 else { throw BoundedCommandError.launchFailed }
        } else {
            guard posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0 else { throw BoundedCommandError.launchFailed }
        }
        var argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let environmentStrings: [String] = ["LC_ALL=C", "LANG=C", "PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        var environment = environmentStrings.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; environment.forEach { free($0) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), environment.dropLast().allSatisfy({ $0 != nil }) else { throw BoundedCommandError.launchFailed }
        var child: pid_t = 0
        let launched = argv.withUnsafeMutableBufferPointer { args in
            environment.withUnsafeMutableBufferPointer { env in
                posix_spawn(&child, executable, &actions, nil, args.baseAddress!, env.baseAddress!)
            }
        }
        guard launched == 0 else { throw BoundedCommandError.launchFailed }
        pipe.closeOutput(); diagnostics?.closeOutput()
        var reaped = false
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            var data = Data(), buffer = [UInt8](repeating: 0, count: 8_192)
            var eof = false, diagnosticsEOF = diagnostics == nil
            var status: Int32 = 0
            while true {
                try Task.checkCancellation()
                if let diagnostics {
                    var byte: UInt8 = 0
                    let count = Darwin.read(diagnostics.input, &byte, 1)
                    if count > 0 { throw BoundedCommandError.diagnosticOutput }
                    if count == 0 { diagnosticsEOF = true }
                    if count < 0 && errno != EAGAIN && errno != EINTR { throw BoundedCommandError.io }
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw BoundedCommandError.timeout }
                if !reaped {
                    let result = waitpid(child, &status, WNOHANG)
                    if result == child { reaped = true }
                    else if result < 0 && errno != EINTR {
                        if errno == ECHILD { reaped = true }
                        throw BoundedCommandError.io
                    }
                }
                if !eof {
                    let count = Darwin.read(input, &buffer, buffer.count)
                    if count > 0 {
                        guard data.count + count <= limit else { throw BoundedCommandError.outputTooLarge }
                        data.append(contentsOf: buffer.prefix(count))
                        continue
                    } else if count == 0 { eof = true }
                    else if errno != EAGAIN && errno != EINTR { throw BoundedCommandError.io }
                }
                if eof && reaped && diagnosticsEOF {
                    guard status == 0 else { throw BoundedCommandError.nonzeroExit }
                    return data
                }
                if eof { usleep(5_000) }
                else {
                    var descriptor = pollfd(fd: input, events: Int16(POLLIN | POLLHUP), revents: 0)
                    if poll(&descriptor, 1, 20) < 0 && errno != EINTR { throw BoundedCommandError.io }
                }
            }
        } catch {
            if !reaped && !terminateAndReap(child) { throw BoundedCommandError.cleanupFailed }
            throw error
        }
    }

    private final class CommandPipe {
        let input: Int32
        let output: Int32
        private var outputOpen = true
        init() throws {
            var descriptors: [Int32] = [0, 0]
            guard Darwin.pipe(&descriptors) == 0 else { throw BoundedCommandError.io }
            input = fcntl(descriptors[0], F_DUPFD_CLOEXEC, 3)
            output = fcntl(descriptors[1], F_DUPFD_CLOEXEC, 3)
            close(descriptors[0]); close(descriptors[1])
            guard input >= 0, output >= 0 else {
                if input >= 0 { close(input) }; if output >= 0 { close(output) }
                throw BoundedCommandError.io
            }
            guard fcntl(input, F_SETFL, O_NONBLOCK) == 0 else {
                close(input); close(output); throw BoundedCommandError.io
            }
        }
        func closeOutput() { if outputOpen { close(output); outputOpen = false } }
        func closeAll() { close(input); closeOutput() }
    }

    private static func terminateAndReap(_ child: pid_t) -> Bool {
        // An unreaped child PID cannot be reused. Never signal after successful waitpid.
        for (signal, grace) in [(SIGTERM, 0.1), (SIGKILL, 0.5)] {
            kill(child, signal)
            let deadline = ProcessInfo.processInfo.systemUptime + grace
            repeat {
                var status: Int32 = 0
                let result = waitpid(child, &status, WNOHANG)
                if result == child || (result < 0 && errno == ECHILD) { return true }
                if result < 0 && errno != EINTR { return false }
                usleep(5_000)
            } while ProcessInfo.processInfo.systemUptime < deadline
        }
        return false
    }
}
