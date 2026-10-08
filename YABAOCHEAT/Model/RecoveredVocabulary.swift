import Foundation

/// The application's wire and catalogue vocabulary, transcribed verbatim from
/// `__cstring`.
///
/// Everything in this file is **recovered**, not authored. The strings appear
/// as consecutive NUL-terminated literals between `0x1003B9950` and
/// `0x1003B9950 + 0x9C`, and again in the localisation `Dictionary`'s pointer
/// table at `0x1003ED000`. Grouping below follows address order, which is how
/// the linker emitted them and therefore how the original declarations were
/// most likely ordered.
///
/// The reason these strings are cross-referenced by *no* code is worth stating,
/// because it looks like a parser bug and is not: the localisation table is a
/// compiled-in Swift `Dictionary`. 205 pointers into `__cstring` sit in a
/// 32-byte-stride array — key, value, and two words of bucket bookkeeping — so
/// the strings are reached by hash lookup, never by direct address. A
/// literal-xref pass over the whole binary finds exactly one directly referenced
/// app string, `injected-runtime`.
public enum RecoveredVocabulary {

    // MARK: - game variants

    /// `0x1003B98D0`
    public static let gameFreeFire = "freeFire"
    /// `0x1003B98D9`
    public static let gameFreeFireMax = "freeFireMax"

    /// Bundle identifiers of the two supported targets.
    /// `0x1003BB160` and `0x1003BB180`.
    public enum BundleID {
        public static let freeFireMax = "com.dts.freefiremax"
        public static let freeFire = "com.dts.freefireth"
    }

    // MARK: - feature catalogue keys

    /// `0x1003B9950`–`0x1003B99D7`. The shape of a catalogue entry as the server
    /// sends it: an identifier, a grouping, presentation fields, and the
    /// behavioural switches that make a feature do anything.
    public enum CatalogEntry {
        public static let id = "id"
        public static let section = "section"
        public static let title = "title"
        public static let subtitle = "subtitle"
        public static let symbol = "symbol"
        public static let radius = "radius"
        public static let headshot = "headshot"
        public static let aimTarget = "aim_target"
        public static let exclusiveGroup = "exclusive_group"
        public static let fastReload = "fast_reload"
        public static let fastFire = "fast_fire"
        public static let colorControl = "color_control"
        public static let aimFovMode = "aim_fov_mode"
        public static let aimbotFov = "aimbot_fov"
    }

    /// `0x1003B99D8`–`0x1003B99F0`. Envelope of the catalogue itself.
    public enum Catalog {
        public static let version = "version"
        public static let sections = "sections"
        public static let options = "options"
        public static let selected = "selected"
    }

    // MARK: - runtime configuration keys

    /// `0x1003B99FA`–`0x1003BA050`. These are the keys of the configuration
    /// document written into the game container as `localConfig.json`, and read
    /// back by the injected runtime.
    ///
    /// Note `h0` and `a0` at `0x1003BA007` and `0x1003BA00A`. They are three
    /// characters and sit between `aimbotRadius` and `fastReloadPercent`, which
    /// is where a colour or an alpha component would sort. They are what the
    /// binary actually contains.
    public enum RuntimeConfig {
        public static let aimbotRadius = "aimbotRadius"
        public static let h0 = "h0"
        public static let a0 = "a0"
        public static let fastReloadPercent = "fastReloadPercent"
        public static let fastFireLevel = "fastFireLevel"
        public static let espColor = "espColor"
        public static let espThickness = "espThickness"
        public static let aimFovMode = "aimFovMode"
    }

    /// `0x1003BB1A0`. Prefix for a live command addressed to a single injected
    /// instance, followed by the device mask.
    public static let liveCommandPrefix = "ffxc.controls.v3."

    // MARK: - language identifiers

    /// `0x1003B9A51`–`0x1003B9A8A`. Seven languages, in emission order. The
    /// display names are at `0x1003BAAB0`–`0x1003BAAF0`.
    public enum LanguageID {
        public static let english = "english"
        public static let indonesian = "indonesian"
        public static let vietnamese = "vietnamese"
        public static let portuguese = "portuguese"
        public static let moroccan = "moroccan"
        public static let arabic = "arabic"
        public static let taiwanese = "taiwanese"

        public static let all = [
            english, indonesian, vietnamese, portuguese,
            moroccan, arabic, taiwanese,
        ]
    }

    /// `UserDefaults` key recording the chosen language. `0x1003BAA60`.
    public static let languageSelectedKey = "ffxc.langSelected"

    // MARK: - licensing response

    /// `0x1003BA70B`–`0x1003BA7DD`. Top-level keys of the signed envelope's
    /// decoded payload.
    public enum Response {
        public static let status = "status"
        public static let message = "message"
        public static let plan = "plan"
        public static let expiresAt = "expiresAt"
        public static let metadata = "metadata"
        public static let session = "session"
        public static let catalog = "catalog"
        public static let deployment = "deployment"
        public static let command = "command"
        public static let credential = "credential"
        public static let licenseLabel = "license_label"
    }

    /// `0x1003BA76E`–`0x1003BA7E6`. Session bookkeeping, including the two
    /// anti-replay fields: a monotonically increasing `sequence` and the `mac`
    /// the session is bound to.
    public enum Session {
        public static let ttl = "session_ttl"
        public static let expiresAt = "session_expiresAt"
        public static let artifact = "artifact"
        public static let state = "state"
        public static let aux = "aux"
        public static let mac = "mac"
        public static let unitMask = "unit_mask"
        public static let disableSequence = "disable_sequence"
        public static let disableMac = "disable_mac"
        public static let sequence = "sequence"
        public static let leaseSeconds = "lease_seconds"
    }

    // MARK: - server policy

    /// `0x1003BB6F0`–`0x1003BB850`. The bootstrap policy keys. These are read
    /// from the `credential bootstrap` response, not hardcoded, which is why the
    /// app ships safe fallbacks.
    public enum PolicyKey {
        public static let clientPublicKey = "client_public_key"
        public static let protocolVersion = "protocol_version"
        public static let secureTransportRequired = "secure_transport_required"
        public static let heartbeatSeconds = "heartbeat_seconds"
        public static let maxNetworkErrors = "max_network_errors"
        public static let receiptTimeoutSeconds = "receipt_timeout_seconds"
        public static let receiptRetentionSeconds = "receipt_retention_seconds"
        public static let patchOpenMonitorMs = "patch_open_monitor_ms"
        public static let fastReloadPercent = "fast_reload_percent"
        public static let devicePublicKey = "device_public_key"
    }

    /// `0x1003BB730`. Names the first leg of the exchange.
    public static let bootstrapOperation = "credential bootstrap"

    // MARK: - supported hardware

    /// `0x1003BA800`–`0x1003BA8A0`, newest first. Six models, all `Pro Max`.
    /// Anything else is rejected with `unsupported_hardware_detail`.
    public static let supportedDeviceModels = [
        "iPhone 16 Pro Max",
        "iPhone 15 Pro Max",
        "iPhone 14 Pro Max",
        "iPhone 13 Pro Max",
        "iPhone 12 Pro Max",
        "iPhone 11 Pro Max",
    ]

    // MARK: - container and sandbox probing

    /// Roots the container scan walks. `0x1003B98F0` and `0x1003B9920`.
    public static let containerRoots = [
        "/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Data/Application",
    ]

    /// `0x1003BAC70`. The same root with a trailing slash, as the scan uses it.
    public static let containerScanRoot = "/var/mobile/Containers/Data/Application/"

    /// `0x1003BABD0`. The canary written and read back to prove the process
    /// really has read/write in the game's container rather than merely
    /// believing it does.
    public static let accessProbe = ".ffxc_access_probe"

    /// Metadata plist the container scan parses, and the key it matches on.
    /// `0x1003BAD80` and `0x1003BADC0`.
    public enum ContainerMetadata {
        public static let plistName = ".com.apple.mobile_container_manager.metadata.plist"
        public static let identifierKey = "MCMMetadataIdentifier"
    }

    /// `0x1003BADE0`. Read to confirm a resolved container is the right app.
    public static let displayNameKey = "CFBundleDisplayName"

    // MARK: - stored payload

    /// `0x1003BB470` and `0x1003BB490`. The patch written into the game, and
    /// the configuration read by the injected runtime.
    public enum Payload {
        public static let patchResource = "Assembly-CSharp-patch.bytes"
        public static let patchInjectionName = "Assembly-CSharp-patch"
        public static let configFile = "localConfig.json"
    }

    /// `0x1003BB4D0`. The document written to prove the patch took effect.
    public static let patchProbeDocument = #"{"testCodePatch":true}"#

    // MARK: - logging

    /// `0x1003BA930`. Written to the app's Documents directory, capped at 500
    /// entries by the writer at `0x10014bac0`.
    public static let debugLogName = "ffxc_debug.log"
    public static let debugLogEntryLimit = 500

    // MARK: - branding

    /// `0x1003BA8C0`.
    public static let brandName = "FFXC / PRIVATE EDITION"
}
