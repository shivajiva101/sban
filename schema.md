CREATE TABLE active (
    id      INTEGER PRIMARY KEY,
    name    VARCHAR (50),
    source  VARCHAR (50),
    created INTEGER,
    reason  VARCHAR (300),
    expires INTEGER,
    pos     VARCHAR (50) 
);

CREATE TABLE address (
    id          INTEGER,
    ip          VARCHAR PRIMARY KEY,
    created     INTEGER,
    last_login  INTEGER,
    login_count INTEGER DEFAULT (1),
    violation   BOOLEAN
);

CREATE TABLE config (
    mod_version VARCHAR,
    db_version  VARCHAR
);

CREATE TABLE expired (
    id       INTEGER,
    name     VARCHAR (50),
    source   VARCHAR (50),
    created  INTEGER,
    reason   VARCHAR (300),
    expires  INTEGER,
    u_source VARCHAR (50),
    u_reason VARCHAR (300),
    u_date   INTEGER,
    last_pos VARCHAR (50) 
);

CREATE TABLE name (
    id          INTEGER,
    name        VARCHAR (50) PRIMARY KEY,
    created     INTEGER,
    last_login  INTEGER,
    login_count INTEGER (6)  DEFAULT (1) 
);

CREATE TABLE violation (
    src_id    INTEGER (10),
    target_id INTEGER (10),
    ip        TEXT (20),
    created   INTEGER (30) 
);

CREATE TABLE whitelist (
    name    VARCHAR (50),
    source  VARCHAR (50),
    created INTEGER
);
