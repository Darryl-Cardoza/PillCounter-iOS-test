//
//  Hl7Repository.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/02/26.
//
import SwiftUI


final class Hl7Repository{
    
    static let shared = Hl7Repository()

    // local storage // db
    let pillDataLocalStorage = PillsDataLocalStorage.shared

    // user storage // db
    let userDataLocalStorage = UserLocalDataSource.shared
    
    
    // this will hold the current scanning transaction that user is performing or working with.
    @Published var currentTransaction: PillCountTransactionEntity?

    
    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userId: String = ""
    
    var onTransactionCreated: (() -> Void)?


    func handleReceivedMessage(_ message: String) {
        
        Task(priority: .background) {
            await createTransaction(
                drugId: 156468,
                countType: .REGULAR
            )
            onTransactionCreated?()
        }
    }

    
    func createTransaction(
        drugId: Int64, countType: CountType, barcodeImage: UIImage? = nil
    ) async {
        // creating the transaction for the pill.
        // step1: get the user.
        guard
            !userId.isEmpty,
            let user = userDataLocalStorage.getUserByUserId(by: userId)
        else {
            return
        }

        // Save Image using Helper if it exists
        var savedPath = ""
        if let img = barcodeImage {
            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            }
        }

        // step 2: we have got all, user id, drugId, count type, for now the barcode image is set to empty string.
        // we now call the db function to create the transaction.
        pillDataLocalStorage.createTransaction(
            for: user,
            drugId: drugId,
            countType: countType,
            barcodeImagePath: savedPath,
            isComingFromPms: true
        )

        // step 3: set the latest transaction as current transaction.
        if let latest = pillDataLocalStorage.fetechLatestTransactionOfUser(
            for: user)
        {
            self.currentTransaction = latest
        }
    }
    
    
    func markSynced(txnId: Int64) {
        
    }
}
