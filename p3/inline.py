def find_user(db, name): return db.execute("SELECT * FROM users WHERE name = '" + name + "'").fetchall()
