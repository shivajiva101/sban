PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- create new tables
-------------------------------------------------------

CREATE TABLE IF NOT EXISTS active (
  id INTEGER(10) PRIMARY KEY,
  name VARCHAR(50),
  source VARCHAR(50),
  created INTEGER(30),
  reason VARCHAR(300),
  expires INTEGER(30),
  pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS expired (
  id INTEGER(10) PRIMARY KEY,
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
  id INTEGER(10),
  name VARCHAR(50) PRIMARY KEY,
  created INTEGER(30),
  last_login INTEGER(30),
  login_count INTEGER(8) DEFAULT(1)
);
CREATE INDEX IF NOT EXISTS idx_name_id ON name(id);
CREATE INDEX IF NOT EXISTS idx_name_lastlogin ON name(last_login);

CREATE TABLE IF NOT EXISTS address (
  id INTEGER(10),
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
  mod_version VARCHAR(12),
  db_version VARCHAR(12)
);
CREATE TABLE IF NOT EXISTS violation (
  src_id INTEGER(10) PRIMARY KEY,
  target_id INTEGER(10),
  ip VARCHAR(50),
  created INTEGER(30)
);


-- create temporary tables for transfering existing data
------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS address_tmp (
	id INTEGER(10),
	ip VARCHAR(50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT (1),
	violation BOOLEAN
);

CREATE TABLE IF NOT EXISTS active_tmp (
	id INTEGER(10) PRIMARY KEY ON CONFLICT IGNORE,
	name VARCHAR(50),
	source VARCHAR(50),
	created INTEGER(30),
	reason VARCHAR(300),
	expires INTEGER(30),
	last_pos VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS fixed (
	id INTEGER(10),
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
	id INTEGER(10),
	name VARCHAR(50) PRIMARY KEY ON CONFLICT IGNORE,
	created INTEGER(30),
	last_login INTEGER(30),
	login_count INTEGER(8) DEFAULT (1)
);

-- transfer existing data to new tables
----------------------------------------------

-- fix any id with a text entry in bans!
INSERT INTO fixed SELECT
	playerdata.id,
	name,
	source,
	created,
	reason,
	expires,
	u_source,
	u_reason,
	u_date,
	active,
	last_pos
FROM bans
	INNER JOIN
	playerdata ON playerdata.name = bans.name
WHERE  typeof(bans.id) = 'text';

DELETE FROM bans WHERE typeof(bans.id) = 'text';
INSERT INTO bans SELECT * FROM fixed;

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
FROM bans WHERE active != 'true' AND typeof(id) = 'integer';

-- insert the active
INSERT INTO active_tmp SELECT
	id,
	name,
	source,
	created,
	reason,
	expires,
	last_pos
FROM bans WHERE active = 'true' AND typeof(id) = 'integer';

INSERT INTO address_tmp (id, ip, created) SELECT DISTINCT id, ip, created FROM playerdata;
INSERT INTO name_tmp (id, name, created, last_login) SELECT DISTINCT id, name, created, last_login FROM playerdata;
INSERT INTO config VALUES('1.1', '0.2.1');
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
DROP TABLE fixed;

COMMIT;

PRAGMA foreign_keys = ON;

VACUUM;
