
import Foundation

struct ThreadSafeQueue<T> {
    private var array = [T]()
    
    private let dispatchQueue = DispatchQueue(
        label: "ThreadSafeQueue<\(T.self)>",
        qos: .utility,
        attributes: .concurrent
    )
    
    // MARK: Non-mutating
    
    var isEmpty: Bool {
        dispatchQueue.sync { array.isEmpty }
    }
    
    var count: Int {
        dispatchQueue.sync { array.count }
    }
    
    func next() -> T? {
        dispatchQueue.sync { array.first }
    }
    
    // MARK: Mutating
    
    mutating func insertFirst(_ element: T) {
        dispatchQueue.sync(flags: .barrier) {
            array.insert(element, at: 0)
        }
    }
    
    /// Adds an array of elements to the end of the queue.
    /// Returns count of elements in the queue after insertion.
    @discardableResult
    mutating func enqueue(elementsOf arr: [T]) -> Int {
        dispatchQueue.sync(flags: .barrier) {
            array.append(contentsOf: arr)
            return array.count
        }
    }
    
    /// Adds an element to the end of the queue.
    /// Returns count of elements in the queue after insertion.
    @discardableResult
    mutating func enqueue(_ element: T) -> Int {
        enqueue(elementsOf: [element])
    }
    
    @discardableResult
    mutating func dequeue() -> T? {
        dispatchQueue.sync(flags: .barrier) {
            if !array.isEmpty {
                return array.removeFirst()
            }
            return nil
        }
    }
    
    mutating func clear() {
        dispatchQueue.sync(flags: .barrier) {
            array.removeAll()
        }
    }
}

