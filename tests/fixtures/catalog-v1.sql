-- Frozen initial catalog schema; intentionally independent of runtime DDL.
    CREATE TABLE nodes(id TEXT PRIMARY KEY,identity TEXT UNIQUE NOT NULL,product_key TEXT NOT NULL,
      kind TEXT NOT NULL,path TEXT NOT NULL,first_seen REAL NOT NULL,last_seen REAL NOT NULL,baseline INTEGER NOT NULL);
    CREATE TABLE instruments(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE physical_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,instrument_id TEXT NOT NULL,path TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,instrument_id,path), FOREIGN KEY(scope_id,node_id,instrument_id) REFERENCES instruments(scope_id,node_id,id));
    CREATE TABLE scopes(id TEXT PRIMARY KEY,configuration TEXT NOT NULL,evidence TEXT NOT NULL,saved_at REAL NOT NULL,generation TEXT NOT NULL,complete INTEGER NOT NULL);
    CREATE TABLE scope_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,path TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,baseline INTEGER NOT NULL,PRIMARY KEY(scope_id,node_id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE removals(path TEXT PRIMARY KEY);
    CREATE INDEX instruments_parent ON instruments(node_id);
    CREATE INDEX members_scope ON scope_members(scope_id);
PRAGMA application_id=1397575756;
PRAGMA user_version=1;
