PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- create new tables
-------------------------------------------------------

CREATE TABLE IF NOT EXISTS active (
	id INTEGER PRIMARY KEY,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS expired (
	id INTEGER,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	u_source VARCHAR(50),
	u_reason VARCHAR(300),
	u_date INTEGER(30),
	last_pos VARCHAR(50)
);
CREATE INDEX IF NOT EXISTS idx_expired_id ON expired(id);

CREATE TABLE IF NOT EXISTS name (
	id INTEGER,
	name VARCHAR(50) PRIMARY KEY,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1)
);
CREATE INDEX IF NOT EXISTS idx_name_id ON name(id);
CREATE INDEX IF NOT EXISTS idx_name_lastlogin ON name(last_login);

CREATE TABLE IF NOT EXISTS address (
	id INTEGER,
	ip VARCHAR(50) PRIMARY KEY,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT(1),
	violation BOOLEAN
);
CREATE INDEX IF NOT EXISTS idx_address_id ON address(id);
CREATE INDEX IF NOT EXISTS idx_address_lastlogin ON address(last_login);

CREATE TABLE IF NOT EXISTS whitelist (
	name_or_ip VARCHAR(50) PRIMARY KEY,
	source VARCHAR(50),
	created INTEGER(30)
);
CREATE TABLE IF NOT EXISTS config (
	setting VARCHAR PRIMARY KEY,
	data VARCHAR
);
CREATE INDEX IF NOT EXISTS idx_config_data ON config(data);

CREATE TABLE IF NOT EXISTS violation (
	id INTEGER PRIMARY KEY,
	data VARCHAR
);


-- create temporary tables for transfering existing data
------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS address_tmp (
	id INTEGER,
	ip VARCHAR(50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT (1),
	violation BOOLEAN
);

CREATE TABLE IF NOT EXISTS active_tmp (
	id INTEGER PRIMARY KEY ON CONFLICT IGNORE,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	last_pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS fix_tmp (
	id INTEGER,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	u_source VARCHAR(50),
	u_reason VARCHAR(300),
	u_date INTEGER(30),
	active BOOLEAN,
	last_pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS name_tmp (
	id INTEGER,
	name VARCHAR(50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT (1)
);

CREATE TABLE IF NOT EXISTS wl_tmp (
	name VARCHAR,
	source VARCHAR,
	created INTEGER
);

-- fix whitelist name field
---------------------------------

INSERT INTO wl_tmp SELECT * FROM whitelist;
DROP TABLE whitelist;
CREATE TABLE whitelist (
	name_or_ip VARCHAR(50) PRIMARY KEY,
	source VARCHAR,
	created INTEGER
);
INSERT INTO whitelist SELECT * FROM wl_tmp;
DROP TABLE wl_tmp;

-- fix text entry id's in bans table
------------------------------------

INSERT INTO fix_tmp SELECT
	playerdata.id,
	bans.name,
	bans.source,
	bans.created,
	bans.reason,
	bans.expires,
	bans.u_source,
	bans.u_reason,
	bans.u_date,
	bans.active,
	bans.last_pos
FROM bans
	INNER JOIN
	playerdata ON playerdata.name = bans.name
WHERE  typeof(bans.id) = 'text';

DELETE FROM bans WHERE typeof(bans.id) = 'text';
INSERT INTO bans SELECT * FROM fix_tmp;

-- transfer existing data to new tables
----------------------------------------------

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

-- insert the active
INSERT INTO active_tmp SELECT
	id,
	name,
	source,
	created,
	reason,
	expires,
	last_pos
FROM bans WHERE active = 'true';

-- initialise expires
UPDATE active SET expires = 0 WHERE expires = '';

-- initialise versions
INSERT INTO config VALUES('db_version', '0.2.1');
INSERT INTO config VALUES('mod_version', '0.2.0');

INSERT INTO address_tmp (id, ip, created, last_login) SELECT DISTINCT id,ip, created, last_login FROM playerdata;
INSERT INTO name_tmp (id, name, created, last_login) SELECT DISTINCT id, name, created, last_login FROM playerdata;
INSERT INTO address SELECT * FROM address_tmp;
INSERT INTO active SELECT * FROM active_tmp;
INSERT INTO name SELECT * FROM name_tmp;

-- clean up temporary tables
-----------------------------------------

DROP TABLE address_tmp;
DROP TABLE bans;
DROP TABLE active_tmp;
DROP TABLE name_tmp;
DROP TABLE players;
DROP TABLE playerdata;
DROP TABLE version;
DROP TABLE fix_tmp;

COMMIT;

PRAGMA foreign_keys = ON;

VACUUM;
