//
//  HistoryViewModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    
    let pillLocalDB = PillsDataLocalStorage.shared
    
    // transactions of the user filtered by dates.
    @Published var filteredTransactionsOfUserByDate:
    [PillCountTransactionEntity] = []
    
    @Published var filteredBatchesOfUserByDate: [BatchCountEntity] = []
    
    
    func getBatchesByDate(startDate: Date, endDate: Date) async {

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        let startTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs   = Int64(endOfDay.timeIntervalSince1970 * 1000)

        let batches = pillLocalDB.getBatchesForUserFilteredByDate(
            startDateTs: startTs,
            endDateTs: endTs
        )

        await MainActor.run {
            self.filteredBatchesOfUserByDate = batches
        }
    }
    
}
