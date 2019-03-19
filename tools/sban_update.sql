PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- create tables

CREATE TABLE IF NOT EXISTS address (
	id INTEGER (10),
	ip TEXT (50) PRIMARY KEY,
	created INTEGER (30),
	last_login INTEGER (30),
	login_count INTEGER (8) DEFAULT (1),
	violation BOOLEAN
);

CREATE TABLE IF NOT EXISTS address_tmp (
	id INTEGER (10),
	ip TEXT (50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER (30),
	last_login INTEGER (30),
	login_count INTEGER (8) DEFAULT (1),
	violation BOOLEAN
);

CREATE TABLE IF NOT EXISTS active  (
	id INTEGER (10) PRIMARY KEY,
	name TEXT (50),
	source TEXT (50),
	created INTEGER (30),
	reason TEXT (300),
	expires INTEGER (30),
	last_pos TEXT (50)
);

CREATE TABLE IF NOT EXISTS active_tmp (
	id INTEGER (10) PRIMARY KEY ON CONFLICT IGNORE,
	name TEXT (50),
	source TEXT (50),
	created INTEGER (30),
	reason TEXT (300),
	expires INTEGER (30),
	last_pos TEXT (50)
);

CREATE TABLE IF NOT EXISTS config (
	mod_version TEXT,
	db_version TEXT
);

CREATE TABLE IF NOT EXISTS expired (
	id INTEGER (10),
	name TEXT (50),
	source TEXT (50),
	created INTEGER (30),
	reason TEXT (300),
	expires INTEGER (30),
	u_source TEXT(50),
	u_reason TEXT(300),
	u_date INTEGER (30),
	last_pos TEXT(50)
);

CREATE TABLE IF NOT EXISTS name (
	id INTEGER (10),
	name TEXT (50) PRIMARY KEY,
	created INTEGER (30),
	last_login INTEGER (30),
	login_count INTEGER (6) DEFAULT (1)
);

CREATE TABLE IF NOT EXISTS name_tmp (
	id INTEGER (10),
	name TEXT (50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER (30),
	last_login INTEGER (30),
	login_count INTEGER (6) DEFAULT (1)
);

CREATE TABLE IF NOT EXISTS violation (
    src_id    INTEGER (10),
    target_id INTEGER (10),
    ip        TEXT (20),
    created   INTEGER (30)
);

-- insert the inactive bans into expired
INSERT INTO expired SELECT
	id,
	name,
	source,
	created,
	reason,
	expires,
	u_source,
	u_reason,
	u_date,
	last_pos
FROM bans WHERE active != 'true';

-- insert the ative
INSERT INTO active_tmp SELECT
	id,
	name,
	source,
	created,
	reason,
	expires,
	last_pos
FROM bans WHERE active = 'true';

INSERT INTO address_tmp (id, ip, created) SELECT DISTINCT id, ip, created FROM playerdata;
INSERT INTO name_tmp (id, name, created, last_login) SELECT DISTINCT id, name, created, last_login FROM playerdata;
INSERT INTO config VALUES('1.1', '0.2.1');
INSERT INTO address SELECT * FROM address_tmp;
INSERT INTO active SELECT * FROM active_tmp;
INSERT INTO name SELECT * FROM name_tmp;

-- clean up
DROP TABLE address_tmp;
DROP TABLE bans;
DROP TABLE active_tmp;
DROP TABLE name_tmp;
DROP TABLE players;
DROP TABLE playerdata;
DROP TABLE version;

COMMIT;

PRAGMA foreign_keys = ON;

VACUUM;
