//
//  ItemLoaderOperation.swift
//  iSub
//
//  Created by Benjamin Baron on 1/7/17.
//  Copyright © 2017 Ben Baron. All rights reserved.
//

import Foundation

class ItemLoaderOperation: Operation {
    fileprivate(set) var loader: ItemLoader
    let onlyLoadIfNotExists: Bool
    
    init(loader: ItemLoader, onlyLoadIfNotExists: Bool = true) {
        self.loader = loader
        self.onlyLoadIfNotExists = onlyLoadIfNotExists
        super.init()
    }
    
    override var isAsynchronous: Bool {
        return true
    }
    
    override var isExecuting: Bool {
        return isExecutingInternal
    }
    
    override var isFinished: Bool {
        return isFinishedInternal
    }
    
    fileprivate var isExecutingInternal = false {
        willSet {
            willChangeValue(forKey: "isExecuting")
        }
        didSet {
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    fileprivate var isFinishedInternal = false {
        willSet {
            willChangeValue(forKey: "isFinished")
        }
        
        didSet {
            didChangeValue(forKey: "isFinished")
        }
    }
    
    override func start() {
        isExecutingInternal = true
        execute()
    }
    
    func execute() {
        var shouldLoad = true
        if onlyLoadIfNotExists {
            // Only load if it's not persisted
            if let persistedItem = loader.associatedItem as? PersistedItem {
                // If we have duplicate loaders in the queue, the first one should have a nil associated object
                // and the second one should have isPersisted = true, so should skip loading.
                shouldLoad = !persistedItem.isPersisted
            }
        }
        
        if shouldLoad {
            let existingCompletionHandler = loader.completionHandler
            loader.completionHandler = { success, error, loader in
                self.finish()
                existingCompletionHandler?(success, error, loader)
            }
            loader.start()
        } else {
            finish()
        }
    }
    
    func finish() {
        // Notify the completion of async task and hence the completion of the operation
        isExecutingInternal = false
        isFinishedInternal = true
    }
}
