import Foundation

/// Installe la commande `notchkit` : un petit script shell qui parle au serveur local de Notchkit.
///
/// Le script (qui contient le jeton) est rangé dans Application Support, lisible par l'utilisateur seul ;
/// un lien symbolique le met dans un dossier du PATH (Homebrew, `/usr/local/bin` ou `~/.local/bin`).
enum ScriptCommandInstaller {
    static let path = "/notchkit/notify"
    static let commandName = "notchkit"

    static var scriptURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit", isDirectory: true)
            .appendingPathComponent(commandName)
    }

    /// Dossiers où poser le lien, dans l'ordre de préférence.
    static var linkDirectories: [URL] {
        [URL(fileURLWithPath: "/opt/homebrew/bin"),
         URL(fileURLWithPath: "/usr/local/bin"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)]
    }

    enum Status: Equatable {
        case notInstalled
        case installed(URL)
        /// Lien présent mais script d'une autre version (port, jeton ou commandes) : le réécrire.
        case outdated
    }

    static func status(port: UInt16, token: String) -> Status {
        guard let link = installedLink() else { return .notInstalled }
        let current = try? String(contentsOf: scriptURL, encoding: .utf8)
        return current == script(port: port, token: token) ? .installed(link) : .outdated
    }

    /// Lien déjà posé par Notchkit (il pointe vers notre script).
    static func installedLink() -> URL? {
        let fileManager = FileManager.default
        return linkDirectories.map { $0.appendingPathComponent(commandName) }.first { link in
            (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == scriptURL.path
        }
    }

    /// Écrit le script et pose le lien. Renvoie l'emplacement du lien.
    @discardableResult
    static func install(port: UInt16, token: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script(port: port, token: token).utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        if let link = installedLink() { return link }

        var lastError: Error?
        for directory in linkDirectories {
            let link = directory.appendingPathComponent(commandName)
            // Un fichier `notchkit` qui n'est pas à nous n'est jamais remplacé.
            if fileManager.fileExists(atPath: link.path) || (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
                continue
            }
            do {
                if directory.path.hasPrefix(fileManager.homeDirectoryForCurrentUser.path) {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                guard fileManager.isWritableFile(atPath: directory.path) else { continue }
                try fileManager.createSymbolicLink(at: link, withDestinationURL: scriptURL)
                return link
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileWriteNoPermission)
    }

    static func uninstall() {
        if let link = installedLink() { try? FileManager.default.removeItem(at: link) }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    // MARK: Script (pur, testé)

    static func script(port: UInt16, token: String) -> String {
        #"""
        #!/bin/sh
        # notchkit : affiche une notification ou une activité dans l'encoche de Notchkit.
        # Généré par Notchkit (connexion locale uniquement, protégée par un jeton). Sans Notchkit : rien ne s'affiche.

        URL='http://127.0.0.1:\#(port)\#(path)'
        TOKEN='\#(token)'

        usage() {
          cat <<'EOF'
        Usage:
          notchkit notify "Title" ["Message"] [--symbol name] [--color name]
          notchkit run [--awake] [--title "Title"] [--symbol name] [--] command [args...]
          notchkit awake [on|off|MINUTES]
          notchkit start ID "Title" [--symbol name] [--color name]
          notchkit progress ID PERCENT ["Title"]
          notchkit end ID [success|failure] ["Message"]

        Examples:
          notchkit run npm test
          notchkit notify "Deploy finished" "api is live" --symbol checkmark.seal --color green
          notchkit start export "Exporting video"; notchkit progress export 40; notchkit end export

        --symbol takes an SF Symbol name; --color: red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray.
        --awake keeps the Mac awake with the lid closed while the command runs; "notchkit awake" does it until you turn it off.
        EOF
          exit "${1:-0}"
        }

        # Envoie chaque argument « clé=valeur » à Notchkit, encodé par curl. Échec silencieux.
        post() {
          n=$#
          while [ "$n" -gt 0 ]; do
            set -- "$@" --data-urlencode "$1"
            shift
            n=$((n - 1))
          done
          /usr/bin/curl -s -m 2 -o /dev/null -H "X-Notchkit-Token: $TOKEN" "$@" "$URL" 2>/dev/null || true
        }

        command="$1"
        [ $# -gt 0 ] && shift
        title='' message='' symbol='' color='' awake=''

        case "$command" in
          notify)
            [ $# -gt 0 ] || usage 1
            while [ $# -gt 0 ]; do
              case "$1" in
                --symbol) symbol="$2"; shift 2 ;;
                --color) color="$2"; shift 2 ;;
                *) if [ -z "$title" ]; then title="$1"; else message="$1"; fi; shift ;;
              esac
            done
            post action=notify "title=$title" "message=$message" "symbol=$symbol" "color=$color"
            ;;
          run)
            while [ $# -gt 0 ]; do
              case "$1" in
                --title) title="$2"; shift 2 ;;
                --symbol) symbol="$2"; shift 2 ;;
                --color) color="$2"; shift 2 ;;
                --awake) awake=1; shift ;;
                --) shift; break ;;
                *) break ;;
              esac
            done
            [ $# -gt 0 ] || usage 1
            [ -n "$title" ] || title="$*"
            id="run-$$"
            post action=start "id=$id" "title=$title" "symbol=${symbol:-terminal}" "color=$color" "awake=$awake"
            "$@"
            code=$?
            if [ "$code" -eq 0 ]; then
              post action=end "id=$id" status=success
            else
              post action=end "id=$id" status=failure "message=exit $code"
            fi
            exit "$code"
            ;;
          start)
            [ $# -ge 1 ] || usage 1
            id="$1"; shift
            while [ $# -gt 0 ]; do
              case "$1" in
                --symbol) symbol="$2"; shift 2 ;;
                --color) color="$2"; shift 2 ;;
                *) title="$1"; shift ;;
              esac
            done
            post action=start "id=$id" "title=$title" "symbol=$symbol" "color=$color"
            ;;
          progress)
            [ $# -ge 2 ] || usage 1
            post action=progress "id=$1" "progress=$2" "title=${3:-}"
            ;;
          end)
            [ $# -ge 1 ] || usage 1
            post action=end "id=$1" "status=${2:-success}" "message=${3:-}"
            ;;
          awake)
            post action=awake "value=${1:-on}"
            ;;
          -h|--help|help|'')
            usage 0
            ;;
          *)
            usage 1
            ;;
        esac

        """#
    }
}
