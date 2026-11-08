import Foundation

if CommandLine.arguments.contains("--selftest") {
    Selftest.run()
    exit(0)
}

UnscrewApp.main()
