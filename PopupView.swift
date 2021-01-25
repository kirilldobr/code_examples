
import EasyPeasy
import RxCocoa
import RxSwift
import SwiftEntryKit
import UIKit

enum PopupState: Equatable {
    case noBluetooth
    case noWifi
    case searchingForClouds(found: Int)
    case enterWiFiName
    case enterPassword(ssid: String)
    case connecting(connected: Int, available: Int)
    case enableBluetoothPrompt
    case enableLocationPrompt
    case bluetoothDenied
    case wifiDenied
    case cloudsCouldNotConnectToWifi(count: Int)
    case success(count: Int)
}

class PopupViewModel: ViewModel {
    // controls everything here
    let state = BehaviorRelay<PopupState>(value: .searchingForClouds(found: 0))
    
    lazy var title: Observable<String> = state.map {
        switch $0 {
        case .noBluetooth: return Strings.enableBluetooth.title
        case let .connecting(connected, available): return Strings.connecting.title
        case let .success(count): return Strings.ready
        case .enterWiFiName: return Strings.enterWiFiName.title
        case let .enterPassword(ssid): return Strings.enterPassword.title(ssid: ssid)
        case let .searchingForClouds(found): return found == 0 ? Strings.searchingForClouds.title : Strings.foundClouds.title
        case .noWifi: return Strings.connectToWifi.title
        case .bluetoothDenied: return Strings.bleutoothDenied.title
        case .wifiDenied: return Strings.wifiDenied.title
        case .enableBluetoothPrompt: return Strings.enableBluetoothPrompt.title
        case .enableLocationPrompt: return Strings.enableLocationPrompt.title
        case .cloudsCouldNotConnectToWifi: return Strings.cloudsCouldNotConnectToWifi.title
        }
    }
    
    lazy var subtitle: Observable<String?> = state.map {
        switch $0 {
        case .noBluetooth: return Strings.enableBluetooth.subtitle
        case .connecting, .success: return Strings.connecting.subtitle
        case .enterWiFiName: return nil
        case .enterPassword: return Strings.enterPassword.subtitle
        case let .searchingForClouds(found): return found == 0 ? Strings.searchingForClouds.subtitle : Strings.foundClouds.subtitle
        case .noWifi: return Strings.connectToWifi.subtitle
        case .bluetoothDenied: return Strings.bleutoothDenied.subtitle
        case .wifiDenied: return Strings.wifiDenied.subtitle
        case .enableBluetoothPrompt: return Strings.enableBluetoothPrompt.subtitle
        case .enableLocationPrompt: return Strings.enableLocationPrompt.subtitle
        case let .cloudsCouldNotConnectToWifi(count): return Strings.cloudsCouldNotConnectToWifi.subtitle(failedCount: count)
        }
    }
    
    lazy var confirmButtonTitle: Observable<String?> = state.map {
        switch $0 {
        case .noBluetooth: return Strings.enableBluetooth.buttonTitle
        case .connecting, .success: return Strings.connecting.buttonTitle
        case .enterWiFiName: return Strings.enterWiFiName.buttonTitle
        case .enterPassword: return Strings.enterPassword.buttonTitle
        case let .searchingForClouds(found): return found == 0 ? Strings.searchingForClouds.buttonTitle : Strings.foundClouds.buttonTitle
        case .noWifi: return Strings.connectToWifi.buttonTitle
        case .bluetoothDenied: return Strings.bleutoothDenied.buttonTitle
        case .wifiDenied: return Strings.wifiDenied.buttonTitle
        case .enableBluetoothPrompt: return Strings.enableBluetoothPrompt.buttonTitle
        case .enableLocationPrompt: return Strings.enableLocationPrompt.buttonTitle
        case .cloudsCouldNotConnectToWifi: return Strings.cloudsCouldNotConnectToWifi.buttonTitle
        }
    }
    
    lazy var isLoading: Observable<Bool> = state.map {
        switch $0 {
        case let .searchingForClouds(count) where count == 0: return true
        case .noBluetooth, .noWifi: return true
        case .connecting: return true
        default: return false
        }
    }
    
    lazy var subtitleIsHidden: Observable<Bool> = subtitle.map { $0?.isEmpty ?? true }
    lazy var confirmButtonIsHidden: Observable<Bool> = confirmButtonTitle.map { $0?.isEmpty ?? true }
    
    lazy var cloudIsHidden: Observable<Bool> = state.map {
        switch $0 {
        case .searchingForClouds, .connecting, .success: return false
        default: return true
        }
    }
    
    lazy var textFieldIsHidden: Observable<Bool> = state.map {
        switch $0 {
        case .enterPassword, .enterWiFiName: return false
        default: return true
        }
    }
    
    lazy var textInsideCloud: Observable<String?> = state.map {
        switch $0 {
        case let .searchingForClouds(foundCount):
            guard foundCount > 0 else { return nil }
            return "x\(foundCount)"
        case let .connecting(connected, available):
            return "\(connected)/\(available)"
        case let .success(count):
            return "x\(count)"
        default:
            return nil
        }
    }
    
    lazy var isGlowing: Observable<Bool> = state.map {
        switch $0 {
        case let .searchingForClouds(foundCount): return foundCount > 0
        default: return true
        }
    }
    
    lazy var cloudViewModel = CloudViewModel(textInside: textInsideCloud, isGlowing: isGlowing)
    
    lazy var textFieldPlaceholder: Observable<String> = state.map {
        switch $0 {
        case .enterPassword: return Strings.pass
        case .enterWiFiName: return Strings.WiFiName
        default: return ""
        }
    }
    
    lazy var textFieldIsSecure: Observable<Bool> = state.map {
        switch $0 {
        case .enterPassword: return true
        case .enterWiFiName: return false
        default: return false
        }
    }
    
    lazy var passFieldViewModel = FieldViewModel(placeholder: textFieldPlaceholder, isSecure: textFieldIsSecure)
    
    let closeDidTap = PublishRelay<Void>()
    
    lazy var confirmButtonViewModel = ButtonViewModel(title: confirmButtonTitle,
                                                      titleColor: Colors.purple)
    
    var confirmButtonTapped: Observable<PopupState> {
        return confirmButtonViewModel.didTap.map { [weak self] _ in self?.state.value }.filterNil()
    }
    
    override init() {
        super.init()
        
        state
            .filter {
                if case .success = $0 { return true }
                return false
            }
            .bind { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Hide popup in 1.5 sec after all clouds connected.
                    CloudPairingService.shared.hidePopupAndRestart()
                }
            }
            .disposed(by: aliveDisposeBag)
        
        state
            .map { "\($0)" }
            .distinctUntilChanged()
            .bind {
                Analytics.popup_state($0)
            }
            .disposed(by: aliveDisposeBag)
    }
}

class PopupView: View<PopupViewModel> {
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let confirmButton = Button()
    let spinner = UIActivityIndicatorView()
    let closeButton = CrossButton()
    let passField = SeparatorField.with(.orange)
    let cloudView = CloudView()
    
    override func setModel(_ viewModel: PopupViewModel) {
        super.setModel(viewModel)
        
        viewModel.title --> titleLabel.rx.text >>> disposeBag
        viewModel.subtitle --> subtitleLabel.rx.text >>> disposeBag
        viewModel.confirmButtonIsHidden --> confirmButton.rx.isHidden >>> disposeBag
        viewModel.subtitleIsHidden --> subtitleLabel.rx.isHidden >>> disposeBag
        viewModel.textFieldIsHidden --> passField.rx.isHidden >>> disposeBag
        viewModel.cloudIsHidden --> cloudView.rx.isHidden >>> disposeBag
        viewModel.isLoading --> spinner.rx.isAnimating >>> disposeBag
        viewModel.isLoading --> confirmButton.rx.isHidden >>> disposeBag
        
        closeButton.rx.tap >>> viewModel.closeDidTap >>> disposeBag
        
        viewModel.textFieldIsHidden --> { hidden in
            if hidden { self.passField.endEditing(true) }
        } >>> disposeBag
        
        confirmButton.setModel(viewModel.confirmButtonViewModel)
        passField.setModel(viewModel.passFieldViewModel)
        cloudView.setModel(viewModel.cloudViewModel)
    }
    
    override func didLoad() {
        super.didLoad()
        
        layer.cornerRadius = 26
        
        addSubview(titleLabel, layout: Top(38), Left(32), Right(32))
        addSubview(confirmButton, layout: Bottom(30), Height(24), Left(32), Right(32))
        addSubview(spinner, layout: CenterX().to(confirmButton), CenterY().to(confirmButton))
        addSubview(closeButton, layout: Right(17), Top(17))
        addSubview(passField, layout: Left(32), Right(32), CenterY())
        addSubview(cloudView, layout: Center(), Width(133), Height(73))
        addSubview(subtitleLabel, layout: Top(16).to(titleLabel), Left(32), Right(32), Bottom(16).to(confirmButton).with(.low))
        
        backgroundColor = Colors.darkest
        
        spinner.style = .whiteLarge
        spinner.hidesWhenStopped = true
        
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.textColor = Colors.Popup.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
        
        subtitleLabel.numberOfLines = 5
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.7
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = Colors.Popup.subtitle
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 250)
    }
}

extension PopupView {
    static var showAttributes: EKAttributes {
        var attributes = EKAttributes.bottomFloat
        attributes.displayDuration = .infinity
        attributes.hapticFeedbackType = .success
        attributes.entranceAnimation = .init(translate: .init(duration: 0.2))
        attributes.exitAnimation = .init(translate: .init(duration: 0.1))
        attributes.screenBackground = .color(color: EKColor(Colors.dark.withAlphaComponent(0.8)))
        attributes.entryInteraction = .absorbTouches
        attributes.screenInteraction = .dismiss
        let widthConstraint = EKAttributes.PositionConstraints.Edge.ratio(value: 0.9)
        let heightConstraint = EKAttributes.PositionConstraints.Edge.intrinsic
        attributes.positionConstraints.size = .init(width: widthConstraint, height: heightConstraint)
        attributes.positionConstraints.verticalOffset = 26
        let offset = EKAttributes.PositionConstraints.KeyboardRelation.Offset(bottom: 15, screenEdgeResistance: 20)
        let keyboardRelation = EKAttributes.PositionConstraints.KeyboardRelation.bind(offset: offset)
        attributes.positionConstraints.keyboardRelation = keyboardRelation
        attributes.lifecycleEvents.didDisappear = {
            WiFiResolver.shared.checkWifiAvailabilitySignal.accept(())
        }
        
        return attributes
    }
}
