//
//  UnsyncedTransaction .swift
//  PillCounter
//
//  Created by Bhushan Patil on 06/02/26.
//

import CoreData
import Combine
import CoreData
import Combine


extension PillsDataLocalStorage {

    typealias PillTxnPublisher = AnyPublisher<[PillCountTransactionEntity], Never>
    

    func observePendingHl7Transactions() -> PillTxnPublisher {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: """
            is_deleted == false
            AND isComingFromPms == true
            AND (isSynced == false OR isSynced == nil)
            AND status IN %@ 
            """,
            [
                CountStatus.COMPLETED.rawValue,
                CountStatus.FORCE_COMPLETED.rawValue
            ]
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "updated_at", ascending: true)
        ]

        let subject = CurrentValueSubject<[PillCountTransactionEntity], Never>([])

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: mainThreadContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        let delegate = PendingTxnFetchedResultsDelegate { txns in
            subject.send(txns)
        }

        controller.delegate = delegate

        // RETAIN THEM (THIS IS CRITICAL)
        self.pendingTxnController = controller
        self.pendingTxnDelegate = delegate

        do {
            try controller.performFetch()
            subject.send(controller.fetchedObjects ?? [])
        } catch {
            print("Failed to fetch pending HL7 txns:", error)
        }

        return subject.eraseToAnyPublisher()
    }
    
    
    func getPendingHl7Txn() -> [PillCountTransactionEntity] {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: """
            is_deleted == false
            AND isComingFromPms == true
            AND (isSynced == false OR isSynced == nil)
            AND status IN %@ 
            """,
            [
                CountStatus.COMPLETED.rawValue,
                CountStatus.FORCE_COMPLETED.rawValue
            ]
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "updated_at", ascending: true)
        ]

        do {
            return try mainThreadContext.fetch(request)
        } catch {
            print("Failed to fetch pending HL7 transactions:", error)
            return []
        }
    }

}

final class PendingTxnFetchedResultsDelegate:
    NSObject,
    NSFetchedResultsControllerDelegate {

    private let onChange: ([PillCountTransactionEntity]) -> Void

    init(onChange: @escaping ([PillCountTransactionEntity]) -> Void) {
        self.onChange = onChange
    }

    func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        let txns =
            controller.fetchedObjects as? [PillCountTransactionEntity] ?? []
        onChange(txns)
    }
}
