//
//  CoreDataManager.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import CoreData

final class CoreDataManager {

    // singleton instanace
    static let shared = CoreDataManager()

    let container: NSPersistentContainer

    // init function
    private init() {
        container = NSPersistentContainer(name: "PillCounter")
        container.loadPersistentStores { description, error in
            if let error = error {
                print(
                    "❌ Failed to load Core Date : \(error.localizedDescription)"
                )
            }
        }
    }
    
    // core data context
    var context: NSManagedObjectContext {
        container.viewContext
    }
    
    var backgroundContext: NSManagedObjectContext {
        container.newBackgroundContext()
    }
    
    // global save function to save into the database.
    func save(context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch let error {
                print("❌ Error saving Core data : \(error.localizedDescription)")
            }
        }
    }
    
    func resetContext() {
        container.viewContext.performAndWait {
            container.viewContext.reset()
        }
    }

}
