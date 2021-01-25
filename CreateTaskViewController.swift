

import EasyPeasy
import RxCocoa
import RxSwift
import UIKit

extension CreateTaskViewController: DeniedUnpinAttemptHandler {
    func handleDeniedUnpinAttempt() {
        viewModel?.cancelPressed.accept(())
    }
}

class CreateTaskViewController: StackViewController, Transitionable, ViewModelSettableDefinition, DisposeBagDefinition {
    override var canUnpinHere: Bool {
        return false
    }
    
    private let cancelButton = BarButtonItem(title: String.Localized.Buttons.cancel, style: .plain, target: self, action: nil)
    
    var disposeBag = DisposeBag()
    
    override var onlyPortraitAllowed: Bool? {
        return false
    }
    
    private let association: ViewModelAssociation<UIView.Type> = [
        TextFieldViewModel.self: MenuFieldView.self,
        MenuTextView.VM.self: MenuTextView.self,
        // MenuFieldWithTitleViewModel.self: MenuFieldWithTitleView.self,
        MenuPickerViewModel.self: MenuPickerView.self,
        // MenuTitleView.VM.self: MenuTitleView.self,
        MenuSeparatorView.VM.self: MenuSeparatorView.self,
        MenuDescriptionViewModel.self: MenuDescriptionView.self,
        MenuMoneyInputViewModel.self: MenuMoneyInputView.self,
        CreateTaskInfoCardViewModel.self: MenuCreateTaskCardView.self,
        CreateTaskButtonTableViewCell.VM.self: CreateTaskButtonTableViewCell.self,
        MenuCompactTitleView.VM.self: MenuCompactTitleView.self,
    ]
    
    var viewModel: CreateTaskViewModel? {
        willSet {
            unbindViewModelIfAny()
        }
        
        didSet {
            guard let viewModel = viewModel else { return }
            bindViewModel()
            
            cancelButton.rx.tap
                .bind(to: viewModel.cancelPressed)
                .disposed(by: disposeBag)
            
            viewModel.scrollToTop.asObservable()
                .filterNil()
                .onMainThread
                .bind(onNext: { [weak self] in
                    UIView.animate(withDuration: 0.2, animations: {
                        self?.scrollView.contentOffset = CGPoint(x: 0, y: -12)
                    }, completion: { _ in
                        self?.stackView.endEditing(true)
                    })
                    
                })
                .disposed(by: disposeBag)
            
            Observable.combineLatest(viewModel.isEnteringAmount.asObservable(), RxKeyboard.instance.visibleHeight.asObservable())
                .onMainThread
                .bind(onNext: { [weak self] _, keyboardHeight in
                    guard let self = self else { return }
                    self.scrollView.contentInset.bottom = max(keyboardHeight, self.bottomContentInset)
                })
                .disposed(by: disposeBag)
            
            Observable.combineLatest(viewModel.isEnteringAmount.asObservable(), RxKeyboard.instance.visibleHeight.asObservable())
                .onMainThread
                .bind(onNext: { [weak self] shouldAdjustTableView, keyboardHeight in
                    guard let self = self, shouldAdjustTableView else { return }
                    
                    for view in self.stackView.subviews where view is MenuCreateTaskCardView {
                        let possibleOffset = (view.origin.y + view.frame.height) - (self.scrollView.frame.height - keyboardHeight) + 16
                        self.scrollView.contentOffset.y = possibleOffset < 0 ? 0 : possibleOffset
                    }
                })
                .disposed(by: disposeBag)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        String.Localized.Challenges.Create.title
            .onMainThread
            .bind(to: navigationItem.rx.title)
            .disposed(by: aliveDisposeBag)
        
        navigationItem.leftBarButtonItem = cancelButton
        
        fill(with: viewModel, association: association, disposeBag: disposeBag)
    }
}
