//
//  Install.swift
//  MineekStore
//
//  Created by Mineek on 02/07/2023.
//

import Foundation
import Darwin.POSIX

@discardableResult func spawn(command: String, args: [String], root: Bool) -> Int {
    var pipestdout: [Int32] = [0, 0]
    var pipestderr: [Int32] = [0, 0]

    let bufsiz = Int(BUFSIZ)

    pipe(&pipestdout)
    pipe(&pipestderr)

    guard fcntl(pipestdout[0], F_SETFL, O_NONBLOCK) != -1 else {
        NSLog("[MineekStoreInstaller] Could not open stdout")
        return -1
    }
    guard fcntl(pipestderr[0], F_SETFL, O_NONBLOCK) != -1 else {
        NSLog("[MineekStoreInstaller] Could not open stderr")
        return -1
    }

    let args: [String] = [String(command.split(separator: "/").last!)] + args
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    var fileActions: posix_spawn_file_actions_t?
    if root {
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addclose(&fileActions, pipestdout[0])
        posix_spawn_file_actions_addclose(&fileActions, pipestderr[0])
        posix_spawn_file_actions_adddup2(&fileActions, pipestdout[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, pipestderr[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, pipestdout[1])
        posix_spawn_file_actions_addclose(&fileActions, pipestderr[1])
    }
    
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    posix_spawnattr_set_persona_np(&attr, 99, UInt32(POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE));
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    let env = [ "PATH=/usr/local/sbin:/var/jb/usr/local/sbin:/usr/local/bin:/var/jb/usr/local/bin:/usr/sbin:/var/jb/usr/sbin:/usr/bin:/var/jb/usr/bin:/sbin:/var/jb/sbin:/bin:/var/jb/bin:/usr/bin/X11:/var/jb/usr/bin/X11:/usr/games:/var/jb/usr/games"  ]
    let proenv: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let pro? in proenv { free(pro) } }
    
    var pid: pid_t = 0
    let spawnStatus = posix_spawn(&pid, command, &fileActions, &attr, argv + [nil], proenv + [nil])
    if spawnStatus != 0 {
        NSLog("[MineekStoreInstaller] Spawn Status = \(spawnStatus)")
        return -1
    }

    close(pipestdout[1])
    close(pipestderr[1])

    var stdoutStr = ""
    var stderrStr = ""

    let mutex = DispatchSemaphore(value: 0)

    let readQueue = DispatchQueue(label: "com.mineek.MineekStoreInstaller.spawn",
                                  qos: .userInitiated,
                                  attributes: .concurrent,
                                  autoreleaseFrequency: .inherit,
                                  target: nil)

    let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: pipestdout[0], queue: readQueue)
    let stderrSource = DispatchSource.makeReadSource(fileDescriptor: pipestderr[0], queue: readQueue)

    stdoutSource.setCancelHandler {
        close(pipestdout[0])
        mutex.signal()
    }
    stderrSource.setCancelHandler {
        close(pipestderr[0])
        mutex.signal()
    }

    stdoutSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }

        let bytesRead = read(pipestdout[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }

            stdoutSource.cancel()
            return
        }

        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            stdoutStr += str
        }
    }
    stderrSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz)
        defer { buffer.deallocate() }

        let bytesRead = read(pipestderr[0], buffer, bufsiz)
        guard bytesRead > 0 else {
            if bytesRead == -1 && errno == EAGAIN {
                return
            }

            stderrSource.cancel()
            return
        }

        let array = Array(UnsafeBufferPointer(start: buffer, count: bytesRead)) + [UInt8(0)]
        array.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
            stderrStr += str
        }
    }

    stdoutSource.resume()
    stderrSource.resume()

    mutex.wait()
    mutex.wait()
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    NSLog("[MineekStoreInstaller] \(status) \(stdoutStr) \(stderrStr)")
    return Int(status)
}

func refreshAll() -> Bool {
    var helper = Bundle.main.path(forResource: "mineekstorehelper", ofType: "")
    var status = spawn(command: helper!, args: ["refresh"], root: true)
    status = spawn(command: helper!, args: ["respring"], root: true)
    return status == 0
}

func installLdid(completion: @escaping (Bool) -> Void) {
    var helper = Bundle.main.path(forResource: "mineekstorehelper", ofType: "")
    let ldidURL = URL(string: "https://github.com/opa334/ldid/releases/latest/download/ldid")!
    let ldid = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ldid")
    var session = URLSession(configuration: .default)
    var task = session.downloadTask(with: ldidURL) { (location, response, error) in
        if let error = error {
            NSLog("[MineekStoreInstaller] \(error)")
            return
        }
        if let location = location {
            do {
                if FileManager.default.fileExists(atPath: ldid.path) {
                    try FileManager.default.removeItem(at: ldid)
                }
                try FileManager.default.moveItem(at: location, to: ldid)
                let status = spawn(command: helper!, args: ["install-ldid", ldid.path, "1"], root: true)
                if status == 0 {
                    NSLog("[MineekStoreInstaller] Installed ldid")
                    completion(true)
                }
            } catch {
                NSLog("[MineekStoreInstaller] \(error)")
                completion(false)
            }
        }
    }
    task.resume()
}

func installApp(appRelease: Release, completion: @escaping (Bool) -> Void) {
    var helper = Bundle.main.path(forResource: "mineekstorehelper", ofType: "")
    var session = URLSession(configuration: .default)
    var task = URLSession.shared.downloadTask(with: URL(string: appRelease.URL!)!) { location, response, error in
        if let error = error {
            NSLog("[MineekStoreInstaller] \(error)")
            return
        }
        if let location = location {
            let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MineekStoreApp-\(UUID().uuidString).ipa")
            do {
                if FileManager.default.fileExists(atPath: temp.path) {
                    try FileManager.default.removeItem(at: temp)
                }
                try FileManager.default.moveItem(at: location, to: temp)
                let status = spawn(command: helper!, args: ["install", temp.path], root: true)
                if status == 0 {
                    NSLog("[MineekStoreInstaller] Installed \(appRelease.Version)")
                    completion(true)
                } else {
                    NSLog("[MineekStoreInstaller] Failed to install \(appRelease.Version)")
                    completion(false)
                }
            } catch let error {
                NSLog("[MineekStoreInstaller] \(error)")
            }
        }
    }
    task.resume()
}
