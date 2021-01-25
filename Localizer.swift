
import Foundation
import RxCocoa
import RxSwift

public protocol LocalizerType {
    /// The code of the current language (e.g. en, fr, es)
    var currentLanguageCode: Observable<String?> { get }
    
    /// The code of the current language (e.g. en, fr, es). Use this value for getting the language in a synchronous code.
    var currentLanguageCodeValue: String? { get }
    
    /// Trigger which is used for changing current language. Element is a language code (e.g. en, fr, es).
    var changeLanguage: BehaviorRelay<String?> { get }
    
    /// Trigger which is used for changing localizer configuration.
    var changeConfiguration: BehaviorRelay<LocalizerConfig> { get }
    
    /// Localizes the string, using Rx
    ///
    /// - Parameter string: String which will be localized
    /// - Returns: Localized string
    func localized(_ string: String, value: String) -> Observable<String>
    
    func localizedWithFormat(_ string: String, value: String, _ arguments: [Observable<String>]) -> Observable<String>
}

class Localizer: LocalizerType {
    static let shared = Localizer()
    
    let changeLanguage = BehaviorRelay<String?>(value: nil)
    let changeConfiguration = BehaviorRelay<LocalizerConfig>(value: LocalizerConfig())
    let currentLanguageCode: Observable<String?>
    private(set) var currentLanguageCodeValue: String?
    
    let localizationBundle = BehaviorRelay<Bundle>(value: .main)
    private let configuration = BehaviorRelay<LocalizerConfig>(value: LocalizerConfig())
    private let disposeBag = DisposeBag()
    #if TESTBUILD
        private static let _availableLanguages = ["en", "ar", "cs", "da", "de", "el", "es", "fa", "fr", "hi", "hu", "id", "it", "ja", "ko", "nl", "pl", "pt", "ro", "ru", "sv", "th", "tr", "ur", "vi", "zh"]
    #else
        private static let _availableLanguages = ["en"]
    #endif
    
    static var availableLanguages: [String] {
        // TODO: use `rx_config` and make it observable.
        return (AppConfiguration.shared.config?.business.user.interfaceLanguages ?? [])
            .filter { _availableLanguages.contains($0) }
    }
    
    func localizedWithFormat(_ string: String, value: String, _ arguments: [Observable<String>]) -> Observable<String> {
        return Observable.combineLatest(Observable.combineLatest(arguments), localizationBundle.asObservable())
            .withLatestFrom(configuration, resultSelector: { ($0, $1) })
            .map { (argumentsAndBundle, config) -> String in
                let (stringArgs, bundle) = argumentsAndBundle
                let localizedString = bundle.localizedString(forKey: string, value: value, table: config.tableName)
                return String(format: localizedString, arguments: stringArgs)
            }
    }
    
    func localized(_ string: String, value: String) -> Observable<String> {
        return localizationBundle
            .withLatestFrom(configuration) {
                $0.localizedString(forKey: string, value: value, table: $1.tableName)
            }
    }
    
    private init() {
        let changeLang = changeLanguage
            .asObservable()
            .filterNil()
            .distinctUntilChanged()
        
        let config = configuration.asObservable()
        
        currentLanguageCode = Observable.combineLatest(changeLang, config) { [localizationBundle] languageCode, configuration in
            let isValidLanguage = Self.availableLanguages.map { $0.lowercased() }.contains(languageCode.lowercased())
            let languageCode = isValidLanguage ? languageCode : "en"
            
            configuration.defaults.currentLanguage = languageCode
            let bundle = configuration.bundle.path(forResource: languageCode, ofType: "lproj").flatMap(Bundle.init)
            localizationBundle.acceptValue = bundle ?? localizationBundle.value
            return languageCode
        }
        .share(replay: 1)
        
        currentLanguageCode.bind(onNext: { [weak self] in
            self?.currentLanguageCodeValue = $0
        }).disposed(by: disposeBag)
        
        if let currentLanguage = configuration.value.defaults.currentLanguage {
            changeLanguage.acceptValue = currentLanguage
        } else {
            let preferredLocalization = configuration.value.bundle.preferredLocalizations.first { $0.count < 3 }
            changeLanguage.acceptValue = preferredLocalization ?? Locale.current.languageCode ?? "en"
        }
        
        changeConfiguration.asObservable()
            .bind(to: configuration)
            .disposed(by: disposeBag)
    }
}

extension UserDefaults {
    var currentLanguage: String? {
        get { return string(forKey: #function) }
        set { set(newValue, forKey: #function) }
    }
}

public struct LocalizerConfig {
    let defaults: UserDefaults
    let tableName: String
    let bundle: Bundle
    
    /// Creates an config for the Localizer
    ///
    /// - Parameters:
    ///   - defaults: User defaults in which Localizer will store current localization. Default value is UserDefaults.standard.
    ///   - bundle: App bundle. Default value is Bundle.main.
    ///   - tableName: The receiver’s string table to search. Default value is Localizable.
    public init(defaults: UserDefaults = .standard, bundle: Bundle = .main, tableName: String = "Localizable") {
        self.defaults = defaults
        self.bundle = bundle
        self.tableName = tableName
    }
}
