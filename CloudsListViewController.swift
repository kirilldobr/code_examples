
import BetterSegmentedControl
import CoreBluetooth
import EasyPeasy
import Foundation
import RxCocoa
import RxSwift
import SwiftEntryKit
import UIKit

class HomeViewModel: ViewModel {
    let popupViewModel = PopupViewModel()
    let cloudsListTableViewModel = TableViewModel()
    let noCloudsPlaceholderViewModel = NoCloudsPlaceholderViewModel()
    let shouldRemoveCloudAtRow = PublishRelay<CloudCardViewModel>()
    let selectedPage = BehaviorRelay<HomePage>(value: .clouds)
    
    override init() {
        super.init()
        
        // CloudStorage.shared.add(Cloud.mock.asCodable)
        
        let allCloudsGroup = CloudStorage.shared.clouds.map {
            CloudGroup(cloudIDs: $0.map { $0.hostname },
                       name: Strings.cloudGroup.allClouds,
                       id: UUID())
        }
        
        let situation = Observable.combineLatest(CloudStorage.shared.clouds,
                                                 allCloudsGroup,
                                                 CloudGroupStorage.shared.groups,
                                                 selectedPage)
            .share(replay: 1)
        
        func sortClouds<T: CloudType>(_ clouds: [T]) -> [T] {
            clouds.sorted(by: { $0.id > $1.id })
        }
        
        func sortGroups<T: CloudGroup>(_ clouds: [T]) -> [T] {
            clouds.sorted(by: { $0.groupTitle.value < $1.groupTitle.value })
        }
        
        shouldRemoveCloudAtRow
            .bind { cardViewModel in
            CloudStorage.shared.remove(cardViewModel.cloud.id)
            CloudGroupStorage.shared.remove(cardViewModel.cloud.id)
        }
            >>> aliveDisposeBag
        
        situation
            .map { clouds, allCloudsGroup, groups, page -> [TappableViewModel] in
            guard !clouds.isEmpty else { return [] }
            
            switch page {
            case .clouds:
                guard !clouds.isEmpty else { return [] }
                return [TitleViewModel(text: .just(Strings.home.myClouds))]
                    + sortClouds(clouds).map { CloudCardViewModel($0) }
                
            case .groups:
                let allCard = CloudCardViewModel(allCloudsGroup)
                
                return [TitleViewModel(text: .just(Strings.home.myClouds))]
                    + [allCard] + sortGroups(groups).map { CloudCardViewModel($0) }
            }
        }
        .bind(to: cloudsListTableViewModel.elements)
        .disposed(by: aliveDisposeBag)
    }
}

enum HomePage {
    case clouds
    case groups
}

class HomeViewController: ViewController<HomeViewModel> {
    let addButton = UIBarButtonItem(barButtonSystemItem: .add,
                                    target: self,
                                    action: nil)
    
    let infoButton = UIBarButtonItem(image: UIImage(named: "infoTest")!,
                                     style: .done,
                                     target: self,
                                     action: nil)
    
    let placeholder = NoCloudsPlaceholderView()
    
    private let refreshControl = UIRefreshControl()
    
    private let shadowView = ShadowView()
    
    let cloudsListTableView = TableView<TableViewModel>()
    
    private let selectedPageInVC = DistinctBehaviorRelay<HomePage>(value: .clouds)
    
    lazy var switcher = BetterSegmentedControl(
        frame: CGRect(x: 0, y: 0, width: 300, height: 44),
        segments: [
            LabelSegment(text: Strings.home.clouds,
                         numberOfLines: 0,
                         normalBackgroundColor: .clear,
                         normalFont: UIFont.systemFont(ofSize: 18, weight: .light),
                         normalTextColor: .lightGray,
                         selectedBackgroundColor: .clear,
                         selectedFont: UIFont.systemFont(ofSize: 18, weight: .bold),
                         selectedTextColor: .white),
            
            LabelSegment(text: Strings.home.groups,
                         numberOfLines: 0,
                         normalBackgroundColor: .clear,
                         normalFont: UIFont.systemFont(ofSize: 18, weight: .light),
                         normalTextColor: .lightGray,
                         selectedBackgroundColor: .clear,
                         selectedFont: UIFont.systemFont(ofSize: 18, weight: .bold),
                         selectedTextColor: .white),
        ],
        index: 0,
        options: [.backgroundColor(.clear),
                  .indicatorViewBackgroundColor(Colors.dark)]
    )
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cloudsListTableView.tableView.refreshControl = refreshControl
        
        navigationItem.title = "Cloudy"
        navigationItem.rightBarButtonItem = addButton
        navigationItem.leftBarButtonItem = infoButton
        
        cloudsListTableView.tableView.easy.layout(Left(16), Right(0))
        cloudsListTableView.tableView.clipsToBounds = false
        
        view.addSubview(cloudsListTableView, layout: Edges())
        view.addSubview(shadowView, layout: Bottom(), Left(), Right(), Height(72))
        view.addSubview(switcher, layout: Bottom(12).to(view.safeAreaLayoutGuide, .bottom), Left(12), Right(12), Height(50))
        view.addSubview(placeholder, layout: Edges())
        
        cloudsListTableView.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 67, right: 0)
        
        switcher.cornerRadius = 24
        switcher.addTarget(self, action: #selector(switcherSwitched), for: .valueChanged)
        switcher.options = [.indicatorViewBorderColor(.darkGray), .indicatorViewBorderWidth(1)]
    }
    
    @objc
    func switcherSwitched() {
        switch switcher.index {
        case 0: selectedPageInVC.accept(.clouds)
        case 1: selectedPageInVC.accept(.groups)
        default: break
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        BTService.shared.isOnCloudListVC.accept(true)
        log.info("list view Did appear")
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        BTService.shared.isOnCloudListVC.accept(false)
        log.info("list view Did disappear")
    }
    
    override func setModel(_ viewModel: HomeViewModel) {
        super.setModel(viewModel)
        
        refreshControl.rx.controlEvent(.valueChanged)
            .bind { [weak self] _ in
                mDNSService.shared.startSearching()
                self?.refreshControl.endRefreshing()
            } >>> disposeBag
        
        cloudsListTableView.tableView.rx.itemDeleted
            .map { [viewModel] indexPath -> CloudCardViewModel? in
                viewModel.cloudsListTableViewModel.elements.value.element(at: indexPath.row) as? CloudCardViewModel
            }
            .filterNil()
            >>> viewModel.shouldRemoveCloudAtRow
            >>> disposeBag
        
        cloudsListTableView.canEditRowAtIndexPath = { [weak self] indexPath in
            guard let self = self else { return false }
            
            guard let item = self.cloudsListTableView.viewModel?.elements.value.element(at: indexPath.row) else {
                return false
            }
            
            if self.selectedPageInVC.value == .clouds {
                guard let cloud = (item as? CloudCardViewModel)?.cloud else {
                    return false
                }
                return cloud.connection.value.isConnected == false
            } else {
                // Skip title and "All Clouds" group
                return indexPath.row > 1
            }
        }
        
        viewModel.cloudsListTableViewModel.elements
            .map { $0.count != 0 }
            .bind(to: placeholder.rx.isHidden)
            .disposed(by: disposeBag)
        
        selectedPageInVC.asObservable()
            >>> viewModel.selectedPage
            >>> disposeBag
        
        CloudStorage.shared.clouds
            --> { [weak self] elements in
                let switcherShouldBeHidden = elements.count < 2
                self?.switcher.isHidden = switcherShouldBeHidden
                if switcherShouldBeHidden {
                    self?.switcher.setIndex(0)
                    self?.selectedPageInVC.accept(.clouds)
                }
            } >>> disposeBag
        
        cloudsListTableView.setModel(viewModel.cloudsListTableViewModel)
        placeholder.setModel(viewModel.noCloudsPlaceholderViewModel)
        let cloudVC = SingleCloudControlViewController()
        
        viewModel.cloudsListTableViewModel.modelSelected
            .bind { [weak self] model in
                guard let model = model as? CloudCardViewModel else { return }
                let vm = CloudControlViewModel(cloud: model.cloud)
                cloudVC.setModel(vm)
                self?.navigationController?.pushViewController(cloudVC, animated: true)
            }
            .disposed(by: disposeBag)
        
        viewModel.noCloudsPlaceholderViewModel.buttonViewModel.didTap
            .bind { _ in
                CloudPairingService.shared.showPopup()
                BTService.shared.restartScan()
            }
            .disposed(by: disposeBag)
        
        let newGroupViewController = CreateCloudGroupViewController()
        let newGroupViewModel = CreateCloudGroupViewModel()
        addButton.rx.tap
            .withLatestFrom(selectedPageInVC)
            .bind { [weak self] page in
                
                switch page {
                case .clouds:
//                    BTService.shared.restartScan()
                    CloudPairingService.shared.showPopup()
                    BTService.shared.restartScan()
                    
                case .groups:
                    newGroupViewModel.headerViewModel.fieldViewModel.text.accept("")
                    newGroupViewModel.selectedClouds.accept([])
                    newGroupViewController.setModel(newGroupViewModel)
                    self?.navigationController?.pushViewController(newGroupViewController, animated: true)
                }
            }
            .disposed(by: disposeBag)
        
        let menuVC = MenuViewController()
        
        infoButton.rx.tap
            .bind { [weak self] _ in
                menuVC.setAnyModel(MenuViewModel())
                self?.navigationController?.pushViewController(menuVC, animated: true)
            }
            .disposed(by: disposeBag)
    }
}
