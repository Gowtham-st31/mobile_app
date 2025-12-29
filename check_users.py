from pymongo import MongoClient
from werkzeug.security import generate_password_hash
from datetime import datetime
import os

# Optional local dev support: load environment variables from a .env file.
try:
    from dotenv import load_dotenv  # type: ignore

    load_dotenv()
except Exception:
    pass

# IMPORTANT: Do not hard-code database credentials in source code.
# Provide MONGO_URI via environment variables (or a local .env file).
MONGO_URI = os.getenv("MONGO_URI")
if not MONGO_URI:
    # Safe local default for development (requires a local MongoDB instance).
    MONGO_URI = "mongodb://localhost:27017"

DB_NAME = "powerloom"
USERS_COLLECTION = "users" # This is the collection where user data is stored

client = None

try:
    print(f"\n--- Attempting to connect to MongoDB to manage {DB_NAME}.{USERS_COLLECTION} ---")
    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    users_collection = db[USERS_COLLECTION]

    # Test the connection to primary just to be sure
    client.admin.command('ismaster')
    print("✅ MongoDB connection successful.")

    admin_username = "admin"
    admin_password = "adminpass"  # This is the password you will use to log in
    
    # Hash the password using werkzeug.security
    hashed_password = generate_password_hash(admin_password)

    # Use update_one with upsert=True to either create the admin user or reset its password
    result = users_collection.update_one(
        {"username": admin_username}, # Query for the 'admin' user (ensure lowercase as per login logic)
        {
            "$set": { # Set or update these fields
                "password_hash": hashed_password,
                "role": "admin",
                "created_at": datetime.utcnow() # Record the creation/update time
            }
        },
        upsert=True # If the user doesn't exist, insert it. If it does, update it.
    )

    if result.upserted_id:
        print(f"✅ Admin user '{admin_username}' created with a new password.")
    elif result.modified_count > 0:
        print(f"🔁 Admin user '{admin_username}' found. Password has been reset/updated.")
    else:
        print(f"ℹ️ Admin user '{admin_username}' already exists and password was already up-to-date (no changes made).")


    print(f"\n🔑 Use these credentials to log in to the application:")
    print(f"   Username: {admin_username}")
    print(f"   Password: {admin_password}") # This is the plaintext password you type

except Exception as e:
    print(f"❌ Error during MongoDB operation in check_users.py: {e}")
    # Print the full traceback for more detailed debugging
    import traceback
    traceback.print_exc()
finally:
    if client:
        client.close()
        print("✅ MongoDB client connection closed.")

