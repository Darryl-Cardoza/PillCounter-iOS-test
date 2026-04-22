//
//  BatchCountMapper.swift
//  PillCounter
//
//  Created by Bhushan Patil on 22/04/26.
//

extension BatchCountEntity {
    func toStockData(ndcCount: Int) -> StockData {
        return StockData(
            id: self.batch_id,
            batchId: self.batch_id,
            createdAt: self.start_date_time,
            ndcCount: Int64(ndcCount),
            status: self.status ?? "",
            bucketId: self.bucket_id ?? "",
            isFromPms: self.req_id_from_pms != nil
        )
    }
}
