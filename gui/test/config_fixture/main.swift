import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: config-fixture <config-path>\n", stderr)
    exit(64)
}

let config = AppConfig.load(fromPath: CommandLine.arguments[1])
for key in ["HOST", "USER", "GROUP", "SERVERCERT"] {
    print("\(key)=\(config[key] ?? "")")
}
