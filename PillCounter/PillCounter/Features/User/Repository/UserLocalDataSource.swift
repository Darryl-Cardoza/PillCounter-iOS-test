//
//  UserLocalDataSource.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import CoreData

final class UserLocalDataSource {
    
    enum UserField: String {
        case name = "name"
        case email = "email"
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case isProfileCompleted = "is_profile_completed"
        case pharmacyName = "pharmacy_name"
        case npiId = "npi_id"
        case language = "language"
        case timezone = "timezone"
        case notifications = "notifications"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }
    
    //singleton instance
    static let shared = UserLocalDataSource()
    
    // get the context from the CoreDataManager
//    private let context = CoreDataManager.shared.context
    
    // background context // this is used to store the values in the db in background.
//    private let context = CoreDataManager.shared.backgroundContext
    
    private let mainThreadContext = CoreDataManager.shared.context
    
    // init function since singleton instance.
    private init() {}
    
    // save user details to database
    func saveUser(from response: UserResponse) {
        
        guard let userDetails = response.data else {
            print("❌ No user data found in response.")
            return
        }
        
//        deleteUser() // i guess we need to map this accordingly based on the local id or user id. so not deleting the user.
        
        let entity = UserEntity(context: mainThreadContext)
        
        entity.user_id = userDetails.profile?.userId ?? ""
        
        
        if let profile = userDetails.profile {
            
            // save the profile details of the user.
            entity.name = profile.fullName ?? ""
            entity.email  = profile.email ?? ""
            entity.phone_number = profile.phoneNumber ?? ""
            entity.avatar_url = profile.avatarURL ?? ""
            entity.is_profile_completed = profile.isProfileCompleted ?? false
            entity.pharmacy_name = profile.pharmacyName ?? ""
            entity.npi_id = profile.npiID ?? ""
            entity.is_verified = profile.isVerified ?? false
        }
        
        if let settings = userDetails.settings {
            
            // save the settings of the user to db
            entity.notifications = settings.notificationsEnabled ?? false
            entity.language = settings.language ?? "en"
            entity.timezone = settings.timezone ?? "Asia/Kolkata"
        }
        
        // save the created at.
        
        entity.created_at = Date()
        
        // save all the data to the db using the save function of CoreDataManager.
        CoreDataManager.shared.save(context: mainThreadContext)
    }
    
    // get user by user id.
    func getUserByUserId(by userId: String) -> UserEntity? {


        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user_id == %@", userId)
        request.fetchLimit = 1

        do {
            let result = try mainThreadContext.fetch(request)

            if let user = result.first {
                return user
            } else {
                print("🔴 DB: No user found for id =", userId)
                return nil
            }

        } catch {
            print("❌ DB ERROR fetching user:", error.localizedDescription)
            return nil
        }
    }
    
    
    // get all users
    func getAllUsers() -> [UserEntity] {


        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()

        do {
            let users = try mainThreadContext.fetch(request)


            for user in users {
            }

            return users

        } catch {
            print("❌ DB ERROR fetching all users:", error.localizedDescription)
            return []
        }
    }

        
    // update the value of the fields.
    func updateUser(userId: String, field: UserField, value: Any?) {
        guard let user = getUserByUserId(by: userId) else {
            print("❌ user not found")
            return
        }
        
        user.setValue(value, forKey: field.rawValue)
        CoreDataManager.shared.save(context: mainThreadContext)
    }
    
    // get all transactions for the user.
    func getTransactions(for user: UserEntity, type: CountType) -> [PillCountTransactionEntity] {
        let set = user.transactions as? Set<PillCountTransactionEntity> ?? []
        
        return set
            .filter { !$0.is_deleted }
            .filter { $0.count_type?.uppercased() == type.rawValue}
            .sorted { $0.created_at < $1.created_at }
    }
    
    // get all transactions for the filterd by created_at date.
    func getTransactionsForUserFilteredByDate(for user: UserEntity, startDateTs: Int64, endDateTs: Int64) -> [PillCountTransactionEntity] {
        let set = user.transactions as? Set<PillCountTransactionEntity> ?? []
        
        return set  
            .filter { txn in
                txn.created_at >= startDateTs && txn.created_at < endDateTs &&
                txn.is_deleted == false
            }
            .sorted { $0.created_at < $1.created_at }
    }
}
