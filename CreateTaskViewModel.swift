

import AppsFlyerLib
import RxCocoa
import RxSwift
import UIKit

class CreateTaskForm {
    lazy var titleValidator: RegexValidator? = {
        if let regex = RegexFactory.taskTitleRegex {
            return RegexValidator(regex: regex)
        }
        return nil
    }()
    
    lazy var descriptionValidator: RegexValidator? = {
        if let regex = RegexFactory.taskDescriptionRegex {
            return RegexValidator(regex: regex)
        }
        return nil
    }()
    
    let challengeReward = BehaviorRelay<Decimal>(value: 0)
    let myDonation = BehaviorRelay<Decimal>(value: 0)
    
    let title = BehaviorRelay<String?>(value: nil)
    let description = BehaviorRelay<String?>(value: nil)
    
    var trimmedTitle: String? {
        return title.value?.trimmingCharacters(in: .whitespaces)
    }
    
    var trimmedDescription: String? {
        return description.value?.trimmingCharacters(in: .whitespaces)
    }
}

class CreateTaskViewModel: ViewModel, ViewModelDataSource {
    let elements: BehaviorRelay<[ViewModel]> = BehaviorRelay(value: [])
    
    let cancelPressed = BehaviorRelay(value: ())
    
    let didSelectItemAtIndexPath = BehaviorRelay<IndexPath?>(value: nil)
    
    let form = CreateTaskForm()
    
    lazy var buttonEnabled = BehaviorRelay<Bool>(value: true)
    
    lazy var buttonViewModel = BaseButtonViewModel(title: String.Localized.Buttons.create.optional, enabled: buttonEnabled.asObservable())
    
    let isEnteringAmount = BehaviorRelay(value: false)
    
    let isStreamer: Bool
    
    let context: EventDispatcherModuleContext
    
    let taskCreated: BehaviorRelay<String?>
    
    lazy var infoAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
        .map { (colors, fonts) -> [NSAttributedString.Key: Any] in
            [.textColor(colors.smoke),
             .font(fonts.headline.h7.medium),
             .custom(NSAttributedString.Key.paragraphStyle, NSMutableParagraphStyle(lineSpacing: 0))].pairs
        }
    
    lazy var errorAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
        .map { (colors, fonts) -> [NSAttributedString.Key: Any] in
            [.textColor(colors.others.infoMessageText),
             .font(fonts.headline.h7.medium),
             .custom(NSAttributedString.Key.paragraphStyle, NSMutableParagraphStyle(lineSpacing: 0))].pairs
        }
    
    lazy var infoCardTextAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
        .map { (colors, fonts) -> [NSAttributedString.Key: Any] in
            [.font: fonts.headline.h8.medium,
             .foregroundColor: colors.fogWhite,
             .paragraphStyle: NSMutableParagraphStyle(lineSpacing: 4)]
        }
    
    lazy var infoCardPercenAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
        .map { (colors, fonts) -> [NSAttributedString.Key: Any] in
            [.font: fonts.headline.h8.semiBold,
             .foregroundColor: colors.fogWhite,
             .paragraphStyle: NSMutableParagraphStyle(lineSpacing: 4)]
        }
    
    let descriptionViewModel = TextViewModel(maxCount: .just(150), placeholderTitle: String.Localized.Challenges.Create.Description.placeholder.optional, newLineAllowed: .just(false))
    
    let titleFieldViewModel: TextFieldViewModel
    
    let challengeRewardInputViewModel: MenuMoneyInputViewModel
    let myDonationInputViewModel: MenuMoneyInputViewModel
    
    let scrollToTop = BehaviorRelay<Void?>(value: nil)
    
    init(context: EventDispatcherModuleContext, broadcast: GRBroadcast, taskCreated: BehaviorRelay<String?>, isStreamer: Bool) {
        self.context = context
        self.taskCreated = taskCreated
        self.isStreamer = isStreamer
        
        titleFieldViewModel = TextFieldViewModel(maxCount: .just(52),
                                                 placeholderTitle: String.Localized.Challenges.Create.Challenge.placeholder.optional)
        
        myDonationInputViewModel = MenuMoneyInputViewModel(context: context, title: String.Localized.Challenges.Create.Reward.myDonation, separatorAlwaysVisible: .just(false))
        challengeRewardInputViewModel = MenuMoneyInputViewModel(context: context, title: String.Localized.Challenges.Create.Reward.challengeReward)
        
        super.init()
        
        let emptySeparator = MenuSeparatorViewModel(.empty)
        
        let titleHeaderViewModel = MenuTitleViewModel(title: String.Localized.Challenges.Create.Challenge.title.uppercased)
        let descriptionHeaderViewModel = MenuTitleViewModel(title: String.Localized.Challenges.Create.Description.title.uppercased)
        
        titleFieldViewModel.text.asObservable()
            .onMainThread
            .bind(to: form.title)
            .disposed(by: aliveDisposeBag)
        
        titleFieldViewModel.text
            .validate(with: form.titleValidator)
            .bind(to: titleFieldViewModel.inputState)
            .disposed(by: aliveDisposeBag)
        
        descriptionViewModel.text.asObservable()
            .bind(to: form.description)
            .disposed(by: aliveDisposeBag)
        
        descriptionViewModel.text.asObservable()
            .validate(with: form.descriptionValidator)
            .bind(to: descriptionViewModel.inputState)
            .disposed(by: aliveDisposeBag)
        
        let balance = GRMe.shared.user.filterNil().flatMapLatest { $0.balance.asObservable() }
        
        let fee = broadcast.isMine ? broadcast.taskCreateCommission : broadcast.createByPerformerCommission
        
        let feeWillBeCharged = String.Localized.Challenges.Create.Terms.feeWillBeCharged(amount: fee.amountString.attributed(infoAttributes),
                                                                                         currency: fee.currencySymbol.attributed(infoAttributes),
                                                                                         baseAttributes: infoAttributes)
        
        let rewardTitleTableViewModel = MenuTitleViewModel(title: String.Localized.Challenges.Create.Reward.title.uppercased)
        
        AppConfiguration.shared.rx.config
            .map { Decimal($0.business.task.defaultReward) }
            .take(1)
            .bind(to: challengeRewardInputViewModel.amount)
            .disposed(by: disposeBag)
        
        Observable.combineLatest(AppConfiguration.shared.rx.config, challengeRewardInputViewModel.amount)
            .map { config, reward in
                config.business.task.ownDonationOnCreate.commission(for: reward)
            }
            .take(1)
            .bind(to: myDonationInputViewModel.amount)
            .disposed(by: disposeBag)
        
        challengeRewardInputViewModel.amount
            .bind(to: form.challengeReward)
            .disposed(by: disposeBag)
        
        let minReward = broadcast.taskMinimumReward
        let maxReward = broadcast.taskMaximumReward
        
        let rewardTooSmall = String.Localized.Challenges.Create.Error.rewardTooSmall(amount: minReward.amountString.attributed(errorAttributes),
                                                                                     currency: minReward.currencySymbol.attributed(errorAttributes))
        
        let rewardTooBig = String.Localized.Challenges.Create.Error.rewardTooBig(amount: maxReward.amountString.attributed(errorAttributes),
                                                                                 currency: maxReward.currencySymbol.attributed(errorAttributes))
        
        Observable.combineLatest(form.challengeReward.asObservable(),
                                 form.myDonation.asObservable(),
                                 AppConfiguration.shared.rx.config,
                                 balance)
            .map { (challengeReward, _, config, _) -> InputState in
                let conf = config.business.task
                if challengeReward < Decimal(conf.minimumReward) {
                    return .error(rewardTooSmall.optional)
                } else if challengeReward > Decimal(conf.maximumReward) {
                    return .error(rewardTooBig.optional)
                }
                
                return .ok
            }
            .bind(to: challengeRewardInputViewModel.inputState)
            .disposed(by: disposeBag)
        
        let formIsValid = Observable.combineLatest(titleFieldViewModel.inputState,
                                                   descriptionViewModel.inputState,
                                                   challengeRewardInputViewModel.inputState,
                                                   myDonationInputViewModel.inputState)
            .map { title, description, challengeReward, myDonation -> Bool in
                title.isOk && description.isOk && challengeReward.isOk && myDonation.isOk
            }
        
        let formIsEmpty = Observable.combineLatest(titleFieldViewModel.inputState,
                                                   descriptionViewModel.inputState)
            .map { title, description -> Bool in
                title.isEmpty && description.isEmpty
            }
        
        cancelPressed
            .skip(1)
            .withLatestFrom(formIsEmpty)
            .map { isEmpty -> DispatcherEventType in
                guard !isEmpty else {
                    return OnCloseCreateTaskEvent()
                }
                
                let closeAction = AlertViewController.ActionType.destructive(title: String.Localized.Buttons.yes, handler: {
                    context.dispatcher.dispatch(event: OnCloseCreateTaskEvent())
                })
                
                let title = String.Localized.Challenges.Create.CancelCreation.title
                let subtitle = String.Localized.Challenges.Create.CancelCreation.description
                let config = AlertConfig(type: .alert,
                                         headers: [.titleSubtitle(title: title, subtitle: subtitle)],
                                         actions: [.cancel(title: String.Localized.Buttons.no), closeAction])
                return AlertOpenEvent(config: config)
            }
            .bind(context.dispatcher)
            .disposed(by: disposeBag)
        
        buttonViewModel.tap
            .throttle(1.0, scheduler: MainScheduler.instance)
            .flatMapLatest { _ in formIsValid.take(1) }
            .onMainThread
            .do(onNext: { [weak self] _ in
                if self?.titleFieldViewModel.inputState.value == .empty {
                    self?.titleFieldViewModel.inputState.accept(.error(String.Localized.Validations.empty(value: String.Localized.Challenges.Create.Challenge.title.attributed).optional))
                }
                
                if self?.descriptionViewModel.inputState.value == .empty {
                    self?.descriptionViewModel.inputState.accept(.error(String.Localized.Validations.empty(value: String.Localized.Broadcast.Create.Options.Description.title.attributed).optional))
                }
                
                self?.titleFieldViewModel.animateRestrictionIfNeeded()
                self?.descriptionViewModel.animateRestrictionIfNeeded()
                self?.challengeRewardInputViewModel.animateRestrictionIfNeeded()
                self?.myDonationInputViewModel.animateRestrictionIfNeeded()
            })
            .bind { [weak self] valid in
                if valid {
                    self?.createTask(for: broadcast.id)
                } else {
                    self?.scrollToTop.accept(())
                }
            }.disposed(by: aliveDisposeBag)
        
        let createCommissionViewModel = MenuDescriptionViewModel(title: feeWillBeCharged)
        
        guard !isStreamer else {
            elements.acceptValue = [
                titleHeaderViewModel,
                titleFieldViewModel,
                descriptionHeaderViewModel,
                descriptionViewModel,
                rewardTitleTableViewModel,
                challengeRewardInputViewModel,
            ]
                + (fee.value.amount > 0 ? [createCommissionViewModel] : [])
                + [buttonViewModel]
            
            return
        }
        
        let imageLoaderViewModel = GRMe.shared.user.map { user -> ImageLoaderViewModel? in
            user?.avatarViewModel(.stream) ?? GRUser.unknownAvatarPlaceholder(.stream).imageLoaderViewModel
        }
        
        let minAmount = broadcast.taskMinimumOwnDonationOnCreate.map { $0?.minimum ?? .zeroEur }
        
        let maxAmount = form.myDonation.inDefaultUserCurrency
        
        let donationTooSmall = String.Localized.Challenges.Create.Error.donationTooSmall(amount: minAmount.amountString.attributed(errorAttributes),
                                                                                         currency: minAmount.currencySymbol.attributed(errorAttributes),
                                                                                         baseAttributes: errorAttributes)
        
        let donationTooBig = String.Localized.Challenges.Create.Error.donationTooSmall(amount: maxAmount.amountString.attributed(errorAttributes),
                                                                                       currency: maxAmount.currencySymbol.attributed(errorAttributes),
                                                                                       baseAttributes: errorAttributes)
        
        let defaultErrorAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
            .map { colors, fonts -> [NSAttributedString.Key: Any] in
                [.foregroundColor: colors.others.infoMessageText,
                 .font: fonts.headline.h7.medium]
            }
        
        let topUpAttributes = Observable.combineLatest(UIColor.rx.kit, UIFont.rx.kit)
            .map { colors, fonts -> [NSAttributedString.Key: Any] in
                [.foregroundColor: colors.blue,
                 .font: fonts.headline.h7.medium,
                 .grTappableRegion: true]
            }
        
        let topUpText =
            String.Localized.Challenges.Create.Error.notEnoughFundsTopUp(topUp: String.Localized.Challenges.Create.TopUp.title.attributed(topUpAttributes),
                                                                         baseAttributes: defaultErrorAttributes)
            .optional
        
        Observable.combineLatest(form.challengeReward.asObservable(),
                                 form.myDonation.asObservable(),
                                 AppConfiguration.shared.rx.config,
                                 minAmount,
                                 maxAmount,
                                 balance)
            .map { (challengeReward, myDonation, config, minAmount, maxAmount, balance) -> InputState in
                
                if myDonation > challengeReward {
                    return .error(String.Localized.Challenges.Create.Error.donationBiggerThanReward.attributed.optional)
                } else if balance.amount < myDonation {
                    return .error(topUpText)
                } else if myDonation < minAmount.amount {
                    return .error(donationTooSmall.optional)
                } else if myDonation > maxAmount.amount {
                    return .error(donationTooBig.optional)
                }
                
                return .ok
            }
            .bind(to: myDonationInputViewModel.inputState)
            .disposed(by: disposeBag)
        
        myDonationInputViewModel.didTapText
            .filterNil()
            .withLatestFrom(Observable.combineLatest(form.myDonation.asObservable(), balance))
            .bind { myDonation, balance in
                context.dispatcher.dispatch(event: DepositsUnavailableEvent())
                // context.dispatcher.dispatch(event: OnShowTopUpEvent(minAmount: myDonation - balance.amount))
            }
            .disposed(by: disposeBag)
        
        let formatter = NumberFormatter.standardDecimalFormatter
        
        let visiblePercent = AppConfiguration.shared.rx.config
            .map { $0.business.task.candidateToPendingRewardThreshold * 100 as NSNumber }
            .map { formatter.string(from: $0) ?? "0" }
            .map { $0 + "%" }
        
        let infoCardText = String.Localized.Challenges.Create.challengeWillBeVisible(percentAmount: visiblePercent.attributed(infoCardPercenAttributes),
                                                                                     baseAttributes: infoCardTextAttributes)
        
        let infoCardViewModel = CreateTaskInfoCardViewModel(donations: form.myDonation.asObservable().debug("ekek1"),
                                                            donationsTarget: form.challengeReward.asObservable().debug("ekek2"),
                                                            title: infoCardText,
                                                            photo: imageLoaderViewModel)
        
        infoCardViewModel.didTapTopUp
            .asObservable()
            .skip(1)
            .withLatestFrom(form.myDonation.asObservable(), resultSelector: { $0 + $1 })
            .bind(to: myDonationInputViewModel.amount)
            .disposed(by: disposeBag)
        
        myDonationInputViewModel.amount.asObservable()
            .bind(to: form.myDonation)
            .disposed(by: disposeBag)
        
        Observable.combineLatest(myDonationInputViewModel.isFirstResponder.asObservable(), challengeRewardInputViewModel.isFirstResponder.asObservable())
            .map { $0.0 || $0.1 }
            .bind(to: isEnteringAmount)
            .disposed(by: aliveDisposeBag)
        
        elements.acceptValue = [
            titleHeaderViewModel,
            titleFieldViewModel,
            descriptionHeaderViewModel,
            descriptionViewModel,
            rewardTitleTableViewModel,
            challengeRewardInputViewModel,
            myDonationInputViewModel,
            emptySeparator,
            infoCardViewModel,
        ]
            + (fee.value.amount > 0 ? [createCommissionViewModel] : [])
            + [buttonViewModel]
    }
    
    private func createTask(for broadcastID: String) {
        guard let title = form.trimmedTitle.value
        else { return }
        
        buttonViewModel.spinnerIsAnimating.acceptValue = true
        buttonEnabled.accept(false)
        
        let form = self.form
        
        let rewardGoal = form.challengeReward.value
        let ownDonation = isStreamer ? nil : form.myDonation.value
        
        let request = API.taskCreate(kind: "ready_for_action",
                                     broarcastID: broadcastID,
                                     title: title,
                                     description: self.form.trimmedDescription.value,
                                     rewardGoal: rewardGoal,
                                     ownDonation: ownDonation)
        
        let mappable: Observable<BroadcastTask> = Socket.default
            .emit(request)
            .rx.responseMappable()
            .retry(delay: .seconds(1))
        
        mappable
            .onMainThread
            .materialize()
            .bind { event in
                switch event {
                case let .next(task):
                    GRAnalytics.shared.trackEvent(ANLEvent.UserCreatedTask())
                    OneSignalManager.shared.challengeCreated()
                    
                    if let sum = ownDonation {
                        GRAnalytics.shared.trackEvent(ANLEvent.SpendMoney())
                        
                        let afSumEvent = ANLEvent.SpendMoneySum(sum: sum, kind: .createTask)
                        GRAnalytics.shared.trackEvent(afSumEvent)
                    }
                    self.buttonViewModel.spinnerIsAnimating.acceptValue = false
                    self.buttonEnabled.accept(true)
                    
                    self.context.dispatcher.dispatch(event: OnCloseCreateTaskEvent())
                    self.taskCreated.acceptValue = task.id
                    
                case let .error(error):
                    InstantNotificationCenter.shared.showTopAlert(TopAlertViewModel(error: error))
                    
                case .completed: break
                }
            }
            .disposed(by: disposeBag)
    }
}
