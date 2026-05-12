//
//  Hl7ServiceController+TxnQueueStorage.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//
//  Stores txnSyncQueue as an associated object on Hl7ServiceController.
//  Mirrors Hl7ServiceController+SyncQueueStorage.swift exactly.
//

import Foundation

private enum TxnQueueKey {
    static var key: UInt8 = 0
}

extension Hl7ServiceController {

    var txnSyncQueue: HL7TxnSyncQueue? {
        get {
            objc_getAssociatedObject(self, &TxnQueueKey.key) as? HL7TxnSyncQueue
        }
        set {
            objc_setAssociatedObject(
                self,
                &TxnQueueKey.key,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
