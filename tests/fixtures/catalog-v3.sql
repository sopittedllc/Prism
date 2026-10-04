-- Frozen catalog v2 schema; independent of runtime migration DDL.
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
ALTER TABLE scope_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
ALTER TABLE instruments ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
ALTER TABLE physical_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
CREATE TABLE root_baselines(kind TEXT NOT NULL,path TEXT NOT NULL,exclusions TEXT NOT NULL,complete INTEGER NOT NULL,PRIMARY KEY(kind,path,exclusions));
CREATE TABLE metadata_overrides(subject TEXT PRIMARY KEY,node_id TEXT NOT NULL,payload TEXT NOT NULL,FOREIGN KEY(node_id) REFERENCES nodes(id));
CREATE INDEX metadata_node ON metadata_overrides(node_id);
PRAGMA user_version=2;

-- Frozen schema3 additions; independent of runtime DDL.
CREATE TABLE date_evidence(source_id TEXT COLLATE BINARY NOT NULL,evidence_id TEXT COLLATE BINARY NOT NULL,subject_id TEXT COLLATE BINARY NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(source_id,evidence_id),FOREIGN KEY(subject_id) REFERENCES nodes(id));
CREATE INDEX date_evidence_subject ON date_evidence(subject_id);
PRAGMA user_version=3;
